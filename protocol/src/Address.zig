const std = @import("std");

const Address = @This();

const ConnectStrategy = enum {
    name,
    path,
    sock,
};

strategy: ConnectStrategy,

info: union(enum) {
    sock: std.posix.fd_t,
    path: [std.Io.net.UnixAddress.max_len:0]u8,
},

pub const Error = error{ NoXdgRuntimeDir, PathTooLong };

pub fn default(init: std.process.Init) Error!Address {
    if (init.environ_map.get("WAYLAND_SOCKET")) |sock_str| {
        if (std.fmt.parseInt(std.posix.fd_t, sock_str, 10) catch null) |sock| {
            return .initSocketFd(sock);
        }
    }

    const display = init.environ_map.get("WAYLAND_DISPLAY") orelse "wayland-0";

    return .initEndpoint(init, display);
}

pub fn initSocketFd(sock: std.posix.fd_t) Address {
    return Address{
        .strategy = .sock,
        .info = .{ .sock = sock },
    };
}

pub fn initEndpoint(init: std.process.Init, endpoint: []const u8) Error!Address {
    const xdg_runtime_dir = init.environ_map.get("XDG_RUNTIME_DIR") orelse
        return error.NoXdgRuntimeDir;

    var self = Address{
        .strategy = .name,
        .info = .{ .path = @splat(0) },
    };

    _ = std.fmt.bufPrintSentinel(&self.info.path, "{s}/{s}", .{ xdg_runtime_dir, endpoint }, 0) catch
        return error.PathTooLong;
    return self;
}

pub fn initAbsolutePath(path: []const u8) Error!Address {
    if (path.len > std.Io.net.UnixAddress.max_len) return error.PathTooLong;

    var self = Address{
        .strategy = .path,
        .info = .{ .path = @splat(0) },
    };

    @memcpy(self.info.path[0..path.len], path);

    return self;
}

pub fn format(self: Address, w: *std.Io.Writer) std.Io.Writer.Error!void {
    switch (self.strategy) {
        .sock => try w.print("socket fd '{d}'", .{self.info.sock}),
        .name => {
            const idx = if (std.mem.findScalarLast(u8, &self.info.path, '/')) |i| i + 1 else 0;
            const endpoint = std.mem.sliceTo(self.info.path[idx..], 0);
            try w.print("endpoint '{s}'", .{endpoint});
        },
        .path => {
            const path = std.mem.sliceTo(&self.info.path, 0);
            try w.print("absolute path '{s}'", .{path});
        },
    }
}
