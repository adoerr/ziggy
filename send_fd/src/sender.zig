const std = @import("std");
const cmsg = @import("ctrl_msg.zig");

const log = std.log.scoped(.sender);

pub fn main(init: std.process.Init) !void {
    // create a shared memory file descriptor
    const shm_prefix = "wl-shm-";
    var shm_name: [22]u8 = @splat(0);
    @memcpy(shm_name[0..shm_prefix.len], shm_prefix);
    try randomize(init.io, shm_name[shm_prefix.len..]);
    const shm_fd = try std.posix.memfd_create(&shm_name, 0);
    defer _ = std.posix.system.close(shm_fd);

    // resize shared memory region to store our message
    const msg = "Hello from the Sender Process via Shared Memory";
    const shm_size = msg.len;
    _ = std.posix.system.ftruncate(shm_fd, shm_size);

    // map the shared memory file descriptor and copy message
    const shm_opt: std.posix.PROT = .{ .READ = true, .WRITE = true };
    const shm_flags: std.posix.MAP = .{ .TYPE = .SHARED };
    const shm_ptr = try std.posix.mmap(null, shm_size, shm_opt, shm_flags, shm_fd, 0);
    defer std.posix.munmap(shm_ptr);
    @memcpy(shm_ptr[0..shm_size], msg);
    log.info("Wrote '{s}' to shared memory (fd={d})", .{ msg, shm_fd });

    // connect to the receiver's Unix Domain Socket
    const sock_path = "/tmp/zig_shm.unix";
    const addr = try std.Io.net.UnixAddress.init(sock_path);
    const stream = try addr.connect(init.io);
    defer stream.close(init.io);
    log.info("Connected to Server ...", .{});

    // we need space for one file descriptor
    var control: [cmsg.space(1)]u8 = undefined;
    std.mem.bytesAsValue(cmsg.Header, control[0..@sizeOf(cmsg.Header)]).* = .{ .cmsg_len = cmsg.length(1) };
    // copy file descriptor into control buffer
    const data = std.mem.bytesAsSlice(std.posix.fd_t, control[@sizeOf(cmsg.Header)..][0..@sizeOf(std.posix.fd_t)]);
    const fds = [_]i32{shm_fd};
    @memcpy(data, &fds);
    // we only use ancillary data, so crate some dummy data
    const dummy_buf: []const u8 = "Here comes the file descriptor";
    var iov = [1]std.posix.iovec_const{.{ .base = dummy_buf.ptr, .len = dummy_buf.len }};

    const msg_hdr = std.posix.msghdr_const{
        .name = null,
        .namelen = 0,
        .iov = &iov,
        .iovlen = 1,
        .control = &control,
        .controllen = control.len,
        .flags = 0,
    };

    const bytes_send = std.posix.system.sendmsg(stream.socket.handle, &msg_hdr, 0);
    std.debug.assert(bytes_send == dummy_buf.len);
    log.info("Send `{d}` bytes", .{bytes_send});
}

/// Fill `buf` with random characters.
fn randomize(io: std.Io, buf: []u8) !void {
    const now = std.Io.Clock.now(std.Io.Clock.real, io);

    const seed = @as(u64, @bitCast(now.toSeconds())) ^ @as(u64, @bitCast(now.toMilliseconds()));
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();

    const alphanumeric = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";

    for (buf) |*byte| {
        byte.* = alphanumeric[rand.uintLessThan(usize, alphanumeric.len)];
    }
}
