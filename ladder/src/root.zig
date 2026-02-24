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
    return comptime blk: {
        var word_list: [countWords(list)][4]u8 = undefined;
        var idx: usize = 0;
        var iter = mem.tokenizeScalar(u8, list, '\n');

        while (iter.next()) |word| : (idx += 1) {
            if (word.len != 4) @compileError("All words must be 4 letters");
            word_list[idx] = word[0..4].*;
        }
        break :blk word_list;
    };
}
