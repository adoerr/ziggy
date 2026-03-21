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

pub fn deinit(self: Description, alloc: std.mem.Allocator) void {
    alloc.free(self.summary);
    if (self.body) |body| alloc.free(body);
}

pub fn write(self: *const Description, writer: anytype, prefix: []const u8) !void {
    if (self.body) |body| {
        // Find the start/end of the relevant text.
        const trimmed_body = std.mem.trim(u8, body, " \n\t");
        if (trimmed_body.len == 0) return;

        var it = std.mem.splitScalar(u8, trimmed_body, '\n');
        while (it.next()) |raw_line| {
            // Each line is trimmed individually to remove indentation.
            const line = std.mem.trim(u8, raw_line, " \t");
            if (line.len == 0) {
                try writer.print("{s}\n", .{prefix});
            } else try writer.print("{s}{s}\n", .{ prefix, line });
        }
    } else try printSummary(self.summary, prefix, writer);
}

pub fn printSummary(summary: []const u8, prefix: []const u8, writer: anytype) !void {
    const trimmed = std.mem.trim(u8, summary, " \n\t");
    const needs_period = trimmed[trimmed.len - 1] != '.';
    try writer.print("{s}{c}{s}{s}\n", .{ prefix, std.ascii.toLower(trimmed[0]), trimmed[1..], if (needs_period) "." else "" });
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

test "Description - write full description with indentation" {
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
    defer desc.deinit(std.testing.allocator);

    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();

    try desc.write(&out.writer, "  ");

    const expected =
        \\  The core global object.  This is a special singleton object.  It
        \\  is used for internal Wayland protocol features.
        \\
    ;
    try std.testing.expectEqualStrings(expected, out.written());
}

test "Description - write summary only" {
    const src =
        \\<description summary="the compositor singleton"/>
    ;

    var static_reader = xml.Reader.Static.init(std.testing.allocator, src, .{});
    defer static_reader.deinit();
    var reader = &static_reader.interface;

    while (reader.read()) |node| {
        if (node == .element_start) break;
    } else |err| return err;

    const desc = try Description.parse(std.testing.allocator, reader);
    defer desc.deinit(std.testing.allocator);

    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();

    try desc.write(&out.writer, "  ");

    const expected = "  the compositor singleton.\n";
    try std.testing.expectEqualStrings(expected, out.written());
}
