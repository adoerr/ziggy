const std = @import("std");
const hostname = @import("hostname");

const Io = std.Io;
const HostName = hostname.HostName;

pub fn main(init: std.process.Init) !void {
    var out_buf: [1024]u8 = undefined;
    var out_writer = Io.File.stdout().writer(init.io, &out_buf);
    var stdout = &out_writer.interface;

    const a = try HostName.init("www.heise.de");
    const b = try HostName.init("www.google.com");

    try stdout.print("Hostnames are equal: {}\n", .{HostName.eq(a, b)});
    try stdout.flush();
}
