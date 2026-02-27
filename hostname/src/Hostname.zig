const HostName = @This();

pub const ValidateError = error{ NameTooLong, InvalidHostName };

pub fn validate(_: []const u8) ValidateError!void {
    unreachable;
}
