const std = @import("std");
const Address = @import("Address.zig");
const ProtocolSide = @import("protocol.zig").ProtocolSide;
const cmsg = @import("ctrl_msg.zig");
const wire = @import("WireFormat.zig");

const log = std.log.scoped(.wayland_connection);

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

    pub fn delete(self: *ObjectInterfaceMap, object_id: u32) error{InvalidId}!void {
        const side = try getSide(object_id);
        const idx = getIndex(object_id, side);
        var interfaces = switch (side) {
            .client => self.client,
            .server => self.server,
        };

        if (idx >= interfaces.len or interfaces[idx] == null) {
            @branchHint(.unlikely);
            log.err("Delete mapping: invalid object ID: {d}", .{object_id});
            return error.InvalidId;
        }
        interfaces[idx] = null;
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
            .server => object_id = wire.server_min_id,
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
            interfaces.ptr = new_memory.ptr;
            // number of current interface entries
            const curr_len = interfaces.len;
            interfaces.len = new_memory.len;
            // init new entries
            for (curr_len..interfaces.len) |i| interfaces[i] = null;
        }
    }
};
