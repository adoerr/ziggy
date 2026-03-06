//! A 24.8 bit fixed-point number type used in the Wayland wire format in place of floats.

const std = @import("std");

pub const Fixed = enum(i32) {
    _,

    /// Create a `Fixed` storing `value`, which can be either an int, comptime int,
    /// float, or comptime float.
    pub fn from(value: anytype) Fixed {
        return switch (@typeInfo(@TypeOf(value))) {
            .int, .comptime_int => @enumFromInt(@as(i32, @intCast(value * 256))),
            .float, .comptime_float => @enumFromInt(@as(i32, @intFromFloat(@round(value * 256.0)))),
            else => @compileError("Unsupported type."),
        };
    }

    /// Get a `T` from `self` where `T` is either a float or int
    pub fn to(self: Fixed, comptime T: type) T {
        return switch (@typeInfo(T)) {
            .int => @as(T, @intCast(@divTrunc(@as(i32, @intFromEnum(self)), 256))),
            .float => @as(T, @floatFromInt(@as(i32, @intFromEnum(self)))) / 256.0,
            else => @compileError("Unsupported type."),
        };
    }

    /// Equivelant of `self + other`.
    pub fn add(self: Fixed, other: Fixed) Fixed {
        return @enumFromInt(@as(i32, @intFromEnum(self)) + @as(i32, @intFromEnum(other)));
    }

    /// Equivalent of `self += other`.
    pub fn addAssign(self: *Fixed, other: Fixed) void {
        self.* = self.add(other);
    }

    /// Equivalent of `self - other`.
    pub fn sub(self: Fixed, other: Fixed) Fixed {
        return @enumFromInt(@as(i32, @intFromEnum(self)) - @as(i32, @intFromEnum(other)));
    }

    /// Equivalent of `self -= other`.
    pub fn subAssign(self: *Fixed, other: Fixed) void {
        self.* = self.sub(other);
    }

    /// Equivalent of `self * other`.
    pub fn mul(self: Fixed, other: Fixed) Fixed {
        return @enumFromInt(@as(i32, @intFromEnum(self)) * @as(i32, @intFromEnum(other)) >> 8);
    }

    /// Equivalent of `self *= other`.
    pub fn mulAssign(self: *Fixed, other: Fixed) void {
        self.* = self.mul(other);
    }

    /// Equivalent of `self / other`.
    pub fn div(self: Fixed, other: Fixed) Fixed {
        return .from(self.to(f64) / other.to(f64));
    }

    /// Equivalent of `self /= other`.
    pub fn divAssign(self: *Fixed, other: Fixed) void {
        self.* = self.div(other);
    }

    /// Allow for printing of a `Fixed` using the format string `"{d}"`.
    /// It will be printed as an `f64`.
    pub fn formatNumber(self: Fixed, writer: *std.Io.Writer, number: std.fmt.Number) !void {
        try writer.printFloat(self.to(f64), number);
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

test "ops" {
    const fix1 = Fixed.from(12.34);
    const fix2 = Fixed.from(-2);

    try std.testing.expectApproxEqAbs(10.34, fix1.add(fix2).to(f64), 0.01);
    try std.testing.expectApproxEqAbs(14.34, fix1.sub(fix2).to(f64), 0.01);
    try std.testing.expectApproxEqAbs(-24.68, fix1.mul(fix2).to(f64), 0.01);
    try std.testing.expectApproxEqAbs(-6.17, fix1.div(fix2).to(f64), 0.01);

    var fix3 = Fixed.from(4);
    var fix4 = Fixed.from(-2);

    fix3.addAssign(fix4);
    try std.testing.expectEqual(2, fix3.to(i32));

    fix4.subAssign(fix3);
    try std.testing.expectEqual(-4, fix4.to(i32));

    fix3.mulAssign(fix4);
    try std.testing.expectEqual(-8, fix3.to(i32));

    fix4.divAssign(fix3);
    try std.testing.expectApproxEqAbs(0.5, fix4.to(f64), 0.01);
}
