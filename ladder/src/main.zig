const std = @import("std");
const ladder = @import("ladder");
const Io = std.Io;

pub fn main() !void {
    const words = blk: {
        @setEvalBranchQuota(1_000_000);
        break :blk ladder.parseList(@embedFile("words.txt"));
    };

    std.debug.print("word list length: {}\n", .{words.len});
}
