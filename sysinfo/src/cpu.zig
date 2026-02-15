const std = @import("std");
const mem = std.mem;

pub const CPUError = error{
    UnexpectedFormat,
};

pub const Sample = struct {
    idle: u64,
    total: u64,
};

pub inline fn parseLine(_: []const u8) CPUError!Sample {
    return .{ .idle = 0, .total = 0 };
}
