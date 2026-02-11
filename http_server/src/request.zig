const std = @import("std");
const Io = std.Io;
const mem = std.mem;
const Stream = std.Io.net.Stream;

pub fn readRequest() !void {}

const Map = std.static_string_map.StaticStringMap;
const MethodMap = Map(Method).initComptime(.{.{ "GET", Method.GET }});

pub const Method = enum {
    GET,

    pub fn init(text: []const u8) !Method {
        return MethodMap.get(text).?;
    }

    pub fn isSupported(m: []const u8) bool {
        const method = MethodMap.get(m);
        if (method) |_| {
            return true;
        }
        return false;
    }
};

const Request = struct {
    method: Method,
    version: []const u8,
    uri: []const u8,

    pub fn init(method: Method, uri: []const u8, version: []const u8) Request {
        return Request{
            .method = method,
            .uri = uri,
            .version = version,
        };
    }
};

pub fn parseRequest(text: []const u8) Request {
    const idx = mem.findScalar(u8, text, '\n') orelse text.len;
    var it = mem.splitScalar(u8, text[0..idx], ' ');
    const method = try Method.init(it.next().?);
    const uri = it.next().?;
    const version = it.next().?;
    return Request.init(method, uri, version);
}

const testing = std.testing;

test "Method init" {
    const m = try Method.init("GET");
    try testing.expectEqual(Method.GET, m);
}

test "Method isSupported" {
    try testing.expect(Method.isSupported("GET"));
    try testing.expect(!Method.isSupported("POST"));
    try testing.expect(!Method.isSupported("DELETE"));
}

test "Method parseRequest" {
    const req = "GET / HTTP/1.1\n";
    var it = mem.splitScalar(u8, req, ' ');
    try testing.expectEqualStrings("GET", it.next().?);
    try testing.expectEqualStrings("/", it.next().?);
    try testing.expectEqualStrings("HTTP/1.1\n", it.next().?);

    const idx = mem.findScalar(u8, req, '\n');
    try testing.expect(idx == 14);
}
