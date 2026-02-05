const std = @import("std");

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

pub fn build(b: *std.Build) void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator;
    _ = allocator;

    const paths = [_][]const u8{
        "basics/hello-world.zig",
    };

    for (paths) |path| {
        std.debug.print("Building Zig module {s}...\n", .{path});
        const file_name = fileName(path);
        const base_name = baseName(file_name);
        const lib = b.addLibrary(.{
            .name = base_name,
            .root_module = b.crateModule(.{
                .root_source_file = b.path(path),
                .target = b.graph.host,
            }),
        });

        b.installArtifact(lib);
    }
}
