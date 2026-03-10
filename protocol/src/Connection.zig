const std = @import("std");

const Address = @import("Address.zig");
const ProtocolSide = @import("protocol.zig").ProtocolSide;
const cmsg = @import("ctrl_msg.zig");
const wire = @import("WireFormat.zig");

const log = std.log.scoped(.wayland_connection);

const Connection = @This();

stream: std.Io.net.Stream,
io: std.Io,
alloc: std.mem.Allocator,
map: ObjectInterfaceMap,

pub const InitError = std.Io.net.UnixAddress.ConnectError || error{OutOfMemory};

pub fn init(io: std.Io, alloc: std.mem.Allocator, address: Address) !Connection {
    var map: ObjectInterfaceMap = try .init(alloc);
    errdefer map.deinit(alloc);

    const stream = try connect(io, address);

    return Connection{
        .stream = stream,
        .io = io,
        .alloc = alloc,
        .map = map,
    };
}

fn connect(io: std.Io, address: Address) std.Io.net.UnixAddress.ConnectError!std.Io.net.Stream {
    return switch (address.info) {
        .sock => |sock| std.Io.net.Stream{ .socket = .{
            .handle = sock,
            .address = .{ .ip4 = .loopback(0) },
        } },
        .path => |path| stream: {
            const addr = std.Io.net.UnixAddress.init(std.mem.sliceTo(&path, 0)) catch unreachable;
            break :stream addr.connect(io);
        },
    };
}

/// Typed buffer for Wayland protocol messages
fn Buffer(comptime length: usize, comptime T: type) type {
    return struct {
        const Self = @This();

        data: [length]T = undefined,
        start: usize = 0,
        end: usize = 0,

        pub const PutError = error{OutOfSpace};

        pub fn put(self: *Self, item: T) PutError!void {
            if (self.end + 1 >= self.data.len) return error.OutOfSpace;
            self.data[self.end] = item;
            self.end += 1;
        }

        pub fn putMany(self: *Self, data: []const T) PutError!void {
            if (self.end + data.len >= self.data.len) return error.OutOfSpace;
            @memcpy(self.data[self.end..][0..data.len], data);
            self.end += data.len;
        }

        pub fn peek(self: *Self, index: usize) ?[]const T {
            if (index > self.end - self.start) return null;
            return self.data[self.start..][0..index];
        }

        pub const SkipError = error{SkipTooLong};

        // Skip `n` items
        pub fn skip(self: *Self, n: usize) SkipError!void {
            if (n > self.end - self.start) return error.SkipTooLong;
            self.start += n;
            if (self.start == self.end) {
                self.start = 0;
                self.end = 0;
            }
        }

        pub fn shiftToStart(self: *Self) void {
            if (self.start == 0) return;
            const len = self.end - self.start;
            @memmove(self.data[0..len], self.data[self.start..self.end]);
            self.start = 0;
            self.end = len;
        }

        pub fn slice(self: *Self) []T {
            return self.data[self.start..self.end];
        }
    };
}

