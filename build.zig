const std = @import("std");

pub fn build(b: *std.Build) void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    _ = allocator;

    // build the HTTP Server
    const http_server = b.addSystemCommand(&.{ "zig", "build" });
    http_server.cwd = b.path("http_server");
    const build_http_step = b.step("http_server", "Build the HTTP server");
    build_http_step.dependOn(&http_server.step);
    b.getInstallStep().dependOn(&http_server.step);

    // build the `ladder` programm
    const ladder = b.addSystemCommand(&.{ "zig", "build" });
    ladder.cwd = b.path("ladder");
    const build_ladder_step = b.step("ladder", "Build the `ladder` programm");
    build_ladder_step.dependOn(&ladder.step);
    b.getInstallStep().dependOn(&ladder.step);

    // build the `ps` programm
    const ps = b.addSystemCommand(&.{ "zig", "build" });
    ps.cwd = b.path("ps");
    const build_ps_step = b.step("ps", "Build the PostScript interpreter");
    build_ps_step.dependOn(&ps.step);
    b.getInstallStep().dependOn(&ps.step);

    // build the `gui` programm
    const gui = b.addSystemCommand(&.{ "zig", "build" });
    gui.cwd = b.path("gui");
    const build_gui_step = b.step("gui", "Build the PostScript interpreter");
    build_gui_step.dependOn(&gui.step);
    b.getInstallStep().dependOn(&gui.step);
}
