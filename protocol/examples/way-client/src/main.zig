const std = @import("std");

const wayland = @import("wayland");

pub fn main(init: std.process.Init) !void {
    var out_buf: [1024]u8 = undefined;
    var out_writer = std.Io.File.stdout().writer(init.io, &out_buf);
    const stdout = &out_writer.interface;

    const addr = try wayland.Address.default(init);
    try stdout.print("Address: {f}\n", .{addr});
    try stdout.flush();
}
