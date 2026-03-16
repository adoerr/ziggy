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
fd_in: Buffer(wire.max_msg_args, std.posix.fd_t) = .{},
fd_out: Buffer(wire.max_msg_args, std.posix.fd_t) = .{},
// next new object id
next_obj_id: u32 = wire.client_min_id,
// free list of available/reusable object ids
obj_id_free_list: std.ArrayList(u32) = .empty,
// client object id range
min_obj_id: u32 = wire.client_min_id,
max_obj_id: u32 = wire.client_max_id,
// last received message header
last_header: ?wire.Header = null,

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

pub const SendError = wire.SerializeError || FlushError || PutFdsError;

/// Sends a Wayland message.
///
/// This function serializes the message arguments and appends them to the outgoing data buffer.
/// It also handles any file descriptors associated with the message, appending them to the
/// outgoing file descriptor buffer.
///
/// If there is not enough space in the buffers, this function attempts to flush the connection.
pub fn sendMessage(self: *Connection, sender_id: u32, comptime len: usize, comptime opcode: u16, args: anytype, fds: []const std.posix.fd_t) SendError!void {
    var buf: [len]u8 = undefined;
    const bytes_written = try wire.serializeMessage(&buf, sender_id, opcode, args);

    self.data_out.putMany(buf[0..bytes_written]) catch {
        @branchHint(.unlikely);
        // not enough space, flush buffers first
        try self.flush();
        try self.data_out.putMany(buf[0..bytes_written]);
    };

    self.putFds(fds) catch |err| switch (err) {
        error.OutOfSpace => {
            @branchHint(.unlikely);
            // not enough space, flush fds first
            try self.flush();
            try self.putFds(fds);
        },
        else => |e| return e,
    };
}

pub const NextMessageError = FlushError || ReadIncomingError || DeserializeMessageError || error{ MessageTooLong, InvalidId };

/// Reads the next Wayland message from the connection.
///
/// This function first flushes any buffered outgoing data. Then it waits for an incoming message,
/// reading data and file descriptors from the socket. Once a complete message is available, it
/// identifies the target object and interface, and attempts to deserialize the message into the
/// provided `Message` union type.
///
/// If the timeout is reached before a message is fully received, `error.Timeout` is returned.
pub fn nextMessage(self: *Connection, comptime Message: type, timeout: std.Io.Timeout) NextMessageError!Message {
    const deadline = timeout.toDeadline(self.io).toTimestamp(self.io);

    try self.flush();

    outer: while (true) {
        const header = self.peekHeader() orelse {
            try self.readIncoming(deadline);
            continue :outer;
        };

        if (header.length > wire.max_msg_size) return error.MessageToLong;

        const data = self.data_in.peek(header.length) orelse {
            try self.readIncoming(deadline);
            continue :outer;
        };
        const body = data[@sizeOf(wire.Header)..];
        const interface = try self.map.getInterface(header.object);
        const message = try self.deserializeMessage(Message, header, interface, body) orelse {
            try self.readIncoming(deadline);
            continue :outer;
        };

        self.last_header = header;
        return message;
    }
}

pub const CreateObjectError = error{ OutOfMemory, OutOfIds, InvalidId, ObjectAlreadyExists };

pub fn createObject(self: *Connection, comptime T: type) CreateObjectError!T {
    // get next object id
    const object_id = id: {
        if (self.obj_id_free_list.pop()) |id| break :id id;
        // check if we ran out of object ids
        if (self.next_obj_id > self.max_obj_id) {
            @branchHint(.unlikely);
            return error.OutOfIds;
        }
        defer self.next_obj_id += 1;
        break :id self.next_obj_id;
    };
    // add object id to interface mapping
    try self.map.add(self.alloc, object_id, T.interface);
    return @enumFromInt(object_id);
}

test "Connection - createObject" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const TestObject = enum(u32) {
        _,
        pub const interface = "test_interface";
    };

    var conn = Connection{
        .stream = undefined,
        .io = undefined,
        .alloc = alloc,
        .map = undefined,
        // obj_id_free_list uses default
        .fd_in = .{}, // defaults
        .fd_out = .{}, // defaults
    };
    conn.map = try ObjectInterfaceMap.init(alloc);
    defer conn.map.deinit(alloc);
    defer conn.obj_id_free_list.deinit(alloc);

    // create first object mapping
    const obj1 = try conn.createObject(TestObject);
    try testing.expectEqual(@as(u32, wire.client_min_id), @intFromEnum(obj1));
    const iface1 = try conn.map.getInterface(@intFromEnum(obj1));
    try testing.expectEqualStrings("test_interface", iface1);

    // create second object
    const obj2 = try conn.createObject(TestObject);
    try testing.expectEqual(@as(u32, wire.client_min_id + 1), @intFromEnum(obj2));

    // reuse of object id
    const obj3 = try conn.createObject(TestObject);
    try testing.expectEqual(@as(u32, wire.client_min_id + 2), @intFromEnum(obj3));
    try conn.releaseObject(@intFromEnum(obj3));
    const obj4 = try conn.createObject(TestObject);
    try testing.expectEqual(@as(u32, wire.client_min_id + 2), @intFromEnum(obj4));

    // OutOfIds error
    conn.next_obj_id = conn.max_obj_id + 1;
    conn.obj_id_free_list.clearRetainingCapacity();
    try testing.expectError(error.OutOfIds, conn.createObject(TestObject));
}

