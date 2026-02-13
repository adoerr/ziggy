const std = @import("std");
const Io = std.Io;
const debug = std.debug;
const log = std.log.scoped(.client);
const http = std.http;
const Uri = std.Uri;

pub const std_options = std.Options{
    .log_level = .debug,
};

pub fn main(init: std.process.Init) !void {
    var client = http.Client{ .io = init.io, .allocator = init.gpa };
    defer client.deinit();

    const uri = try Uri.parse("http://127.0.0.1:3490");

    var req = try client.request(.GET, uri, .{});
    req.deinit();
    _ = try req.sendBodiless();
}
