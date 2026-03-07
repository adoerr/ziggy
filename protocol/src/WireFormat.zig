//! Wayland wire format serialization and deserialization.
//!
//! The wire protocol is a stream of 32-bit values, encoded with the host's byte order (e.g. little-endian on x86 family CPUs).

const std = @import("std");
const builtin = @import("builtin");

const Fixed = @import("fixed.zig").Fixed;

const log = std.log.scoped(.WireFormat);

// Max values match `libwayland`
pub const max_msg_size = 4096;
pub const max_msg_args = 20;
// Client object ID allocation range
pub const client_min_id = 0x00000002;
pub const client_max_id = 0xfeffffff;
// Server object ID allocation range
pub const server_min_id = 0xff000000;
pub const server_max_id = 0xfffffffe;

/// The message header is two words. The first word is the sender object ID. The second is two 16-bit values; the upper
/// 16 bits are the size of the message (including the header itself) and the lower 16 bits are the event or request opcode.
pub const Header = switch (builtin.target.cpu.arch.endian()) {
    .little => extern struct {
        object: u32,
        opcode: u16,
        length: u16,
    },
    .big => extern struct {
        object: u32,
        length: u16,
        opcode: u16,
    },
};

/// The 32-bit object ID. Generally, the interface used for the new object is inferred from the xml, but in the case where
/// it's not specified, a new_id is preceded by a string specifying the interface name, and a `uint` specifying the version.
pub const NewId = struct {
    interface: [:0]const u8,
    version: u32,
    new_id: u32,

    pub fn init(comptime T: type, version: T.Version, new_id: u32) NewId {
        return .{
            .interface = T.interface,
            .version = @intFromEnum(version),
            .new_id = new_id,
        };
    }
};

fn serializeInt(buffer: []u8, int: i32) usize {
    std.mem.bytesAsValue(i32, buffer[0..@sizeOf(i32)]).* = int;
    return @sizeOf(i32);
}

test "serializeInt" {
    var buf: [4]u8 = undefined;
    try std.testing.expectEqual(4, serializeInt(&buf, -65536));
    try std.testing.expectEqual(-65536, std.mem.bytesToValue(i32, &buf));
}

fn serializeUint(buffer: []u8, uint: u32) usize {
    std.mem.bytesAsValue(u32, buffer[0..@sizeOf(u32)]).* = uint;
    return @sizeOf(u32);
}

test "serializeUint" {
    var buf: [4]u8 = undefined;
    try std.testing.expectEqual(4, serializeUint(&buf, 65536));
    try std.testing.expectEqual(65536, std.mem.bytesToValue(u32, &buf));
}

/// Serialize an optional object as it's ID, or zero if `null`. Return `@sizeOf(u32)`
fn serializeOptionalObject(buffer: []u8, object: anytype) usize {
    return serializeUint(buffer, if (object) |o| o.getId() else 0);
}

test "serializeOptionalObject" {
    const obj1: ?TestInterface = @enumFromInt(42);
    const obj2: ?TestInterface = null;

    var buf: [4]u8 = undefined;
    try std.testing.expectEqual(4, serializeOptionalObject(&buf, obj1));
    try std.testing.expectEqual(42, std.mem.bytesToValue(u32, &buf));
    try std.testing.expectEqual(4, serializeOptionalObject(&buf, obj2));
    try std.testing.expectEqual(TestInterface.invalid, std.mem.bytesToValue(TestInterface, &buf));
}

/// Serialize the backing i32 of a `Fixed`. Return `@sizeof(i32)`
fn serializeFixed(buffer: []u8, fixed: Fixed) usize {
    return serializeInt(buffer, @intFromEnum(fixed));
}

test "serializeFixed" {
    var buf: [4]u8 = undefined;
    try std.testing.expectEqual(4, serializeFixed(&buf, .from(2.1)));
    try std.testing.expectApproxEqAbs(2.1, std.mem.bytesToValue(Fixed, &buf).to(f64), 0.01);
}

/// Serialize `string` by starting with an unsigned 32-bit length (including null
/// terminator), followed by the UTF-8 encoded string contents, including terminating
/// null byte, then padding to a 32-bit boundary. A null value is represented with
/// a length of 0. Interior null bytes are not permitted.
fn serializeString(buffer: []u8, string: [:0]const u8) usize {
    // unsigned 32-big string length
    const idx = serializeUint(buffer, @intCast(string.len + 1));
    // followed by string content
    @memcpy(buffer[idx..][0..string.len], string);
    // terminating null value
    buffer[idx + string.len] = 0;
    // align length of serialized string to a 32-bit boundary
    return idx + alignTo4(string.len + 1);
}

test "serializeString" {
    const message = "hello, world";
    var buf: [20]u8 = undefined;
    try std.testing.expectEqual(buf.len, serializeString(&buf, message));
    const len = std.mem.bytesToValue(u32, buf[0..4]);
    try std.testing.expectEqual(message.len + 1, len);
    try std.testing.expectEqualSlices(u8, message, buf[4..][0..message.len]);
}

