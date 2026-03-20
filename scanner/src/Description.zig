//! Parse Wayland protocol interface description

const std = @import("std");
const xml = @import("xml");

const Description = @This();

summary: []const u8,
body: ?[]const u8,

pub fn parse(alloc: std.mem.Allocator, reader: *xml.Reader) !Description {
    const summary_idx = reader.attributeIndex("summary") orelse return error.SummaryNotFound;
    const summary = try reader.attributeValueAlloc(alloc, summary_idx);
    errdefer alloc.free(summary);

    var body = try std.ArrayList(u8).initCapacity(alloc, 1024);
    defer body.deinit(alloc);

    while (reader.read()) |node| switch (node) {
        .element_end => {
            if (!std.mem.eql(u8, reader.elementName(), "description")) return error.UnexpectedElementEnd;
            break;
        },
        .text => try body.appendSlice(alloc, reader.textRaw()),
        .eof => return error.UnexpectedEof,
        else => {},
    } else |err| return err;

    const maybe_body = if (body.items.len > 0) try body.toOwnedSlice(alloc) else null;
    return .{ .summary = summary, .body = maybe_body };
}

test "Description - parse simple description" {
    const src =
        \\<description summary="foo">
        \\    bar
        \\</description>
    ;

    var static_reader = xml.Reader.Static.init(std.testing.allocator, src, .{});
    defer static_reader.deinit();
    var reader = &static_reader.interface;

    while (reader.read()) |node| {
        if (node == .element_start) break;
    } else |err| return err;

    const desc = try Description.parse(std.testing.allocator, reader);
    defer {
        std.testing.allocator.free(desc.summary);
        if (desc.body) |text| std.testing.allocator.free(text);
    }

    try std.testing.expectEqualStrings("foo", desc.summary);
    try std.testing.expect(desc.body != null);
    try std.testing.expectEqualStrings("\n    bar\n", desc.body.?);
}

test "Description - parse empty description" {
    const src =
        \\<description summary="empty"/>
    ;

    var static_reader = xml.Reader.Static.init(std.testing.allocator, src, .{});
    defer static_reader.deinit();
    var reader = &static_reader.interface;

    while (reader.read()) |node| {
        if (node == .element_start) break;
    } else |err| return err;

    const desc = try Description.parse(std.testing.allocator, reader);
    defer {
        std.testing.allocator.free(desc.summary);
        if (desc.body) |text| std.testing.allocator.free(text);
    }

    try std.testing.expectEqualStrings("empty", desc.summary);
    try std.testing.expect(desc.body == null);
}

test "Description - parse missing summary" {
    const src =
        \\<description>
        \\    oops
        \\</description>
    ;

    var static_reader = xml.Reader.Static.init(std.testing.allocator, src, .{});
    defer static_reader.deinit();
    var reader = &static_reader.interface;

    while (reader.read()) |node| {
        if (node == .element_start) break;
    } else |err| return err;

    try std.testing.expectError(error.SummaryNotFound, Description.parse(std.testing.allocator, reader));
}

test "Description - parse real wayland description" {
    const src =
        \\<description summary="core global object">
        \\      The core global object.  This is a special singleton object.  It
        \\      is used for internal Wayland protocol features.
        \\    </description>
    ;

    var static_reader = xml.Reader.Static.init(std.testing.allocator, src, .{});
    defer static_reader.deinit();
    var reader = &static_reader.interface;

    while (reader.read()) |node| {
        if (node == .element_start) break;
    } else |err| return err;

    const desc = try Description.parse(std.testing.allocator, reader);
    defer {
        std.testing.allocator.free(desc.summary);
        if (desc.body) |text| std.testing.allocator.free(text);
    }

    try std.testing.expectEqualStrings("core global object", desc.summary);
    try std.testing.expect(desc.body != null);
    // Verify part of the body
    const body = desc.body.?;
    try std.testing.expect(std.mem.indexOf(u8, body, "The core global object.") != null);
}
