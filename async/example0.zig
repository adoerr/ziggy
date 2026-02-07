const std = @import("std");

pub fn main() !void {
    doWork();
}

fn doWork() void {
    std.debug.print("working ...\n", .{});
    var timespec: std.posix.timespec = .{ .sec = 1, .nsec = 0 };
    _ = std.posix.system.nanosleep(&timespec, &timespec);
}
