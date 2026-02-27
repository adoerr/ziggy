const std = @import("std");
const Io = std.Io;
var threaded: Io.Threaded = .init_single_threaded;
const io = threaded.ioBasic();

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

    // build the `cat` programm
    const cat = b.addSystemCommand(&.{ "zig", "build" });
    cat.cwd = b.path("cat");
    const build_cat_step = b.step("cat", "Build the `cat` programm");
    build_cat_step.dependOn(&cat.step);
    b.getInstallStep().dependOn(&cat.step);

    // build the `ladder` programm
    const ladder = b.addSystemCommand(&.{ "zig", "build" });
    ladder.cwd = b.path("ladder");
    const build_ladder_step = b.step("ladder", "Build the `ladder` programm");
    build_ladder_step.dependOn(&ladder.step);
    b.getInstallStep().dependOn(&ladder.step);

    // build the 'sysinfo' programm
    const sysinfo = b.addSystemCommand(&.{ "zig", "build" });
    sysinfo.cwd = b.path("sysinfo");
    const build_sysinfo_step = b.step("sysinfo", "Build the `sysinfo` programm");
    build_sysinfo_step.dependOn(&sysinfo.step);
    b.getInstallStep().dependOn(&sysinfo.step);

    // build the `ps` programm
    const ps = b.addSystemCommand(&.{ "zig", "build" });
    ps.cwd = b.path("ps");
    const build_ps_step = b.step("ps", "Build the PostScript interpreter");
    build_ps_step.dependOn(&ps.step);
    b.getInstallStep().dependOn(&ps.step);
}
