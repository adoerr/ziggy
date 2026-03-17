//! By convention, root.zig is the root source file when making a package.
const std = @import("std");

pub const Address = @import("Address.zig");
pub const Server = @import("Server.zig");
pub const Fixed = @import("fixed.zig");
pub const WireFormat = @import("WireFormat.zig");
pub const Message = @import("message.zig").MessageUnion;
pub const Connection = @import("Connection.zig");
pub const ctrl_msg = @import("ctrl_msg.zig");

pub const ProtocolSide = enum { client, server };

test {
    @import("std").testing.refAllDecls(@This());
}