/// A map of object IDs to wayland interfaces
const ObjectInterfaceMap = struct {
    client: []?[:0]const u8,
    server: []?[:0]const u8,

    pub fn init(alloc: std.mem.Allocator) error{OutOfMemory}!ObjectInterfaceMap {
        var client_buf = try alloc.alloc(?[:0]const u8, 16);
        errdefer alloc.free(client_buf);
        @memset(client_buf, null);
        // object id `1` preassigned (client map idx = object id - 1)
        client_buf[0] = "wl_display";

        const server_buf = try alloc.alloc(?[:0]const u8, 4);
        errdefer alloc.free(server_buf);
        @memset(server_buf, null);

        return ObjectInterfaceMap{ .client = client_buf, .server = server_buf };
    }

    pub fn deinit(self: *ObjectInterfaceMap, alloc: std.mem.Allocator) void {
        alloc.free(self.client);
        alloc.free(self.server);
    }

    /// Add a mapping from `object_id` to `interface`
    pub fn add(self: *ObjectInterfaceMap, alloc: std.mem.Allocator, object_id: u32, interface: [:0]const u8) error{ OutOfMemory, InvalidId, ObjectAlreadyExists }!void {
        const side = try getSide(object_id);
        const idx = getIndex(object_id, side);
        try self.ensureCapacity(alloc, idx, side);

        const interfaces = switch (side) {
            .client => self.client,
            .server => self.server,
        };

        if (interfaces[idx] != null) {
            @branchHint(.unlikely);
            return error.ObjectAlreadyExists;
        }
        interfaces[idx] = interface;
    }

    /// Delete interface mapping for `object_id`
    pub fn delete(self: *ObjectInterfaceMap, object_id: u32) error{InvalidId}!void {
        const side = try getSide(object_id);
        const idx = getIndex(object_id, side);
        var interfaces = switch (side) {
            .client => self.client,
            .server => self.server,
        };

        if (idx >= interfaces.len or interfaces[idx] == null) {
            @branchHint(.unlikely);
            log.debug("Delete mapping: invalid object ID: {d}", .{object_id});
            return error.InvalidId;
        }
        interfaces[idx] = null;
    }

    /// Return interface which `object_id` has been mapped to
    pub fn getInterface(self: *ObjectInterfaceMap, object_id: u32) error{InvalidId}![:0]const u8 {
        const side = try getSide(object_id);
        const idx = getIndex(object_id, side);
        var interfaces = switch (side) {
            .client => self.client,
            .server => self.server,
        };
        // check if `object_id` resulted in an out-of-bounds index
        if (idx >= interfaces.len) return error.InvalidId;
        return interfaces[idx] orelse error.InvalidId;
    }

    /// Return the protocol side based on `object_id`
    fn getSide(object_id: u32) error{InvalidId}!ProtocolSide {
        return switch (object_id) {
            1, wire.client_min_id...wire.client_max_id => .client,
            wire.server_min_id...wire.server_max_id => .server,
            else => error.InvalidId,
        };
    }

    /// Return map index for `object_id` based on the protocol side
    fn getIndex(object_id: u32, side: ProtocolSide) usize {
        return switch (side) {
            .client => object_id - 1,
            .server => object_id - wire.server_min_id,
        };
    }

    /// Ensure that the internal object ID to interface map has enough capacity
    fn ensureCapacity(self: *ObjectInterfaceMap, alloc: std.mem.Allocator, index: usize, side: ProtocolSide) error{ InvalidId, OutOfMemory }!void {
        var interfaces = switch (side) {
            .client => self.client,
            .server => self.server,
        };

        if (index > interfaces.len) return error.InvalidId;
        // check if map is at capacity
        if (index == interfaces.len) {
            const new_capacity = interfaces.len * 2;
            const new_memory = alloc.remap(interfaces, new_capacity) orelse mem: {
                // remap would be equivalent to allocating new memory, we do this ourselves
                const new_memory = try alloc.alloc(?[:0]const u8, new_capacity);
                // copy existing interfaces to the beginning of the newly allocated memory
                @memcpy(new_memory[0..interfaces.len], interfaces);
                // free existing memory allocation
                alloc.free(interfaces);
                break :mem new_memory;
            };

            // init new entries
            for (interfaces.len..new_memory.len) |i| new_memory[i] = null;
            // use the new allocation
            switch (side) {
                .client => self.client = new_memory,
                .server => self.server = new_memory,
            }
        }
    }
};

test "ObjectInterfaceMap - init/deinit" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var map = try ObjectInterfaceMap.init(alloc);
    defer map.deinit(alloc);

    // Initial state check
    try testing.expectEqualStrings("wl_display", (try map.getInterface(1)));
}

test "ObjectInterfaceMap - add/get client" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var map = try ObjectInterfaceMap.init(alloc);
    defer map.deinit(alloc);

    // Test adding and retrieving client-side interfaces
    const client_id: u32 = 2;
    try map.add(alloc, client_id, "wl_registry");
    try testing.expectEqualStrings("wl_registry", (try map.getInterface(client_id)));
}

