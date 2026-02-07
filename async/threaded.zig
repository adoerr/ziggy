const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

fn juicyMain(gpa: Allocator, io: Io) !void {
    _ = gpa;

    doWork(io);
}

fn doWork(io: Io) void {
    std.debug.print("working ...\n", .{});
    io.sleep(.fromSeconds(1), .awake) catch {};
}

pub fn main() !void {
    var dbg_alloc: std.heap.DebugAllocator(.{}) = .init;
    defer assert(dbg_alloc.deinit() == .ok);
    const gpa = dbg_alloc.allocator();

    var threaded: Io.Threaded = .init_single_threaded;
    defer threaded.deinit();
    const io = threaded.io();

    return juicyMain(gpa, io);
}
