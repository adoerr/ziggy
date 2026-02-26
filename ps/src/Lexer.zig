const std = @import("std");
const ascii = std.ascii;
const log = std.log.scoped(.Lexer);

pub const Lexer = struct {
    input: []const u8,
    pos: usize,

    pub fn init(input: []const u8) Lexer {
        return .{ .input = input, .pos = 0 };
    }

    pub fn next(self: *Lexer) ?[]const u8 {
        while (self.pos < self.input.len) {
            var char = self.input[self.pos];

            // skip whitespace
            if (ascii.isWhitespace(char)) {
                self.pos += 1;
                continue;
            }

            // skip comments starting with `%`
            if (char == '%') {
                while (self.pos < self.input.len and self.input[self.pos] != '\n') : (self.pos += 1) {}
                continue;
            }

            // read token until whitespace of `%` is reached
            const start = self.pos;
            while (self.pos < self.input.len) {
                char = self.input[self.pos];
                if (ascii.isWhitespace(char) or char == '%') break;
                self.pos += 1;
            }

            return self.input[start..self.pos];
        }
        // no token found
        return null;
    }
};
