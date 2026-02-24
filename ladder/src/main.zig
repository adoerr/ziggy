const std = @import("std");
const ladder = @import("ladder");
const Io = std.Io;

pub fn main() !void {
    const last_word = [_]u8{ 's', 'e', 'p', 'p' };
    _ = try ladder.validateWord("hugo", last_word);
}
