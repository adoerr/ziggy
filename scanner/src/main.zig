const std = @import("std");

const Description = @import("Description.zig");
const util = @import("util.zig");

pub fn main(_: std.process.Init) !void {
    std.debug.print("Hello Scanner\n", .{});
}

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(util);
    std.testing.refAllDecls(Description);
}
