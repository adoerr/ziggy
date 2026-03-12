const std = @import("std");
const cmsg = @import("ctrl_msg.zig");

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

    var data_buf: [40]u8 = undefined;
    var iov = [1]std.posix.iovec{.{ .base = &data_buf, .len = data_buf.len }};
    var control: [cmsg.space(1)]u8 = undefined;

    var msg_hdr = std.posix.msghdr{
        .name = null,
        .namelen = 0,
        .iov = &iov,
        .iovlen = 1,
        .control = &control,
        .controllen = control.len,
        .flags = 0,
    };

    const num = std.posix.system.recvmsg(stream.socket.handle, &msg_hdr, std.posix.system.MSG.DONTWAIT);
    log.info("Received: `{d}` bytes", .{num});
}
