const std = @import("std");
const options = @import("options");
const Init = std.process.Init;
const Io = std.Io;

pub fn main(init: Init) !void {
    var out_buf: [options.write_buf_sz]u8 = undefined;
    var out_writer = Io.File.stdout().writer(init.io, &out_buf);
    var stdout = &out_writer.interface;

    var err_buf: [1024]u8 = undefined;
    var err_writer = Io.File.stderr().writer(init.io, &err_buf);
    var stderr = &err_writer.interface;

    const cwd = std.Io.Dir.cwd();

    const args = try init.minimal.args.toSlice(init.arena.allocator());

    for (args[1..]) |path| {
        const file = cwd.openFile(init.io, path, .{}) catch {
            stderr.print("failed to open: {s}\n", .{path}) catch {};
            try stderr.flush();
            continue;
        };
        defer file.close(init.io);

        var file_buf: [options.read_buf_sz]u8 = undefined;
        var file_reader = file.reader(init.io, &file_buf);
        var reader = &file_reader.interface;

        _ = try reader.streamRemaining(stdout);
    }

    try stdout.flush();
}