pub const ReleaseObjectError = error{ OutOfMemory, InvalidId };

pub fn releaseObject(self: *Connection, object_id: u32) ReleaseObjectError!void {
    // delete object id to interface mapping
    try self.map.delete(object_id);
    // make object id available again
    try self.obj_id_free_list.append(self.alloc, object_id);
}

test "Connection - releaseObject" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const TestObject = enum(u32) {
        _,
        pub const interface = "test_interface";
    };

    var conn = Connection{
        .stream = undefined,
        .io = undefined,
        .alloc = alloc,
        .map = undefined,
        .fd_in = .{}, // defaults
        .fd_out = .{}, // defaults
    };
    conn.map = try ObjectInterfaceMap.init(alloc);
    defer conn.map.deinit(alloc);
    defer conn.obj_id_free_list.deinit(alloc);

    // create 3 objects
    const obj1 = try conn.createObject(TestObject);
    const obj2 = try conn.createObject(TestObject);
    const obj3 = try conn.createObject(TestObject);
    // verify object ids
    try testing.expectEqual(@as(u32, wire.client_min_id), @intFromEnum(obj1));
    try testing.expectEqual(@as(u32, wire.client_min_id + 1), @intFromEnum(obj2));
    try testing.expectEqual(@as(u32, wire.client_min_id + 2), @intFromEnum(obj3));

    // release multiple objects (LIFO order for reuse)
    try conn.releaseObject(@intFromEnum(obj2));
    try conn.releaseObject(@intFromEnum(obj3));
    // verify object id to interface map deletion
    try testing.expectError(error.InvalidId, conn.map.getInterface(@intFromEnum(obj2)));
    try testing.expectError(error.InvalidId, conn.map.getInterface(@intFromEnum(obj3)));

    // recreate objects - should reuse IDs in LIFO (last released is obj3, then obj2)
    const obj3_new = try conn.createObject(TestObject);
    try testing.expectEqual(@as(u32, wire.client_min_id + 2), @intFromEnum(obj3_new));
    const obj2_new = try conn.createObject(TestObject);
    try testing.expectEqual(@as(u32, wire.client_min_id + 1), @intFromEnum(obj2_new));
    // create another one - should be new ID because free list is empty
    const obj4 = try conn.createObject(TestObject);
    try testing.expectEqual(@as(u32, wire.client_min_id + 3), @intFromEnum(obj4));
}

pub const FlushError = error{ ConnectionClosed, OutOfMemory, Unexpected };

/// Flushes the connection's outgoing buffer to the underlying stream.
///
/// This function sends any buffered data and file descriptors to the server. If the buffer is empty,
/// this function does nothing.
///
/// If the send operation returns `0`, `error.ConnectionClosed` is returned.
pub fn flush(self: *Connection) FlushError!void {
    // nothing to flush
    if (self.data_out.end == 0) return;

    // output data with protocol messages
    const data = self.data_out.slice();
    var iov = [1]std.posix.iovec_const{.{ .base = data.ptr, .len = data.len }};
    // ancillary data object (aka control information) with shared memory file descriptors
    const fds = self.fd_out.slice();
    var ctrl: [cmsg.space(wire.max_msg_args)]u8 = undefined;
    std.mem.bytesAsValue(cmsg.Header, ctrl[0..@sizeOf(cmsg.Header)]).* = .{ .len = cmsg.length(fds.len) };
    // copy file descriptors into control information after the header
    const dest = std.mem.bytesAsSlice(std.posix.fd_t, ctrl[@sizeOf(cmsg.Header)..][0..(fds.len * @sizeOf(std.posix.fd_t))]);
    @memcpy(dest, fds);

    const msg_hdr = std.posix.msghdr_const{
        .name = null,
        .namelen = 0,
        .iov = &iov,
        .iovlen = iov.len,
        .control = &ctrl,
        .controllen = @intCast(cmsg.length(fds.len)),
        .flags = 0,
    };

    const bytes_sent: usize = while (true) {
        const rc = std.posix.system.sendmsg(self.stream.socket.handle, &msg_hdr, 0);
        // error handling,
        switch (std.posix.errno(rc)) {
            //`EPIPE` and `ECONNRESET` are ignored in order to allow clients to handle server disconnects.
            .SUCCESS, .PIPE, .CONNRESET => break @intCast(rc),
            .NOBUFS, .NOMEM => return error.OutOfMemory,
            .AGAIN => unreachable,
            .AFNOSUPPORT => unreachable,
            .BADF => unreachable,
            // retry in case send message sys call got interrupted
            .INTR => continue,
            .INVAL => unreachable,
            .MSGSIZE => unreachable,
            .NOTCONN => unreachable,
            .NOTSOCK => unreachable,
            .OPNOTSUPP => unreachable,
            .IO => unreachable,
            .LOOP => unreachable,
            .NAMETOOLONG => unreachable,
            .NOENT => unreachable,
            .NOTDIR => unreachable,
            .ACCES => unreachable,
            .DESTADDRREQ => unreachable,
            .HOSTUNREACH => unreachable,
            .ISCONN => unreachable,
            .NETDOWN => unreachable,
            .NETUNREACH => unreachable,
            else => |err| return std.posix.unexpectedErrno(err),
        }
    };

    if (bytes_sent == 0) return error.ConnectionClosed;

    for (fds) |fd| _ = std.posix.system.close(fd);
    self.data_out.start = 0;
    self.data_out.end = 0;
    self.fd_out.start = 0;
    self.fd_out.end = 0;
}

