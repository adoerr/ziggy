const std = @import("std");

const log = std.log.scoped(.receiver);
pub fn main(init: std.process.Init) !void {
    const sock_path = "/tmp/zig_shm.unix";

    const addr = try std.Io.net.UnixAddress.init(sock_path);
    defer std.Io.Dir.cwd().deleteFile(init.io, sock_path) catch {};

    log.info("Listening ...", .{});
    var server = try addr.listen(init.io, .{});
    defer server.socket.close(init.io);

    var stream = try server.accept(init.io);
    defer stream.close(init.io);
    log.info("Client accepted ...", .{});
}
