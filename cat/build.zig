const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const read_buf_sz = b.option(usize, "read_buf_sz", "Reader buffer size") orelse 1024;
    const write_buf_sz = b.option(usize, "write_buf_sz", "Writer buffer size") orelse 1024;

    // add build options
    const options = b.addOptions();
    options.addOption(usize, "read_buf_sz", read_buf_sz);
    options.addOption(usize, "write_buf_sz", write_buf_sz);

    const options_mod = options.createModule();

    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    mod.addImport("options", options_mod);

    const exe = b.addExecutable(.{
        .name = "cat",
        .root_module = mod,
    });

    b.installArtifact(exe);
}