const PutFdsError = error{ OutOfSpace, Unexpected };

fn putFds(self: *Connection, fds: []const std.posix.fd_t) PutFdsError!void {
    if (self.fd_out.end + fds.len >= self.fd_out.data.len) return error.OutOfSpace;

    for (fds) |fd| {
        const new_fd = std.posix.system.dup(fd);
        if (std.posix.errno(new_fd) != .SUCCESS) return error.Unexpected;
        // we checked for space at the beginning
        self.fd_out.put(@intCast(new_fd)) catch unreachable;
    }
}

fn peekHeader(self: *const Connection) ?wire.Header {
    const bytes = self.data_in.peek(@sizeOf(wire.Header)) orelse return null;
    return std.mem.bytesToValue(wire.Header, bytes);
}

const ReadIncomingError = std.posix.PollError || error{ ConnectionClosed, Timeout, OutOfMemory, OutOfSpace };

/// Reads incoming data and file descriptors from the connection stream.
///
/// This function waits for data to become available on the socket, respecting the provided
/// `deadline`. If data is available, it reads it into the `data_in` buffer and any
/// associated file descriptors into the `fd_in` buffer.
///
/// If the deadline is reached before any data is received, `error.Timeout` is returned.
/// If the connection is closed by the peer, `error.ConnectionClosed` is returned.
fn readIncoming(self: *Connection, deadline: ?std.Io.Clock.Timestamp) ReadIncomingError!void {
    self.data_in.shiftToStart();
    self.fd_in.shiftToStart();

    // wait indefinitely until an event occurs
    const indefinitely: i32 = -1;
    const timeout: i32 = if (deadline) |d| ms: {
        const remaining = d.durationFromNow(self.io);
        break :ms if (remaining.raw.nanoseconds <= 0) 0 else @intCast(remaining.raw.toMilliseconds());
    } else indefinitely;

    var pfd = [1]std.posix.pollfd{.{ .fd = self.stream.socket.handle, .events = std.posix.POLL.IN, .revents = 0 }};
    if (try std.posix.poll(&pfd, timeout) == 0) return error.Timeout;

    const data = self.data_in.data[self.data_in.end..];
    var iov = [1]std.posix.iovec{.{ .base = data.ptr, .len = data.len }};
    var ctrl: [cmsg.space(wire.max_msg_args)]u8 align(@alignOf(cmsg.Header)) = undefined;

    var msg_hdr = std.posix.msghdr{
        .name = null,
        .namelen = 0,
        .iov = &iov,
        .iovlen = iov.len,
        .control = &ctrl,
        .controllen = ctrl.len,
        .flags = 0,
    };

    const bytes_read = while (true) {
        const rc = std.posix.system.recvmsg(self.stream.socket.handle, &msg_hdr, std.posix.system.MSG.DONTWAIT);
        switch (std.posix.errno(rc)) {
            .SUCCESS => break @as(usize, @intCast(rc)),
            .INTR => continue,
            .AGAIN => continue,
            .INTR => continue,
            .CONNRESET, .PIPE => return error.ConnectionClosed,
            .TIMEDOUT => return error.Timeout,
            .NOBUFS, .NOMEM => return error.OutOfMemory,
            .BADF => unreachable,
            .INVAL => unreachable,
            .MSGSIZE => unreachable,
            .NOTCONN => unreachable,
            .NOTSOCK => unreachable,
            .OPNOTSUPP => unreachable,
            .IO => unreachable,
            else => |err| return std.posix.unexpectedErrno(err),
        }
    };

    if (bytes_read == 0) return error.ConnectionClosed;

    self.data_in.end += bytes_read;
    var header = cmsg.firstHeader(&msg_hdr);
    while (header) |hdr| {
        const fd_bytes: []align(@alignOf(std.posix.fd_t)) const u8 = @alignCast(cmsg.data(hdr));
        const fds = std.mem.bytesAsSlice(std.posix.fd_t, fd_bytes);
        try self.fd_in.putMany(fds);
        header = cmsg.nextHeader(&msg_hdr, hdr);
    }
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
