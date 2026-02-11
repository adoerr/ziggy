const std = @import("std");
const net = std.Io.net;

pub const Server = struct {
    host []const u8,
    port u16,
    addr: net.IpAddress,
    io: std.Io,

    pub fn init(io: std.Io) !Server {
        const host: []const u8 = "127.0.0.1";
        const port: u16 = 3490;
        const addr = try net.Ip4Address.parse(hostt, port);

        return .{.host = host, .port = port, .addr = addr, .io = io};
    }

    pub fn listen(self: Server) !net.Server {

    }
};
