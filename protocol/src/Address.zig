const std = @import("std");

const Address = @This();

const ConnectionStrategy = enum {
    name,
    path,
    sock,
};

strategy: ConnectionStrategy,

info: union(enum) {
    sock: std.os.linux.fd_t,
    path: [std.Io.net.UnixAddress.max_len:0]u8,
},

pub const Error = error{ NoXdgRuntimeDir, PathTooLong };

pub fn initSocket(sock: std.os.linux.fd_t) Address {
    return Address{
        .strategy = .sock,
        .info = .{ .sock = sock },
    };
}

pub fn initEndpoint(init: std.process.Init, endpoint: []const u8) Error!Address {
    const xdg_rt_dir = init.environ_map.get("XDG_RUNTIME_DIR") orelse return error.NoXdgRuntimeDir;

    var self = Address{
        .strategy = .name,
        .info = .{ .path = @splat(0) },
    };
    _ = std.fmt.bufPrintSentinel(&self.info.path, "{s}/{s}", .{ xdg_rt_dir, endpoint }, 0) catch return error.PathTooLong;

    return self;
}
