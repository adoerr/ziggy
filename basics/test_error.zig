const std = @import("std");
const Allocator = std.mem.Allocator;
const expectError = std.testing.expectError;

fn allocError(alloc: Allocator) !void {
    var buf = try alloc.alloc(u8, 100);
    buf[0] = 2;
}

test "testing error" {
    var buf: [10]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const alloc = fba.allocator();
    try expectError(error.OutOfMemory, allocError(alloc));
}
