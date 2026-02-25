const std = @import("std");
const log = std.log.scoped(.Lexer);

pub const Lexer = struct {
    input: []const u8,
    pos: usize,
};

pub fn init(input: []const u8) Lexer {
    log.debug("code:\n {s}", .{input});
    return .{ .input = input, .pos = 0 };
}
