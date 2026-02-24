const std = @import("std");
const mem = std.mem;

/// Count newline delemited words in `text`
pub fn countWords(text: []const u8) usize {
    var count: usize = 0;
    var word_iter = mem.tokenizeScalar(u8, text, '\n');

    while (word_iter.next()) |_| : (count += 1) {}

    return count;
}

/// Parse `list` into an array of 4-letter words
pub fn parseList(comptime list: []const u8) [countWords(list)][4]u8 {
    var word_list: [countWords(list)][4]u8 = undefined;
    var idx: usize = 0;
    var iter = mem.tokenizeScalar(u8, word_list, '\n');

    while (iter.next()) |word| : (idx += 1) {
        word_list[idx] = @as(*const [word.len]u8, @ptrCast(word.ptr)).*;
    }

    return word_list;
}
