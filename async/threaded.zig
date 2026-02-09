const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const debug = std.debug;

fn juicyMain(gpa: Allocator, io: Io) !void {
    var a = io.async(doWork, .{ gpa, io, "hard" });
    defer if (a.cancel(io)) |s| gpa.free(s) else |_| {};

    var b = io.async(doWork, .{ gpa, io, "on an excuse to drink Spezi" });
    defer if (b.cancel(io)) |s| gpa.free(s) else |_| {};

    const a_str = try a.await(io);
    const b_str = try b.await(io);
    debug.print("finished {s}\n", .{a_str});
    debug.print("finished {s}\n", .{b_str});
}

fn doWork(gpa: Allocator, io: Io, text: []const u8) ![]u8 {
    const string = try gpa.dupe(u8, text);
    debug.print("working {s}\n", .{string});

    io.sleep(.fromSeconds(1), .awake) catch {};
    return string;
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
