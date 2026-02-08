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
    };
}
