const std = @import("std");
const debug = std.debug;
const net = std.Io.net;
const testing = std.testing;
const Socket = std.Io.net.Socket;
const Protocol = std.Io.net.Protocol;
const log = std.log.scoped(.server);

pub const Server = struct {
    host: []const u8,
    port: u16,
    addr: net.IpAddress,
    io: std.Io,

    pub fn init(io: std.Io) !Server {
        const host: []const u8 = "127.0.0.1";
        const port: u16 = 3490;
        const addr = try net.IpAddress.parse(host, port);

        return .{ .host = host, .port = port, .addr = addr, .io = io };
    }

    pub fn listen(self: Server) !net.Server {
        log.debug("Server Addr: {s}:{any}\n", .{ self.host, self.port });
        return try self.addr.listen(self.io, .{ .mode = Socket.Mode.stream, .protocol = Protocol.tcp });
    }
};

const assert = std.debug.assert;

test "Server.init configures default host and port correctly" {
    const io: std.Io = undefined;
    const server = try Server.init(io);

    try testing.expectEqualStrings("127.0.0.1", server.host);
    try testing.expectEqual(@as(u16, 3490), server.port);
}

test "Server.listen starts listening on default port" {
    var alloc: std.heap.DebugAllocator(.{}) = .init;
    defer assert(alloc.deinit() == .ok);
    const gpa = alloc.allocator();
    var threaded: std.Io.Threaded = .init(gpa, .{ .environ = .empty });
    defer threaded.deinit();
    const io = threaded.io();

    const srv = try Server.init(io);

    var net_srv = srv.listen() catch |err| {
        switch (err) {
            error.AddressInUse => return, // expected error
            else => return err,
        }
    };
    defer net_srv.deinit(io);
}
