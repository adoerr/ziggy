const std = @import("std");
const wayland = @import("wayland");

const Io = std.Io;

pub fn main(init: std.process.Init) !void {
    var out_buffer: [1024]u8 = undefined;
    var out_file_writer: Io.File.Writer = .init(.stdout(), init.io, &out_buffer);
    const stdout = &out_file_writer.interface;

    const addr = try wayland.Address.default(init);

    try addr.format(stdout);
    try stdout.print("\n", .{});
    try stdout.flush();
}
