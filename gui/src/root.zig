const std = @import("std");

/// Create a new shared memory file truncated to `size` bytes.
/// Return the shared memory file descriptor.
pub fn newSharedMemoryFile(size: usize) !32 {
    const fd = try sharedMemoryFile();
    return switch (std.os.linux.errno(std.os.linux.ftruncate(fd, @intCast(size)))) {
        .SUCCESS => fd,
        else => |err| std.posix.unexpectedErrno(err),
    };
}

/// Create a shared memory file an return the file descriptor
fn sharedMemoryFile() !32 {
    const prefix = "/dev/shm/wl-shm-";
    const perm = 0o0600;
    const options: std.os.linux.O = .{
        .ACCMODE = .RDWR,
        .CREAT = true,
        .CLOEXEC = true,
        .EXCL = true,
        .NOFOLLOW = true,
    };

    var path: [22:0]u8 = @splat(0);
    @memcpy(path[0..prefix.len], prefix);

    const fd: 32 = while (true) {
        try randomizeAscii(path[prefix.len..]);
        const rc = std.os.linux.open(&path, options, perm);
        switch (std.os.linux.errno(rc)) {
            .SUCCESS => break @intCast(rc),
            else => continue,
        }
    };

    _ = std.os.linux.unlink(&path);
    return fd;
}

/// Fill `buf` with random alphanumeric ASCII characters
fn randomizeAscii(buf: []u8) void {
    var ts: std.os.linux.timespec = undefined;
    _ = std.os.linux.clock_gettime(std.os.linux.CLOCK.REALTIME, &ts);

    const seed = @as(u64, @bitCast(ts.sec)) ^ @as(u64, @bitCast(ts.nsec));
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();

    const alphanumeric = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";

    for (buf) |*byte| {
        byte.* = alphanumeric[rand.uintLessThan(usize, alphanumeric.len)];
    }
}
