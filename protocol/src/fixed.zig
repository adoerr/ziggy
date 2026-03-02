//! A 24.8 bit fixed-point number type used in the Wayland wire format in place of floats.

const std = @import("std");

pub const Fixed = enum(i32) {
    // dummy tag for syntax
    _,

    pub fn from(val: anytype) Fixed {
        return switch (@typeInfo(@TypeOf(val))) {
            .int, .comptime_int => @enumFromInt(@as(i32, @intCast(val * 256))),
            .float, .comptime_float => @enumFromInt(@as(i32, @intFromFloat(@round(val * 256)))),
            else => @compileError("Unsupported type."),
        };
    }

    pub fn to(self: Fixed, comptime T: type) T {
        return switch (@typeInfo(T)) {
            .int => @as(T, @intCast(@divTrunc(@as(i32, @intFromEnum(self)), 256))),
            .float => @as(T, @floatFromInt(@as(i32, @intFromEnum(self)))) / 256.0,
            else => @compileError("Unsupported type."),
        };
    }
};

test "to/from int" {
    try std.testing.expectEqual(0, Fixed.from(0).to(i32));
    try std.testing.expectEqual(-1, Fixed.from(-1).to(i16));
    try std.testing.expectEqual(1024, Fixed.from(1024).to(usize));

    try std.testing.expectEqual(4321, Fixed.from(@as(u64, 4321)).to(isize));
}

test "to/from float" {
    try std.testing.expectApproxEqAbs(0.0, Fixed.from(0.0).to(f32), 0.001);
    try std.testing.expectApproxEqAbs(1.2, Fixed.from(1.2).to(f32), 0.001);

    try std.testing.expectApproxEqAbs(3.456, Fixed.from(@as(f64, 3.456)).to(f64), 0.0011);
}

test "float/int" {
    try std.testing.expectEqual(3, Fixed.from(3.201).to(u16));
    try std.testing.expectEqual(15.0, Fixed.from(15).to(f64));
}
