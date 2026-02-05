const std = @import("std");
var buffer: [1024]u8 = undefined;
var writer = std.fs.File.stdout().writer(&buffer);
const stdout = &writer.interface;

pub fn main() !void {
    try stdout.print("Hello, World!\n", .{});
}