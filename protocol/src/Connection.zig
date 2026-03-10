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
// regular protocol messages
data_in: Buffer(wire.max_msg_size, u8) = .{},
data_out: Buffer(wire.max_msg_size, u8) = .{},
// (file) descriptor transfer messages
fd_in: Buffer(wire.max_msg_args, std.posix.fd_t),
fd_out: Buffer(wire.max_msg_args, std.posix.fd_t),
// object id management
next_obj_id: u32 = wire.client_min_id,
obj_id_free_list: std.ArrayList(u32) = .empty,
min_obj_id: u32 = wire.client_min_id,
max_obj_id: u32 = wire.client_max_id,

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

pub fn deinit(self: *Connection) void {
    for (self.fd_out.slice()) |fd| _ = std.posix.system.close(fd);
    for (self.fd_in.slice()) |fd| _ = std.posix.system.close(fd);
    self.obj_id_free_list.deinit(self.alloc);
    self.map.deinit(self.alloc);
    self.stream.close(self.io);
    self.* = undefined;
}

const DeserializeMessageError = wire.DeserializeError || error{ UnsupportedInterface, InvalidOpcode };

fn deserializeMessage(self: *Connection, comptime Message: type, header: wire.Header, interface: [:0]const u8, body: []const u8) DeserializeMessageError!?Message {
    @setEvalBranchQuota(10000);

    const msg = @typeInfo(Message).@"union";

    inline for (msg.fields) |field| if (std.mem.eql(u8, field.name, interface)) {
        const sub_fields = @typeInfo(field.type).@"union".fields;
        switch (header.opcode) {
            0...sub_fields.len - 1 => |i| {
                const sub_field = sub_fields[i];

                const fd_count = countFds(sub_field.type);
                const fds = self.fd_in.peek(fd_count) orelse return null;

                self.data_in.discard(header.length) catch unreachable;
                self.fd_in.discard(fd_count) catch unreachable;

                var message = try wire.deserializeMessage(sub_field.type, body, fds);
                const object_self_field = std.meta.fields(@TypeOf(message))[0];
                @field(message, object_self_field.name) = @enumFromInt(header.object);

                const interface_message = @unionInit(field.type, sub_field.name, message);
                return @unionInit(Message, field.name, interface_message);
            },
            else => return error.InvalidOpcode,
        }
    };

    return error.UnsupportedInterface;
}

fn countFds(comptime T: type) usize {
    comptime var count: usize = 0;
    inline for (T._signature) |byte| if (byte == 'd') {
        count += 1;
    };
    return count;
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

        /// Append an item to the buffer. Return `error.OutOfSpace` if the buffer is full.
        pub fn put(self: *Self, item: T) PutError!void {
            if (self.end + 1 >= self.data.len) return error.OutOfSpace;
            self.data[self.end] = item;
            self.end += 1;
        }

        /// Append multiple items to the buffer. Return `error.OutOfSpace` if the buffer doesn't have enough space.
        pub fn putMany(self: *Self, data: []const T) PutError!void {
            if (self.end + data.len >= self.data.len) return error.OutOfSpace;
            @memcpy(self.data[self.end..][0..data.len], data);
            self.end += data.len;
        }

        /// Return a slice of the first `n` items from the buffer without removing them. Return `null` if `n` is
        /// larger than the number of available items.
        pub fn peek(self: *Self, n: usize) ?[]const T {
            if (n > self.end - self.start) return null;
            return self.data[self.start..][0..n];
        }

        pub const SkipError = error{SkipTooLong};

        /// Skip `n` items from the start of the buffer. Return `error.SkipTooLong` if `n` is larger than the number
        /// of available items.
        pub fn skip(self: *Self, n: usize) SkipError!void {
            if (n > self.end - self.start) return error.SkipTooLong;
            self.start += n;
            if (self.start == self.end) {
                self.start = 0;
                self.end = 0;
            }
        }

        /// Shift the valid items to the beginning of the underlying array to reclaim space.
        pub fn shiftToStart(self: *Self) void {
            if (self.start == 0) return;
            const len = self.end - self.start;
            @memmove(self.data[0..len], self.data[self.start..self.end]);
            self.start = 0;
            self.end = len;
        }

        /// Return a slice of the valid items in the buffer.
        pub fn slice(self: *Self) []T {
            return self.data[self.start..self.end];
        }
    };
}

