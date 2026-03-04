const std = @import("std");
const wayland = @import("wayland");
const wl_client = @import("wl_client");
const xdg_shell = @import("xdg_shell");

pub const State = struct {
    connection: wayland.Connection = undefined,
    registry: wl_client.Registry = .invalid,
    compositor: wl_client.Compositor = .invalid,
    shm: wl_client.Shm = .invalid,
    wm_base: xdg_shell.WmBase = .invalid,
    surface: wl_client.Surface = .invalid,
    buffer: wl_client.Buffer = .invalid,
    shared_memory: []align(4096) u8 = undefined,
};

pub fn allocBuffer(state: *State, width: comptime_int, height: comptime_int) !void {
    const stride = width * 4;
    const size = stride * height;
    const fd = try newSharedMemoryFile(size);
    defer _ = std.os.linux.close(fd);

    state.shared_memory = try std.os.linux.mmap(null, size, .{ .READ = true, .WRITE = true }, .{ .TYPE = .SHARED }, fd, 0);
    // Fill the buffer with white pixels
    @memset(state.shared_memory, 255);

    const pool = try state.shm.createPool(&state.connection, fd, size);
    defer pool.destroy(&state.connection) catch {};

    state.buffer = try pool.createBuffer(&state.connection, 0, width, height, stride, .argb8888);
}

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
