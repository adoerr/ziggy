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

test "Lexer.next" {
    const testing = std.testing;

    const code =
        \\ % This is a comment
        \\ 10 20 add       % 10 + 20 = 30
        \\ 5.5 mul         % 30 * 5.5 = 165.0
        \\ /my_variable    % push a literal name
        \\ 100 20 div      % 100 / 20 = 5
        \\ pstack          % Should print: 5 \n /my_variable \n 165
    ;

    var lexer = Lexer.init(code);

    try testing.expectEqualStrings("10", lexer.next().?);
    try testing.expectEqualStrings("20", lexer.next().?);
    try testing.expectEqualStrings("add", lexer.next().?);

    try testing.expectEqualStrings("5.5", lexer.next().?);
    try testing.expectEqualStrings("mul", lexer.next().?);

    try testing.expectEqualStrings("/my_variable", lexer.next().?);

    try testing.expectEqualStrings("100", lexer.next().?);
    try testing.expectEqualStrings("20", lexer.next().?);
    try testing.expectEqualStrings("div", lexer.next().?);

    try testing.expectEqualStrings("pstack", lexer.next().?);

    try testing.expect(lexer.next() == null);
}
