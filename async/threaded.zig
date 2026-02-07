const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

fn juicyMain(gpa: Allocator, io: Io) !void {
    _ = gpa;

    var a = io.async(doWork, .{ io, "hard" });
    var b = io.async(doWork, .{ io, "on an excuse to drink Spezi" });

    a.await(io);
    b.await(io);
}

fn doWork(io: Io, text: []const u8) void {
    std.debug.print("working {s}\n", .{text});
    io.sleep(.fromSeconds(1), .awake) catch {};
}

pub fn main() !void {
    var dbg_alloc: std.heap.DebugAllocator(.{}) = .init;
    defer assert(dbg_alloc.deinit() == .ok);
    const gpa = dbg_alloc.allocator();

    var threaded: Io.Threaded = .init(gpa, .{ .environ = .empty });
    defer threaded.deinit();
    const io = threaded.io();

    return juicyMain(gpa, io);
}
