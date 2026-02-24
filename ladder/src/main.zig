const std = @import("std");
const ladder = @import("ladder");
const Io = std.Io;

pub fn main(init: std.process.Init) !void {
    const cwd = Io.Dir.cwd();
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const words = try cwd.readFileAlloc(init.io, args[1], init.gpa, .unlimited);
    defer init.gpa.free(words);

    const count = ladder.countWords(words);
    std.debug.print("word count: {}\n", .{count});
}
