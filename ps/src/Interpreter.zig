const std = @import("std");

/// Object model - in PorstScript everything is an object.
const ValueType = enum { integer, float, name, executable };

const Value = union(ValueType) {
    integer: i64,
    float: f64,
    name: []const u8, // literal names like `/foo`
    executable: []const u8, // executable name like `add` or `sub`

    /// Print a value to a writer
    pub fn print(self: Value, writer: anytype) !void {
        switch (self) {
            .integer => |i| try writer.print("{d}", .{i}),
            .float => |f| try writer.print("{d}", .{f}),
            .name => |n| try writer.print("/{s}", .{n}),
            .executable => |e| try writer.print("{s}", .{e}),
        }
    }
};

pub const Interpreter = struct {};

const testing = std.testing;

test "Value print" {
    const alloc = testing.allocator;
    var writer = std.Io.Writer.Allocating.init(alloc);
    defer writer.deinit();

    // print integer
    const int = Value{ .integer = 42 };
    try int.print(&writer.writer);

    var int_list = writer.toArrayList();
    try testing.expectEqualStrings("42", int_list.items);
    defer int_list.deinit(alloc);

    // print float
    const float = Value{ .float = 3.14159 };
    try float.print(&writer.writer);

    var float_list = writer.toArrayList();
    try testing.expectEqualStrings("3.14159", float_list.items);
    defer float_list.deinit(alloc);

    // print name
    const name = Value{ .name = "foo" };
    try name.print(&writer.writer);

    var name_list = writer.toArrayList();
    try testing.expectEqualStrings("/foo", name_list.items);
    defer name_list.deinit(alloc);

    // print executable
    const exec = Value{ .executable = "add" };
    try exec.print(&writer.writer);

    var exec_list = writer.toArrayList();
    try testing.expectEqualStrings("add", exec_list.items);
    exec_list.deinit(alloc);
}
