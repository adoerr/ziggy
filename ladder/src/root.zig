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

const words = blk: {
    @setEvalBranchQuota(1_000_000);
    break :blk parseList(@embedFile("words.txt"));
};

const InvalidWordError = error{
    BadLength,
    NotInWordList,
    NotWordLadder,
};

pub fn validateWord(input: []const u8, last_word: [4]u8) ![4]u8 {
    if (input.len != 4) {
        return error.BadLength;
    }

    const candidate = @as(*const [4]u8, @ptrCast(input.ptr));

    // check that the candidate word is in word list
    for (words) |word| {
        if (std.mem.eql(u8, &word, candidate)) {
            break;
        }
    } else {
        return error.NotInWordList;
    }

    var delta: u32 = 0;

    for (candidate, last_word) |char_a, char_b| {
        if (char_a != char_b) {
            delta += 1;
        }
    }

    if (delta != 1) {
        return error.NotWordLadder;
    }

    return candidate.*;
}
