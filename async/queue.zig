const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const debug = std.debug;

fn juicyMain(io: Io) !void {
    var queue: Io.Queue([]const u8) = .init(&.{});

    var t1 = try io.concurrent(producer, .{ io, &queue, "never gonna give you up" });
    defer t1.cancel(io) catch {};

    var t2 = try io.concurrent(consumer, .{ io, &queue });
    defer _ = t2.cancel(io) catch {};

    const res = try t2.await(io);
    debug.print("received message {s}\n", .{res});
}

fn producer(io: Io, queue: *Io.Queue([]const u8), text: []const u8) !void {
    try queue.putOne(io, text);
}

fn consumer(io: Io, queue: *Io.Queue([]const u8)) ![]const u8 {
    return queue.getOne(io);
}

pub fn main() !void {
    var dbg_alloc: std.heap.DebugAllocator(.{}) = .init;
    defer assert(dbg_alloc.deinit() == .ok);
    const gpa = dbg_alloc.allocator();

    var threaded: Io.Threaded = .init(gpa, .{ .environ = .empty });
    defer threaded.deinit();
    const io = threaded.io();

    return juicyMain(io);
}
