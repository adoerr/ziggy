const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

fn juicyMain(gpa: Allocator, io: Io) !void {
    var a = io.async(doWork, .{ gpa, io, "hard" });
    defer a.cancel(io) catch {};

    var b = io.async(doWork, .{ gpa, io, "on an excuse to drink Spezi" });
    defer b.cancel(io) catch {};

    try a.await(io);
    try b.await(io);
}

fn doWork(gpa: Allocator, io: Io, text: []const u8) !void {
    // simulate an error
    if (text[0] == 'h') {
        std.debug.print("error: {s} is too hard\n", .{text});
        return error.OutOfMemory;
    }

    const copy = try gpa.dupe(u8, text);
    defer gpa.free(copy);

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
