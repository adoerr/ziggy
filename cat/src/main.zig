const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const path = "./assets/meow.txt";
    const alloc = init.gpa;

    const cwd = std.Io.Dir.cwd();
    const text = try cwd.readFileAlloc(init.io, path, alloc, .limited(16 * 1014 * 1024));
    defer alloc.free(text);

    try std.Io.File.stdout().writeStreamingAll(init.io, text);
}
