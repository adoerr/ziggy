//! Server listener to accept Wayland client connections

const std = @import("std");

const Connection = @import("Connection.zig");

const Server = @This();

const map_displays = 10;

inner: std.Io.net.Server,
lock: std.Io.File,
path: [std.Io.net.UnixAddress.max_len:0]u8,

const LockDisplayError = std.Io.File.OpenError || std.Io.File.LockError || std.Io.File.StatError || error{LockFailed};

fn lockDisplay(io: std.Io, xdg_runtime_dir: std.Io.Dir, endpoint: []const u8) !std.Io.File {
    // Lock file path
    var path_buf: [32]u8 = undefined;
    const lock = std.fmt.bufPrint(&path_buf, "{s}.lock", .{endpoint}) catch unreachable;

    // Create lock file
    const lock_file = try xdg_runtime_dir.createFile(io, lock, .{
        .read = true,
        .permissions = .fromMode(std.posix.system.IRUSR, std.posix.system.IWUSR, std.posix.system.IRGRP, std.posix.system.IWGRP),
        .lock_nonblocking = true,
    });
    errdefer lock_file.close(io);

    if (!lock_file.tryLock(io, .exclusive)) return error.LockFailed;

    // Remove stale socket if it exists
    xdg_runtime_dir.deleteFile(io, endpoint) catch {};

    return lock_file;
}
