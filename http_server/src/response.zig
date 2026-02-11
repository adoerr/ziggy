const std = @import("std");
const Stream = std.Io.net.Stream;
const Io = std.Io;

pub fn ok(conn: Stream, io: Io) !void {
    const msg = ("HTTP/1.1 200 OK\nContent-Length: 48" ++ "\nContent-Type: text/html\n" ++ "Connection: Closed\n\n<html><body>" ++ "<h1>Hello, World!</h1></body></html>");
    var writer = conn.writer(io, &.{}).interface;
    _ = try writer.write(msg);
}

pub fn notFound(conn: Stream, io: Io) !void {
    const msg = ("HTTP/1.1 404 Bad Request\nContent-Length: 50" ++ "\nContent-Type: text/html\n" ++ "Connection: Closed\n\n<html><body>" ++ "<h1>File not found!</h1></body></html>");
    var writer = conn.writer(io, &.{}).interface;
    _ = try writer.write(msg);
}
