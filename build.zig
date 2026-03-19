const std = @import("std");

pub fn build(b: *std.Build) void {
    var gpa = std.heap.DebugAllocator(.{}){};
    const allocator = gpa.allocator();
    _ = allocator;

    // build the HTTP Server
    const http_server = b.addSystemCommand(&.{ "zig", "build" });
    http_server.cwd = b.path("http_server");
    const build_http_step = b.step("http_server", "Build the HTTP server");
    build_http_step.dependOn(&http_server.step);
    b.getInstallStep().dependOn(&http_server.step);

    // build `ps`
    const ps = b.addSystemCommand(&.{ "zig", "build" });
    ps.cwd = b.path("ps");
    const build_ps_step = b.step("ps", "Build the PostScript interpreter");
    build_ps_step.dependOn(&ps.step);
    b.getInstallStep().dependOn(&ps.step);

    // build `gui`
    // const gui = b.addSystemCommand(&.{ "zig", "build" });
    // gui.cwd = b.path("gui");
    // const build_gui_step = b.step("gui", "Build the GUI");
    // build_gui_step.dependOn(&gui.step);
    // b.getInstallStep().dependOn(&gui.step);

    // build `send_fd`
    const send_fd = b.addSystemCommand(&.{ "zig", "build" });
    send_fd.cwd = b.path("send_fd");
    const build_send_fd_step = b.step("send_fd", "Build the send file descriptor example");
    build_send_fd_step.dependOn(&send_fd.step);
    b.getInstallStep().dependOn(&send_fd.step);

    // build `protocol`
    const protocol = b.addSystemCommand(&.{ "zig", "build" });
    protocol.cwd = b.path("protocol");
    const build_protocol_step = b.step("protocol", "Build the Wayland wire protocol module");
    build_protocol_step.dependOn(&protocol.step);
    b.getInstallStep().dependOn(&protocol.step);
}
