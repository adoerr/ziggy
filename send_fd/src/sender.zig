const std = @import("std");
const cmsg = @import("ctrl_msg.zig");

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
