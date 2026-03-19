//! Server listener to accept Wayland client connections

const std = @import("std");

const Connection = @import("Connection.zig");

const Server = @This();

// Each Wayland client has an associated display structure. For each display a lock file
// is crated. Hence this constant basically limits the number of Wayland clients a server
// can deal with.
const max_displays = 10;

inner: std.Io.net.Server,
lock: std.Io.File,
path: [std.Io.net.UnixAddress.max_len:0]u8,

pub const InitError = LockDisplayError || std.Io.Dir.OpenError || std.Io.net.UnixAddress.ListenError ||
    error{ NoXdgRuntimeDir, NoDisplaysAvailable, NameTooLong, NoSpaceLeft };

pub fn init(env: std.process.Init, io: std.Io) InitError!Server {
    const xdg_runtime_dir_path = env.environ_map.get("XDG_RUNTIME_DIR") orelse return error.NoXdgRuntimeDir;
    const xdg_runtime_dir = try std.Io.Dir.openDirAbsolute(io, xdg_runtime_dir_path, .{});
    defer xdg_runtime_dir.close(io);

    var endpoint_buf: [12]u8 = undefined;
    var endpoint: []const u8 = undefined;

    const lock: std.Io.File = for (0..max_displays) |display| {
        endpoint = std.fmt.bufPrint(&endpoint_buf, "wayland-{}", .{display}) catch unreachable;
        break lockDisplay(io, xdg_runtime_dir, endpoint) catch |err| {
            if (err == error.LockFailed) continue;
            return err;
        };
    } else return error.NoDisplaysAvailable;
    errdefer lock.close(io);

    var path_buf: [std.Io.net.UnixAddress.max_len]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ xdg_runtime_dir_path, endpoint });
    const addr = try std.Io.net.UnixAddress.init(path);

    const server = try addr.listen(io, .{});

    var self = Server{ .inner = server, .lock = lock, .path = @splat(0) };
    @memcpy(self.path[0..path.len], path);

    return self;
}

pub fn deinit(self: *Server, io: std.Io) void {
    const path = std.mem.sliceTo(&self.path, 0);
    var lock_buf: [std.Io.UnixAddress.max_len]u8 = undefined;
    const lock_path = std.fmt.bufPrint(&lock_buf, "{s}.lock", .{path}) catch unreachable;

    std.Io.Dir.deleteFileAbsolute(io, path) catch {};
    std.Io.Dir.deleteFileAbsolute(io, lock_path) catch {};

    self.lock.close(io);
    self.inner.socket.close(io);
}

pub fn getFd(self: *const Server) std.posix.fd_t {
    return self.inner.socket.handle;
}

pub fn socketPath(self: *const Server) []const u8 {
    return std.mem.sliceTo(&self.path, 0);
}

pub fn getEndpoint(self: *const Server) []const u8 {
    const path = self.socketPath();
    const idx = if (std.mem.findScalarLast(u8, path, '/')) |idx| idx + 1 else 0;
    return path[idx..];
}

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
