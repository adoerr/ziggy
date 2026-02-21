const std = @import("std");
const Io = std.Io;

pub fn main(init: std.process.Init) !void {
    const path = "./assets/meow.txt";

    var out_buf: [1024]u8 = undefined;
    var out_writer = Io.File.stdout().writer(init.io, &out_buf);
    var stdout = &out_writer.interface;

    var err_buf: [1024]u8 = undefined;
    var err_writer = Io.File.stderr().writer(init.io, &err_buf);
    var stderr = &err_writer.interface;

    const cwd = std.Io.Dir.cwd();

    const file = cwd.openFile(init.io, path, .{}) catch |err| {
        try stderr.print("failed to open: {s}\n", .{path});
        return err;
    };
    defer file.close(init.io);

    var file_buf: [1014]u8 = undefined;
    var file_reader = file.reader(init.io, &file_buf);
    var reader = &file_reader.interface;

    _ = try reader.streamRemaining(stdout);
    try stdout.flush();
}
