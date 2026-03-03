const std = @import("std");

const gui = @import("gui");
const wayland = @import("wayland");
const wl_client = @import("wl_client");
const xdg_shell = @import("xdg_shell");

const Io = std.Io;
const log = std.log.scoped(.main);

var conn: wayland.Connection = undefined;
const display: wl_client.Display = .display; // object ID 1 is always implicitly assigned to `wl_display`
var registry: wl_client.Registry = .invalid;
var compositor: wl_client.Compositor = .invalid;
var shm: wl_client.Shm = .invalid;
var wm_base: xdg_shell.WmBase = .invalid;

const Event = wayland.Message(.{ wl_client, xdg_shell });

pub fn main(init: std.process.Init) !void {
    const addr = try wayland.Address.default(init);

    conn = wayland.Connection.init(init.io, init.gpa, addr) catch |err| {
        log.err("Failed to connect to {f}: {t}", .{ addr, err });
        return err;
    };
    defer conn.deinit();

    log.info("Connected to {f}", .{addr});

    registry = try display.getRegistry(&conn);
    _ = try display.sync(&conn);

    while (conn.nextMessage(Event, .none)) |event| {
        switch (event) {
            .wl_registry => |r| switch (r) {
                .global => |g| {
                    // interface name
                    const iface = @field(g, "interface");

                    log.debug("Interface: `{s}`", .{iface});

                    // bind to globals
                    if (std.mem.eql(u8, iface, wl_client.Compositor.interface)) {
                        compositor = try registry.bind(&conn, wl_client.Compositor, .v1, g.name);
                    } else if (std.mem.eql(u8, iface, wl_client.Shm.interface)) {
                        shm = try registry.bind(&conn, wl_client.Shm, .v1, g.name);
                    } else if (std.mem.eql(u8, iface, xdg_shell.WmBase.interface)) {
                        wm_base = try registry.bind(&conn, xdg_shell.WmBase, .v1, g.name);
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

    // Assert all globals are bound
    std.debug.assert(compositor != .invalid and shm != .invalid and wm_base != .invalid);
}
