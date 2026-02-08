const std = @import("std");

pub fn Queue(comptime Child: type) type {
    return struct {
        const Self = @This();
        const Node = struct {
            data: Child,
            next: ?*Node,
        };
        gpa: std.mem.Allocator,
        start: ?*Node,
        end: ?*Node,

        pub fn init(gpa: std.mem.Allocator) Self {
            return Self{
                .gpa = gpa,
                .start = null,
                .end = null,
            };
        }

        pub fn enqueue(self: *Self, value: Child) !void {
            const node = try self.gpa.create(Node);
            node.* = .{ .data = value, .next = null };
            if (self.end) |end| end.next = node else self.start = node;
            self.end = node;
        }

        pub fn dequeue(self: *Self) ?Child {
            const start = self.start orelse return null;
            defer self.gpa.destroy(start);
            if (start.next) |next|
                self.start = next
            else {
                self.start = null;
                self.end = null;
            }
            return start.data;
        }
    };
}

test "queue" {
    var q = Queue(i32).init(std.testing.allocator);

    try q.enqueue(25);
    try q.enqueue(50);
    try q.enqueue(75);
    try q.enqueue(100);

    try std.testing.expectEqual(q.dequeue(), 25);
    try std.testing.expectEqual(q.dequeue(), 50);
    try std.testing.expectEqual(q.dequeue(), 75);
    try std.testing.expectEqual(q.dequeue(), 100);
    try std.testing.expectEqual(q.dequeue(), null);

    try q.enqueue(5);
    try std.testing.expectEqual(q.dequeue(), 5);
    try std.testing.expectEqual(q.dequeue(), null);
}
