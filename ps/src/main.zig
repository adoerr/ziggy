const std = @import("std");
const ps = @import("ps");
const Io = std.Io;
const log = std.log.scoped(.main);

pub fn main(init: std.process.Init) !void {
    // sample PostScript snippet to test our Lexer and RPN logic
    const code =
        \\ % This is a comment
        \\ 10 20 add       % 10 + 20 = 30
        \\ 5.5 mul         % 30 * 5.5 = 165.0
        \\ /my_variable    % push a literal name
        \\ 100 20 div      % 100 / 20 = 5
        \\ pstack          % Should print: 5 \n /my_variable \n 165
    ;

    var lexer = ps.Lexer.init(code);

    var interpreter = ps.Interpreter.init(init.io, init.gpa);
    defer interpreter.deinit();

    log.info("Start evaluate PostScript code", .{});

    while (lexer.next()) |token| {
        try interpreter.evaluate(token);
    }

    log.info("Evaluation done\n", .{});
}
