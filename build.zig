const std = @import("std");
const Io = std.Io;
var threaded: Io.Threaded = .init_single_threaded;
const io = threaded.ioBasic();

fn fileName(path: []const u8) []const u8 {
    var it = std.mem.tokenizeScalar(u8, path, '/');
    var segment: []const u8 = undefined;
    var idx: u8 = 0;

    while (idx < 254) : (idx += 1) {
        segment = it.next() orelse break;
    }

    return segment;
}

fn baseName(name: []const u8) []const u8 {
    var it = std.mem.tokenizeScalar(u8, name, '.');
    return it.peek().?;
}

fn deleteArtifacts() !void {
    const dir = try std.Io.Dir.cwd().openDir(io, ".", .{ .iterate = true });
    var it = dir.iterate();

    while (try it.next(io)) |entry| {
        if (entry.kind != .file)
            continue;

        if (std.mem.endsWith(u8, entry.name, ".a")) {
            std.debug.print("Cleaning file: {s}\n", .{entry.name});
            try dir.deleteFile(io, entry.name);
        }
    }
}

pub fn build(b: *std.Build) void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    _ = allocator;

    const paths = [_][]const u8{
        "async/example0.zig",
        "async//threaded.zig",
        "base64/base64_basic.zig",
        "basics/hello-world.zig",
        "basics/queue.zig",
    };

    for (paths) |path| {
        std.debug.print("Building Zig module {s} ...\n", .{path});
        const file_name = fileName(path);
        const base_name = baseName(file_name);
        const lib = b.addLibrary(.{
            .name = base_name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(path),
                .target = b.graph.host,
            }),
        });

        b.installArtifact(lib);
    }

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

    deleteArtifacts() catch std.debug.print("Failed to delete build artifacts", .{});
}
