const std = @import("std");
const mem = std.mem;

pub const CPUError = error{
    InvalidFormat,
};

pub const Sample = struct {
    idle: u64,
    total: u64,
};

pub inline fn parseLine(line: []const u8) CPUError!Sample {
    // remove everything up to the first numerical value
    _, const after = mem.cutScalar(u8, line, ' ') orelse return CPUError.InvalidFormat;
    const values = mem.trimStart(u8, after, " ");

    std.debug.print("Values: '{s}'\n", .{values});

    return .{ .idle = 0, .total = 0 };
}

test "parseLine" {
    const line = "cpu  218940 1325 115910 98319183 16321 0 3538 0 0 0";
    _ = try parseLine(line);
}
