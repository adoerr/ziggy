const std = @import("std");
const Io = std.Io;
const assert = std.debug.assert;
const Socket = std.Io.net.Socket;
const Protocol = std.Io.net.Protocol;
const log = std.log.scoped(.main);

const Request = @import("request.zig");
const Response = @import("response.zig");
const Method = Request.Method;
const Server = @import("server.zig").Server;

pub const std_options = std.Options{
    .log_level = .debug,
};

pub fn main() !void {
    var alloc: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer assert(alloc.deinit() == .ok);
    const gpa = alloc.allocator();

    var threaded: Io.Threaded = .init(gpa, .{ .environ = .empty });
    defer threaded.deinit();
    const io = threaded.io();

    const server = try Server.init(io);
    var listner = try server.listen();
    const client = try listner.accept(io);
    defer client.close(io);

    var buf: [1024]u8 = undefined;
    var writer = std.Io.File.stdout().writer(io, &buf);
    const stdout = &writer.interface;

    log.debug("client connected {any}\n", .{client});

    var req_buf = [_]u8{0} ** 1000;
    try Request.readRequest(io, client, req_buf[0..]);
    const request = Request.parseRequest(req_buf[0..req_buf.len]);

    log.debug("request {any}", .{request});

    req_buf[req_buf.len - 1] = '\n';
    _ = try stdout.writeAll(req_buf[0..]);
    try stdout.flush();
}
