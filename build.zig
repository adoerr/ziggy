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

    deleteArtifacts() catch std.debug.print("Failed to delete build artifacts", .{});
}
