const std = @import("std");

const gui = @import("gui");
const wayland = @import("wayland");
const wl_client = @import("wl_client");
const xdg_shell = @import("xdg_shell");

const Io = std.Io;
const log = std.log.scoped(.main);

const display: wl_client.Display = .display; // object ID 1 is always implicitly assigned to `wl_display`
var registry: wl_client.Registry = .invalid;
var compositor: wl_client.Compositor = .invalid;
var shm: wl_client.Shm = .invalid;
var wm_base: xdg_shell.WmBase = .invalid;
var surface: wl_client.Surface = .invalid;

const Event = wayland.Message(.{ wl_client, xdg_shell });

pub fn main(init: std.process.Init) !void {
    var state = gui.State{};

    const addr = try wayland.Address.default(init);

    state.connection = wayland.Connection.init(init.io, init.gpa, addr) catch |err| {
        log.err("Failed to connect to {f}: {t}", .{ addr, err });
        return err;
    };
    defer state.connection.deinit();

    log.info("Connected to {f}", .{addr});

    registry = try display.getRegistry(&state.connection);
    _ = try display.sync(&state.connection);

    while (state.connection.nextMessage(Event, .none)) |event| {
        switch (event) {
            .wl_registry => |r| switch (r) {
                .global => |g| {
                    // interface name
                    const iface = @field(g, "interface");

                    log.debug("Interface `{s}` available", .{iface});

                    // bind to globals `wl_compositor`, `wl_shm` and `xdg_wm_base`
                    if (std.mem.eql(u8, iface, wl_client.Compositor.interface)) {
                        compositor = try registry.bind(&state.connection, wl_client.Compositor, .v1, g.name);
                    } else if (std.mem.eql(u8, iface, wl_client.Shm.interface)) {
                        shm = try registry.bind(&state.connection, wl_client.Shm, .v1, g.name);
                    } else if (std.mem.eql(u8, iface, xdg_shell.WmBase.interface)) {
                        wm_base = try registry.bind(&state.connection, xdg_shell.WmBase, .v1, g.name);
                    }
                },
                .global_remove => {
                    // Ignore
                },
            },
            .wl_callback => {
                break; // all globals received
            },
            else => log.err("Unexpected event: {}", .{event}),
        }
    } else |err| {
        log.debug("Error {}", .{err});
        return err;
    }

    // Assert all globals needed are bound
    std.debug.assert(compositor != .invalid and shm != .invalid and wm_base != .invalid);

    surface = try compositor.createSurface(&state.connection);
    const xdg_surface = try wm_base.getXdgSurface(&state.connection, surface);
    _ = try xdg_surface.getToplevel(&state.connection);
    try surface.commit(&state.connection);

    // Main loop
    while (state.connection.nextMessage(Event, .none)) |event| switch (event) {
        .xdg_wm_base => |ev| {
            log.debug("xdg_wm_base event: {}", .{ev});
            try wm_base.pong(&state.connection, ev.ping.serial);
        },
        else => log.info("Unexpected event: {}", .{event}),
    } else |err| {
        log.debug("Error {}", .{err});
        return err;
    }
}
