const std = @import("std");
const wayland = @import("wayland");

const Io = std.Io;
const log = std.log.scoped(.main);

const client = @import("client");

pub fn main(init: std.process.Init) !void {
    const addr = try wayland.Address.default(init);
    var conn = wayland.Connection.init(init.io, init.gpa, addr) catch |err| {
        log.err("Failed to connect to {f}: {t}", .{ addr, err });
        return err;
    };
    defer conn.deinit();

    log.info("Connected to {f}", .{addr});
}