/// If `string` is not `null` serialize it as a regular string, otherwise zero
/// is used as a sentinel for no content. Return `sizeof(u32)`
fn serializeOptionalString(buffer: []u8, string: ?[:0]const u8) usize {
    return if (string) |s|
        serializeString(buffer, s)
    else
        serializeUint(buffer, 0);
}

test "serializeOptionalString" {
    const message = "optional hello, world";
    var buf: [28]u8 = undefined;
    try std.testing.expectEqual(buf.len, serializeOptionalString(&buf, message));
    const len = std.mem.bytesToValue(u32, buf[0..4]);
    try std.testing.expectEqual(message.len + 1, len);
    try std.testing.expectEqualSlices(u8, message, buf[4..][0..message.len]);
    // serialize `null` string
    try std.testing.expectEqual(4, serializeOptionalString(&buf, null));
    const len2 = std.mem.bytesToValue(u32, buf[0..4]);
    try std.testing.expectEqual(0, len2);
}

/// Serialize `new_id` as a string specifying the interface, followed by the
/// interface version as a `uint`, followed by the  object ID itself also a `uint`.
fn serializeNewId(buffer: []u8, new_id: NewId) usize {
    var idx = serializeString(buffer, new_id.interface);
    idx += serializeUint(buffer[idx..], new_id.version);
    return idx + serializeUint(buffer[idx..], new_id.new_id);
}

test "serializeNewId" {
    const new_id: NewId = .init(TestInterface, .v2, 42);
    var buf: [24]u8 = undefined;
    try std.testing.expectEqual(buf.len, serializeNewId(&buf, new_id));

    const len = std.mem.bytesToValue(u32, buf[0..4]);
    try std.testing.expectEqual(TestInterface.interface.len + 1, len);
    const bytes = buf[4..][0..TestInterface.interface.len];
    try std.testing.expectEqualSlices(u8, TestInterface.interface, bytes);
    try std.testing.expectEqual(2, std.mem.bytesToValue(u32, buf[16..20]));
    try std.testing.expectEqual(42, std.mem.bytesToValue(u32, buf[20..24]));
}

/// Return the message size in bytes starting at the header (i.e. every message
/// has at least a minimum size of 8).
///
/// `args` is an anonymous struct literal containing all the message arguments.
fn messageLength(args: anytype) u16 {
    var length: u16 = @intCast(@sizeOf(Header));

    // iterate over the message arguments struct
    inline for (@typeInfo(@TypeOf(args)).@"struct".fields) |field| {
        const f = @field(args, field.name);
        length += switch (field.type) {
            []const u8 => @intCast(alignTo4(f.len) + 4),
            [:0]const u8 => @intCast(alignTo4(f.len + 1) + 4),
            ?[:0]const u8 => if (f) |s| @intCast(alignTo4(s.len + 1) + 4) else 4,
            NewId => @intCast(alignTo4(f.interface.len + 1) + 12),
            else => 4,
        };
    }

    return length;
}

test "messageLength" {
    const new_id = @as(NewId, .{ .interface = "test", .version = 1, .new_id = 100 });
    const args = .{
        @as(i32, -1), // + 4 = 12
        @as(u32, 2), // + 4 = 16
        Fixed.from(12.34), // + 4 = 20
        @as(?[:0]const u8, null), // + 4 = 24
        new_id, // + 8 + 12 = 44
        @as([]const u8, &.{ 0, 1, 2, 3, 4 }), // + 4 + 8 = 56
    };

    try std.testing.expectEqual(56, messageLength(args));
}

/// Round `value` up to the next multiple of 4
fn alignTo4(value: anytype) @TypeOf(value) {
    const T = @TypeOf(value);
    return switch (@typeInfo(T)) {
        .int => (value + 3) & ~@as(T, 3),
        else => @compileError("alignTo4: Invalid type"),
    };
}

test "alignTo4" {
    try std.testing.expectEqual(0, alignTo4(@as(usize, 0)));
    try std.testing.expectEqual(4, alignTo4(@as(usize, 4)));
    try std.testing.expectEqual(4, alignTo4(@as(usize, 3)));
    try std.testing.expectEqual(24, alignTo4(@as(u18, 21)));
    try std.testing.expectEqual(100, alignTo4(@as(u16, 97)));
    try std.testing.expectEqual(1024, alignTo4(@as(u32, 1021)));
    try std.testing.expectEqual(1024, alignTo4(@as(u32, 1022)));
    try std.testing.expectEqual(1024, alignTo4(@as(u32, 1023)));
    try std.testing.expectEqual(1024, alignTo4(@as(u32, 1024)));
}

/// Mock interface for serialization and deserialization unit testing. This
/// interface mirrors the interfaces which are generated by the scanner.
const TestInterface = enum(u32) {
    invalid = 0,
    _,

    const interface = "wl_foobar";

    const Version = enum(u32) {
        v1 = 1,
        v2 = 2,
    };

    fn getId(self: TestInterface) u32 {
        return @intFromEnum(self);
    }
};
