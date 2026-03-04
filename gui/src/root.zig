const std = @import("std");

pub fn randomize(buf: []u8) !void {
    var ts: std.os.linux.timespec = undefined;
    _ = std.os.linux.clock_gettime(.REALTIME, &ts);

    for (buf) |*byte| {
        byte.* = @as(u8, @intCast((ts.nsec & 15) + (ts.nsec & 16) * 2));
        ts.nsec >>= 1;
    }
}
