const std = @import("std");
const debug = std.debug;

pub fn main(init: std.process.Init) !void {
    try std.Io.File.stdout().writeStreamingAll(init.io, "Hello World\n");

    const args = try init.minimal.args.toSlice(init.arena.allocator());

    for (args) |arg| {
        debug.print("Arg: {s}\n", .{arg});
    }
}
