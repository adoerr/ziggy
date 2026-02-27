const std = @import("std");
const testing = std.testing;

const HostName = @This();

/// Max supported host name length
pub const MAX_LEN = 255;

pub const ValidateError = error{ NameTooLong, InvalidHostName };

/// Validates a hostname according to [RFC 1123](https://www.rfc-editor.org/rfc/rfc1123)
pub fn validate(bytes: []const u8) ValidateError!void {
    if (bytes.len == 0) return error.InvalidHostName;
    if (bytes[0] == '.') return error.InvalidHostName;

    // A trailing do in the FQDN doesn't cound toward host name length
    const end = if (bytes[bytes.len - 1] == '.') end: {
        if (bytes.len == 1) return error.InvalidHostName;
        break :end bytes.len - 1;
    } else bytes.len;

    if (end > MAX_LEN) return error.NameTooLong;
}

test {
    try testing.expectError(error.InvalidHostName, validate(""));
    try testing.expectError(error.InvalidHostName, validate(".example.com"));
}
