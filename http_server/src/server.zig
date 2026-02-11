const std = @import("std");
const debug = std.debug;
const net = std.Io.net;
const Socket = std.Io.net.Socket;
const Protocol = std.Io.net.Protocol;

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
        debug.print("Server Addr: {s}:{any}", .{self.host, .self.port});
        return try self.addr.listen(self.io, .{.mode = Socket.Mode.stream, .protocol = Protocol.tcp});
    }
};

