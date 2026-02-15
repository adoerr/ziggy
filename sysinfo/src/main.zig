const std = @import("std");
const Io = std.Io;

const sysinfo = @import("sysinfo");

pub fn main(init: std.process.Init) !void {
    _ = init.gpa;
}
