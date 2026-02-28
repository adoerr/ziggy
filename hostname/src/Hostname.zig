const std = @import("std");
const ascii = std.ascii;
const testing = std.testing;

pub const HostName = @This();

// validated, hostname bytes as a static variable
bytes: []const u8,

/// Max supported host name length
pub const MAX_LEN = 255;

pub const ValidateError = error{ NameTooLong, InvalidHostName };

/// Validates a hostname according to [RFC 1123](https://www.rfc-editor.org/rfc/rfc1123)
pub fn validate(bytes: []const u8) ValidateError!void {
    if (bytes.len == 0) return error.InvalidHostName;
    if (bytes[0] == '.') return error.InvalidHostName;

    // a trailing dot in the FQDN doesn't count toward host name length
    const end = if (bytes[bytes.len - 1] == '.') end: {
        if (bytes.len == 1) return error.InvalidHostName;
        break :end bytes.len - 1;
    } else bytes.len;

    if (end > MAX_LEN) return error.NameTooLong;

    // for each hostname `label` (substring)
    // - lenght must be > 0 and < 63
    // - first character is alphanumeric
    // - last character is alphanumeric
    // - middle character is alphanumeric OR '-'
    var label_start: usize = 0;
    var label_len: usize = 0;

    for (bytes[0..end], 0..) |c, i| {
        switch (c) {
            '.' => {
                if (label_len == 0 or label_len > 63) return error.InvalidHostName;
                if (!ascii.isAlphanumeric(bytes[label_start])) return error.InvalidHostName;
                if (!ascii.isAlphanumeric(bytes[i - 1])) return error.InvalidHostName;

                label_start = i + 1;
                label_len = 0; // labels are separated by dots
            },
            '-' => {
                label_len += 1;
            },
            else => {
                if (!ascii.isAlphanumeric(c)) return error.InvalidHostName;
                label_len += 1;
            },
        }
    }

    // validate final label
    if (label_len == 0 or label_len > 63) return error.InvalidHostName;
    if (!ascii.isAlphanumeric(bytes[label_start])) return error.InvalidHostName;
    if (!ascii.isAlphanumeric(bytes[end - 1])) return error.InvalidHostName;
}

test validate {
    // valid hostnames
    try validate("example");
    try validate("example.com");
    try validate("www.example.com");
    try validate("sub.domain.example.com");
    try validate("example.com.");
    try validate("host-name.example.com.");
    try validate("123.example.com.");
    try validate("a-b.com");
    try validate("a.b.c.d.e.f.g");
    try validate("127.0.0.1"); // numberic hostnames are valid
    try validate("a" ** 63 ++ ".com"); // label exactly 63 chars (valid)
    try validate("a." ** 127 ++ "a"); // total length 255 (valid)

    // invalid hostnames
    try testing.expectError(error.InvalidHostName, validate(""));
    try testing.expectError(error.InvalidHostName, validate(".example.com"));
    try testing.expectError(error.InvalidHostName, validate("example.com.."));
    try testing.expectError(error.InvalidHostName, validate("host..domain"));
    try testing.expectError(error.InvalidHostName, validate("-hostname"));
    try testing.expectError(error.InvalidHostName, validate("hostname-"));
    try testing.expectError(error.InvalidHostName, validate("a.-.b"));
    try testing.expectError(error.InvalidHostName, validate("host_name.com"));
    try testing.expectError(error.InvalidHostName, validate("."));
    try testing.expectError(error.InvalidHostName, validate(".."));
    try testing.expectError(error.InvalidHostName, validate("a" ** 64 ++ ".com")); // label length 64 (too loang)
    try testing.expectError(error.NameTooLong, validate("a." ** 127 ++ "ab")); // total length 256 (too long)
}

pub fn init(bytes: []const u8) ValidateError!HostName {
    try validate(bytes);
    return .{ .bytes = bytes };
}

pub fn sameParentDomain(parent: HostName, child: HostName) bool {
    const parent_bytes = parent.bytes;
    const child_bytes = child.bytes;

    if (!ascii.endsWithIgnoreCase(child_bytes, parent_bytes)) return false;
    if (child_bytes.len == parent_bytes.len) return true;
    if (parent_bytes.len > child_bytes.len) return false;
    return child_bytes[child_bytes.len - parent_bytes.len - 1] == '.';
}

test sameParentDomain {
    try testing.expect(!sameParentDomain(try .init("foo.com"), try .init("bar.com")));
    try std.testing.expect(sameParentDomain(try .init("foo.com"), try .init("foo.com")));
    try std.testing.expect(sameParentDomain(try .init("foo.com"), try .init("bar.foo.com")));
    try std.testing.expect(!sameParentDomain(try .init("bar.foo.com"), try .init("foo.com")));
}

/// Domain names are case-insensitive (RFC 5890, Section 2.3.2.4)
pub fn eq(a: HostName, b: HostName) bool {
    return ascii.eqlIgnoreCase(a.bytes, b.bytes);
}
