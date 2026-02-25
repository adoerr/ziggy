const std = @import("std");
const Io = std.Io;

const ps = @import("ps");

pub fn main(_: std.process.Init) !void {
    // sample PostScript snippet to test our Lexer and RPN logic
    const code =
        \\ % This is a comment
        \\ 10 20 add       % 10 + 20 = 30
        \\ 5.5 mul         % 30 * 5.5 = 165.0
        \\ /my_variable    % push a literal name
        \\ 100 20 div      % 100 / 20 = 5
        \\ pstack          % Should print: 5 \n /my_variable \n 165
    ;

    _ = ps.Lexer.init(code);
}
