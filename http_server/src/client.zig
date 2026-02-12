const std = @import("std");
const Io = std.Io;
const debug = std.debug;
const net = std.Io.net;

pub fn main(init: std.process.Init) !void {
    const host = "127.0.0.1";
    const port: u16 = 3490;

    debug.print("Client connecting to {s}:{any}\n", .{ host, port });
    const addr = try net.IpAddress.parseIp4(host, port);
    const conn = try addr.connect(init.io, .{ .mode = net.Socket.Mode.stream, .protocol = net.Protocol.tcp });
    debug.print("Connection {any}\n", .{conn});
}
