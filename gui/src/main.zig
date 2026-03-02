const std = @import("std");
const gui = @import("gui");
const wayland = @import("wayland");

const Io = std.Io;
var conn: wayland.Connection = undefined;

pub fn main(init: std.process.Init) !void {
    const addr = try wayland.Address.default(init);

    conn = wayland.Connection.init(init.io, init.gpa, addr) catch |err| {
        std.log.err("Failed to connect to {f}: {t}", .{ addr, err });
        return err;
    };
    defer conn.deinit();

    std.log.info("Connected to {f}\n", .{addr});
}
