const std = @import("std");

const wayland = @import("wayland");
const wl_client = @import("wl_client");
const xdg_shell = @import("xdg_shell");

const log = std.log.scoped(.gui);

const display: wl_client.Display = .display; // `wl_display` has aways the special reserved id of `1`
var connection: wayland.Connection = undefined;
var registry: wl_client.Registry = .invalid;
var configured = false;

const Event = wayland.Message(.{ wl_client, xdg_shell });

pub const State = struct {
    compositor: wl_client.Compositor = .invalid,
    shm: wl_client.Shm = .invalid,
    wm_base: xdg_shell.WmBase = .invalid,
    surface: wl_client.Surface = .invalid,
    buffer: wl_client.Buffer = .invalid, // opaque pixel container
    shared_memory: []align(4096) u8 = undefined,
};

pub fn setup(init: std.process.Init, state: *State) !void {
    const addr = try wayland.Address.default(init);
    connection = wayland.Connection.init(init.io, init.gpa, addr) catch |err| {
        std.log.err("Failed to connect to {f}: {t}", .{ addr, err });
        return err;
    };

    std.log.info("Connected to {f}", .{addr});

    registry = try display.getRegistry(&connection);

    // Sync display to know when all registry globals have benn received
    _ = try display.sync(&connection);

    while (connection.nextMessage(Event, .none)) |event| {
        switch (event) {
            .wl_registry => |r| switch (r) {
                .global => |g| {
                    // interface name
                    const iface = @field(g, "interface");

                    log.debug("Interface `{s}` available", .{iface});

                    // bind to globals `wl_compositor`, `wl_shm` and `xdg_wm_base`
                    if (std.mem.eql(u8, iface, wl_client.Compositor.interface)) {
                        state.compositor = try registry.bind(&connection, wl_client.Compositor, .v4, g.name);
                    } else if (std.mem.eql(u8, iface, wl_client.Shm.interface)) {
                        state.shm = try registry.bind(&connection, wl_client.Shm, .v1, g.name);
                    } else if (std.mem.eql(u8, iface, xdg_shell.WmBase.interface)) {
                        state.wm_base = try registry.bind(&connection, xdg_shell.WmBase, .v1, g.name);
                    }
                },
                .global_remove => {
                    // Ignore
                },
            },
            .wl_callback => {
                log.debug("Callback.done - all globals received", .{});
                break; // all globals received
            },
            else => log.err("Unexpected event: {}", .{event}),
        }
    } else |err| {
        log.debug("Error {}", .{err});
        return err;
    }

    // Assert all globals needed are bound
    std.debug.assert(state.compositor != .invalid and state.shm != .invalid and state.wm_base != .invalid);

    state.surface = try state.compositor.createSurface(&connection);
    const xdg_surf = try state.wm_base.getXdgSurface(&connection, state.surface);
    _ = try xdg_surf.getToplevel(&connection);

    try state.surface.commit(&connection);

    // Main loop
    while (connection.nextMessage(Event, .none)) |event| switch (event) {
        .xdg_wm_base => |ev| {
            try state.wm_base.pong(&connection, ev.ping.serial);
        },
        .xdg_surface => |ev| {
            log.debug("Event {}", .{ev});
            try xdg_surf.ackConfigure(&connection, ev.configure.serial);
            if (!configured) {
                try allocBuffer(state, 256, 256);
                try state.surface.attach(&connection, state.buffer, 256, 256);
            }
            try state.surface.commit(&connection);
            configured = true;
        },
        .xdg_toplevel => |ev| switch (ev) {
            .close => {
                log.debug("Event: {}", .{ev});
                break;
            },
            else => {},
        },
        else => log.debug("Event: {}", .{event}),
    } else |err| {
        log.debug("Error {}", .{err});
    }
}

pub fn deinit() void {
    defer connection.deinit();
}

pub fn createSurface(state: *State) !void {
    state.surface = try state.compositor.createSurface(&connection);
    const xdg_surface = try state.wm_base.getXdgSurface(&connection, state.surface);
    _ = try xdg_surface.getToplevel(&connection);
    try state.surface.commit(&connection);

    // Main loop
    while (connection.nextMessage(Event, .none)) |event| switch (event) {
        .xdg_wm_base => |ev| {
            log.debug("xdg_wm_base event: {}", .{ev});
            try state.wm_base.pong(&connection, ev.ping.serial);
        },
        else => log.info("Unexpected event: {}", .{event}),
    } else |err| {
        log.debug("Error {}", .{err});
        return err;
    }
}

pub fn allocBuffer(state: *State, width: comptime_int, height: comptime_int) !void {
    const stride = width * 4;
    const size = stride * height;
    const fd = try newSharedMemoryFile(size);
    defer _ = std.os.linux.close(fd);

    state.shared_memory = try std.posix.mmap(null, size, .{ .READ = true, .WRITE = true }, .{ .TYPE = .SHARED }, fd, 0);
    // Fill the buffer with white pixels
    @memset(state.shared_memory, 255);

    const pool = try state.shm.createPool(&connection, fd, size);
    defer pool.destroy(&connection) catch {};

    state.buffer = try pool.createBuffer(&connection, 0, width, height, stride, .argb8888);
}

/// Create a new shared memory file truncated to `size` bytes.
/// Return the shared memory file descriptor.
pub fn newSharedMemoryFile(size: usize) !i32 {
    const fd = try sharedMemoryFile();
    return switch (std.os.linux.errno(std.os.linux.ftruncate(fd, @intCast(size)))) {
        .SUCCESS => fd,
        else => |err| std.posix.unexpectedErrno(err),
    };
}

/// Create a shared memory file an return the file descriptor
fn sharedMemoryFile() !i32 {
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

    const fd: i32 = while (true) {
        randomizeAscii(path[prefix.len..]);
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
