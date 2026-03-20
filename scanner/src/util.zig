const std = @import("std");

pub fn snakeToPascal(alloc: std.mem.Allocator, snake: []const u8) !u8 {
    var pascal = try std.ArrayList(u8).initCapacity(alloc, snake.len);
    var it = std.mem.tokenizeScalar(u8, snake, '_');

    while (it.next()) |tok| {
        // first token char becomes uppercase
        pascal.appendAssumeCapacity(std.ascii.toUpper(tok[0]));
        // remaining chars are copied as is
        if (tok.len > 1) pascal.appendAssumeCapacity(tok[1..]);
    }

    return try pascal.toOwnedSlice(alloc);
}

pub fn snakeToCamel(alloc: std.mem.Allocator, snake: []const u8) !u8 {
    var camel = try snakeToPascal(alloc, snake);
    camel[0] = std.ascii.toLower(camel[0]);
    return camel;
}
