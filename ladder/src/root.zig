const std = @import("std");

pub fn countWords(text: []const u8) usize {
    var count: usize = 0;
    var word_iter = std.mem.tokenizeScalar(u8, text, '\n');

    while (word_iter.next()) |_| {
        count += 1;
    }

    return count;
}
