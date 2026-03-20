const std = @import("std");

pub fn snakeToPascal(alloc: std.mem.Allocator, snake: []const u8) ![]u8 {
    var pascal = try std.ArrayList(u8).initCapacity(alloc, snake.len);
    var it = std.mem.tokenizeScalar(u8, snake, '_');

    while (it.next()) |tok| {
        pascal.appendAssumeCapacity(std.ascii.toUpper(tok[0]));
        if (tok.len > 1) {
            pascal.appendSliceAssumeCapacity(tok[1..]);
        }
    }

    return try pascal.toOwnedSlice(alloc);
}

pub fn snakeToCamel(alloc: std.mem.Allocator, snake: []const u8) ![]u8 {
    const camel = try snakeToPascal(alloc, snake);

    if (camel.len > 0) {
        camel[0] = std.ascii.toLower(camel[0]);
    }

    return camel;
}

test "util - snakeToPascal" {
    const expectEqualStrings = std.testing.expectEqualStrings;
    const alloc = std.testing.allocator;

    const s1 = try snakeToPascal(alloc, "hello_world");
    defer alloc.free(s1);
    try expectEqualStrings("HelloWorld", s1);

    const s2 = try snakeToPascal(alloc, "one_two_three");
    defer alloc.free(s2);
    try expectEqualStrings("OneTwoThree", s2);

    const s3 = try snakeToPascal(alloc, "single");
    defer alloc.free(s3);
    try expectEqualStrings("Single", s3);

    const s4 = try snakeToPascal(alloc, "");
    defer alloc.free(s4);
    try expectEqualStrings("", s4);
}

test "util - snakeToCamel" {
    const expectEqualStrings = std.testing.expectEqualStrings;
    const alloc = std.testing.allocator;

    const s1 = try snakeToCamel(alloc, "hello_world");
    defer alloc.free(s1);
    try expectEqualStrings("helloWorld", s1);

    const s2 = try snakeToCamel(alloc, "One_Two_Three");
    defer alloc.free(s2);
    try expectEqualStrings("oneTwoThree", s2);

    const s3 = try snakeToCamel(alloc, "single");
    defer alloc.free(s3);
    try expectEqualStrings("single", s3);

    const s4 = try snakeToCamel(alloc, "");
    defer alloc.free(s4);
    try expectEqualStrings("", s4);
}
