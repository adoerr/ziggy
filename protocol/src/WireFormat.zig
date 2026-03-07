//! Wayland wire format marshalling and unmarshalling
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
/// it's not specified, a new_id is preceded by a string specifying the interface name, and a uint specifying the version.
pub const NewId = struct {
    interface: [:0]const u8,
    version: u32,
    new_id: u32,

    pub fn init(comptime T: type, version: T.version, new_id: u32) NewId {
        return .{
            .interface = T.interface,
            .version = @intFromEnum(version),
            .new_id = new_id,
        };
    }
};

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
