const std = @import("std");
const wayland = @import("wayland");

const Io = std.Io;

pub fn main(init: std.process.Init) !void {
    var out_buffer: [1024]u8 = undefined;
    var out_file_writer: Io.File.Writer = .init(.stdout(), init.io, &out_buffer);
    const stdout = &out_file_writer.interface;

    const addr = try wayland.Address.initEndpoint(init, "wayland-0");
    const path: []const u8 = &addr.info.path;

    try addr.format(stdout);
    try stdout.print("\nPath: '{s}'\n", .{path});
    try stdout.print("\n", .{});
    try stdout.flush();
}