test "Buffer - basic usage" {
    const testing = std.testing;
    const Buf = Buffer(10, u8);
    var buf = Buf{};

    try testing.expectEqual(@as(usize, 0), buf.start);
    try testing.expectEqual(@as(usize, 0), buf.end);
    try testing.expectEqual(@as(usize, 0), buf.slice().len);

    try buf.put(1);
    try buf.put(2);
    try buf.put(3);

    const s = buf.slice();
    try testing.expectEqual(@as(usize, 3), s.len);
    try testing.expectEqual(@as(u8, 1), s[0]);
    try testing.expectEqual(@as(u8, 2), s[1]);
    try testing.expectEqual(@as(u8, 3), s[2]);
}

test "Buffer - putMany" {
    const testing = std.testing;
    const Buf = Buffer(10, u8);
    var buf = Buf{};

    const data = [_]u8{ 1, 2, 3, 4, 5 };
    try buf.putMany(&data);

    try testing.expectEqual(@as(usize, 5), buf.slice().len);
    try testing.expectEqualSlices(u8, &data, buf.slice());

    // Test overflow
    const overflow = [_]u8{ 6, 7, 8, 9, 10, 11 };
    try testing.expectError(Buf.PutError.OutOfSpace, buf.putMany(&overflow));
}

test "Buffer - peek" {
    const testing = std.testing;
    const Buf = Buffer(10, u8);
    var buf = Buf{};

    try buf.put(10);
    try buf.put(20);

    const p1 = buf.peek(1);
    try testing.expect(p1 != null);
    try testing.expectEqual(@as(u8, 10), p1.?[0]);
    try testing.expectEqual(@as(usize, 1), p1.?.len);

    const p2 = buf.peek(2);
    try testing.expect(p2 != null);
    try testing.expectEqualSlices(u8, &[_]u8{ 10, 20 }, p2.?);

    const p3 = buf.peek(3);
    try testing.expect(p3 == null);
}

test "Buffer - skip and shiftToStart" {
    const testing = std.testing;
    const Buf = Buffer(11, u8);
    var buf = Buf{};

    try buf.putMany(&[_]u8{ 1, 2, 3, 4, 5 });

    try buf.skip(2);
    try testing.expectEqual(@as(usize, 2), buf.start);
    try testing.expectEqual(@as(usize, 5), buf.end);
    try testing.expectEqualSlices(u8, &[_]u8{ 3, 4, 5 }, buf.slice());

    buf.shiftToStart();
    try testing.expectEqual(@as(usize, 0), buf.start);
    try testing.expectEqual(@as(usize, 3), buf.end);
    try testing.expectEqualSlices(u8, &[_]u8{ 3, 4, 5 }, buf.slice());

    // Fill up the rest with 7 items. Buffer size is 11 (max 10). We have 3 items. 10 - 3 = 7.
    try buf.putMany(&[_]u8{ 6, 7, 8, 9, 10, 11, 12 });
    try testing.expectEqual(@as(usize, 10), buf.slice().len);
    try testing.expectEqualSlices(u8, &[_]u8{ 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 }, buf.slice());
}

test "Buffer - skip fully" {
    const testing = std.testing;
    const Buf = Buffer(5, u8);
    var buf = Buf{};

    try buf.putMany(&[_]u8{ 1, 2, 3 });
    try buf.skip(3); // Skip all

    // Should reset to 0,0
    try testing.expectEqual(@as(usize, 0), buf.start);
    try testing.expectEqual(@as(usize, 0), buf.end);
    try testing.expectEqual(@as(usize, 0), buf.slice().len);
}

test "Buffer - errors" {
    const testing = std.testing;
    const Buf = Buffer(3, u8);
    var buf = Buf{};

    try buf.put(1);
    try buf.put(2);
    try testing.expectError(Buf.PutError.OutOfSpace, buf.put(3));

    try testing.expectError(Buf.SkipError.SkipTooLong, buf.skip(3));
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
