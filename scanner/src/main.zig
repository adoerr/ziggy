const std = @import("std");

const util = @import("util.zig");

pub fn main(_: std.process.Init) !void {
    std.debug.print("Hello Scanner\n", .{});
}

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(util);
}