test "ObjectInterfaceMap - add/get server" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var map = try ObjectInterfaceMap.init(alloc);
    defer map.deinit(alloc);

    // Test adding and retrieving server-side interfaces
    const server_id: u32 = wire.server_min_id;
    try map.add(alloc, server_id, "wl_output");
    try testing.expectEqualStrings("wl_output", (try map.getInterface(server_id)));
}

test "ObjectInterfaceMap - duplicate add" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var map = try ObjectInterfaceMap.init(alloc);
    defer map.deinit(alloc);

    const client_id: u32 = 2;
    try map.add(alloc, client_id, "wl_registry");
    // Test duplicate add
    try testing.expectError(error.ObjectAlreadyExists, map.add(alloc, client_id, "wl_shm"));
}

test "ObjectInterfaceMap - delete" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var map = try ObjectInterfaceMap.init(alloc);
    defer map.deinit(alloc);

    const client_id: u32 = 2;
    try map.add(alloc, client_id, "wl_registry");

    // Test delete
    try map.delete(client_id);
    try testing.expectError(error.InvalidId, map.getInterface(client_id));
    // Test delete invalid ID (already deleted)
    try testing.expectError(error.InvalidId, map.delete(client_id));
}

test "ObjectInterfaceMap - invalid access" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var map = try ObjectInterfaceMap.init(alloc);
    defer map.deinit(alloc);

    // Test invalid ID retrieval
    try testing.expectError(error.InvalidId, map.getInterface(99999));
    // Invalid ID (0 is invalid)
    try testing.expectError(error.InvalidId, map.getInterface(0));
}

test "ObjectInterfaceMap - capacity expansion" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var map = try ObjectInterfaceMap.init(alloc);
    defer map.deinit(alloc);

    // Test capacity expansion. The initial client capacity is 16. We add enough items to force a resize.
    var i: u32 = 3;
    while (i <= 33) : (i += 1) {
        try map.add(alloc, i, "test_interface");
    }
    try testing.expectEqualStrings("test_interface", (try map.getInterface(33)));
}

test "ObjectInterfaceMap - getSide" {
    const testing = std.testing;

    // Test client side range
    try testing.expectEqual(ProtocolSide.client, try ObjectInterfaceMap.getSide(1));
    try testing.expectEqual(ProtocolSide.client, try ObjectInterfaceMap.getSide(wire.client_min_id));
    try testing.expectEqual(ProtocolSide.client, try ObjectInterfaceMap.getSide(wire.client_max_id));
    // Test server side range
    try testing.expectEqual(ProtocolSide.server, try ObjectInterfaceMap.getSide(wire.server_min_id));
    try testing.expectEqual(ProtocolSide.server, try ObjectInterfaceMap.getSide(wire.server_max_id));
    // Test invalid IDs
    try testing.expectError(error.InvalidId, ObjectInterfaceMap.getSide(0));
}

test "ObjectInterfaceMap - getIndex" {
    const testing = std.testing;

    // Test client side indexing
    try testing.expectEqual(@as(usize, 0), ObjectInterfaceMap.getIndex(1, .client));
    try testing.expectEqual(@as(usize, 1), ObjectInterfaceMap.getIndex(2, .client));
    // Test server side indexing
    try testing.expectEqual(@as(usize, 0), ObjectInterfaceMap.getIndex(wire.server_min_id, .server));
    try testing.expectEqual(@as(usize, 1), ObjectInterfaceMap.getIndex(wire.server_min_id + 1, .server));
}

test "ObjectInterfaceMap - ensureCapacity" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var map = try ObjectInterfaceMap.init(alloc);
    defer map.deinit(alloc);

    // Initial capacity is 16 for client. Index 16 is the 17th element, requiring resizing. Calling private ensureCapacity directly
    try map.ensureCapacity(alloc, 16, .client);
    // Check if capacity increased (not directly observable without inspecting private fields, but the slice length should have increased)
    try testing.expect(map.client.len > 16);
    // Trying to ensure invalid capacity (index > len) without contiguous growth logic? The ensureCapacity implementations logic checks,
    // `if (index > interfaces.len) return error.InvalidId;` It only allows growing by 1 step at the boundary `(index == len)`.
    try testing.expectError(error.InvalidId, map.ensureCapacity(alloc, 100, .client));
}
