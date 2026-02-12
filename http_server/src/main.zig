const std = @import("std");
const Io = std.Io;
const assert = std.debug.assert;
const Socket = std.Io.net.Socket;
const Protocol = std.Io.net.Protocol;

const Request = @import("request.zig");
const Response = @import("response.zig");
const Method = Request.Method;
const Server = @import("server.zig").Server;

pub fn main() !void {
    var alloc: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer assert(alloc.deinit() == .ok);
    const gpa = alloc.allocator();

    var threaded: Io.Threaded = .init(gpa, .{ .environ = .empty });
    defer threaded.deinit();
    const io = threaded.io();

    var buf: [1024]u8 = undefined;
    _ = &std.Io.File.stdout().writer(io, &buf).interface; // stdout

    const server = try Server.init(io);
    var listner = try server.listen();
    const client = try listner.accept(io);
    defer client.close(io);

    std.debug.print("Client connected {any}\n", client);
}
