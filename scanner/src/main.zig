const std = @import("std");

pub fn main(_: std.process.Init) !void {
    std.debug.print("Hello Scanner\n", .{});
}

test {
    @import("std").testing.refAllDecls(@This());
}
