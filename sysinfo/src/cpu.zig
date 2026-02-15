const std = @import("std");
const mem = std.mem;
const fmt = std.fmt;

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

    var it = mem.tokenizeScalar(u8, values, ' ');

    var fields: [8]u64 = .{ 0, 0, 0, 0, 0, 0, 0, 0 };
    var idx: usize = 0;

    while (it.next()) |tok| {
        if (idx >= 8) break;
        fields[idx] = fmt.parseInt(u64, tok, 10) catch return CPUError.InvalidFormat;
        idx += 1;
    }

    // we want at least `user`, `nice`, `system` and `idle` times
    if (idx < 4) return CPUError.InvalidFormat;

    const sum_idle = fields[3] + fields[4]; //`idle` and `iowait`
    const sum_bussy = fields[0] + fields[1] + fields[2] + fields[5] + fields[6] + fields[7];

    return .{ .idle = sum_idle, .total = sum_bussy };
}

const testing = std.testing;

test "parseLine" {
    // valid cpu line
    const line = "cpu  218940 1325 115910 98319183 16321 0 3538 0 0 0";
    const sample = try parseLine(line);
    try testing.expectEqual(@as(u64, 98335504), sample.idle);
    try testing.expectEqual(@as(u64, 339713), sample.total);

    // value core line (cpu10)
    const line2 = "cpu10 1989 3 1458 4353320 112 0 7 0 0 0";
    const sample2 = try parseLine(line2);
    try testing.expectEqual(@as(u64, 4353432), sample2.idle);
    try testing.expectEqual(@as(u64, 3457), sample2.total);

    // missing field (less than 4)
    const line3 = "btime 1771145266";
    try testing.expectError(CPUError.InvalidFormat, parseLine(line3));

    // bad format (non numerical)
    const line4 = "cpu9 3555 13 3030 alpha 284 0 6 0 0 0";
    try testing.expectError(CPUError.InvalidFormat, parseLine(line4));
}
