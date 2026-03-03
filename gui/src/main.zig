const std = @import("std");
const gui = @import("gui");
const wayland = @import("wayland");
const wl_client = @import("wl_client");
const xdg_shell = @import("xdg_shell");

const Io = std.Io;
const log = std.log.scoped(.main);

var conn: wayland.Connection = undefined;
const disp: wl_client.Display = .display; // object ID 1 is always implicitly assigned to `wl_display`
var registry: wl_client.Registry = undefined;

const Event = wayland.Message(.{wl_client});

pub fn main(init: std.process.Init) !void {
    const addr = try wayland.Address.default(init);

    conn = wayland.Connection.init(init.io, init.gpa, addr) catch |err| {
        log.err("Failed to connect to {f}: {t}", .{ addr, err });
        return err;
    };
    defer conn.deinit();

    log.info("Connected to {f}", .{addr});

    registry = try disp.getRegistry(&conn);
    _ = try disp.sync(&conn);

    while (conn.nextMessage(Event, .none)) |event| {
        switch (event) {
            .wl_registry => |r| switch (r) {
                .global => |g| {
                    const n = @field(g, "interface");
                    log.debug("Interface: `{s}`", .{n});
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
}
