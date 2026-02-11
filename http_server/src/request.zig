const std = @import("std");

const Map = std.static_string_map.StaticStringMap;
const MethodMap = Map(Method).initComptime(.{.{ "GET", Method.GET }});

pub const Method = enum {
    GET,

    pub fn init(text: []const u8) !Method {
        return MethodMap.get(text).?;
    }

    pub fn is_supported(m: []const u8) bool {
        const method = MethodMap.get(m);
        if (method) |_| {
            return true;
        }
        return false;
    }
};

const testing = std.testing;

test "Method init" {
    const m = try Method.init("GET");
    try testing.expectEqual(Method.GET, m);
}

test "Method is_supported" {
    try testing.expect(Method.is_supported("GET"));
    try testing.expect(!Method.is_supported("POST"));
    try testing.expect(!Method.is_supported("DELETE"));
}
