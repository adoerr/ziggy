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
    log.info("Received: `{d}` bytes `{s}`", .{ num, data_buf[0..num] });

    // we expect only one control message with the shared memory fd
    var shm_fd: std.posix.fd_t = undefined;
    if (cmsg.firstHeader(&msg_hdr)) |header| {
        const data = cmsg.data(header);
        const fds = std.mem.bytesAsSlice(std.posix.fd_t, data);
        shm_fd = fds[0];
    } else {
        log.err("Missing control msg header", .{});
        std.process.exit(1);
    }

    // get shared memory file stats
    const file = std.Io.File{ .handle = shm_fd, .flags = .{ .nonblocking = true } };
    const shm_stat = try file.stat(init.io);
    // map the shared memory fd and read the message
    const shm_opt: std.posix.PROT = .{ .READ = true, .WRITE = true };
    const shm_flags: std.posix.MAP = .{ .TYPE = .SHARED };
    const shm_ptr = try std.posix.mmap(null, shm_stat.size, shm_opt, shm_flags, shm_fd, 0);
    defer std.posix.munmap(shm_ptr);
    defer _ = std.posix.system.close(shm_fd);
    log.info("Read `{s}` from shared memory (fd={d})", .{ shm_ptr, shm_fd });
}
