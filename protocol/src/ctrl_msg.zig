//! The simplest way for getting pixels from a client to a compositor is
//! through shared memory. In order to do so, a client creates a shared
//! memory file and transfers the respective file descriptor to the
//! compositor. File descriptor transfer is done using so called ancillary
//! data.

const std = @import("std");

const alignment: usize = @sizeOf(usize);

/// Represents a control message header
pub const Header = extern struct {
    cmsg_len: usize,
    cmsg_level: c_int = std.posix.SOL.SOCKET,
    cmsg_type: c_int = std.posix.SCM.RIGHTS,
};

/// Returns `size` aligned to `@sizeOf(usize)`. Equivalent to `CMSG_ALIGN`.
pub fn @"align"(size: usize) usize {
    return size + alignment - 1 & ~(alignment - 1);
}

/// Returns the padding needed to align `size` to `@sizeOf(usize)`.
pub fn padding(size: usize) usize {
    return (alignment - (size & (alignment - 1))) & (alignment - 1);
}

/// Returns the length of a control message payload including the header,
/// for `count` file descriptors. Equivalent to `CMSG_LEN`.
pub fn length(count: usize) usize {
    return @"align"(@sizeOf(Header)) + count * @sizeOf(std.posix.fd_t);
}

/// Returns the total space required for a control message including the
/// header and padding, for `count` file descriptors. Equivalent to `CMSG_SPACE`.
pub inline fn space(count: usize) usize {
    return @"align"(@sizeOf(Header)) + @"align"(count * @sizeOf(std.posix.fd_t));
}

/// Returns the first control message header in `msghdr`. Equivalent to `CMSG_FIRSTHDR`.
pub fn firstHeader(msghdr: *const std.posix.msghdr) ?*const Header {
    return if (msghdr.controllen >= @sizeOf(Header) and msghdr.control != null)
        @as(*const Header, @ptrCast(@alignCast(msghdr.control.?)))
    else
        null;
}

/// Returns the next control message header after `ctrl_msg`. Equivalent to `CMSG_NXTHDR`.
pub fn nextHeader(msghdr: *const std.posix.msghdr, ctrl_msg: *const Header) ?*const Header {
    const ctrl_ptr: [*]align(alignment) const u8 = @ptrCast(@alignCast(msghdr.control.?));
    const cmsg_ptr: [*]align(alignment) const u8 = @ptrCast(ctrl_msg);
    const size_needed = @sizeOf(Header) + padding(ctrl_msg.cmsg_len);

    if (ctrl_ptr + msghdr.controllen - cmsg_ptr < size_needed or
        ctrl_ptr + msghdr.controllen - cmsg_ptr - size_needed < ctrl_msg.cmsg_len)
        return null;

    return @as(*const Header, @ptrCast(@alignCast(cmsg_ptr + @"align"(ctrl_msg.cmsg_len))));
}

/// Returns the data portion of the control message as a byte slice. Equivalent to `CMSG_DATA`.
pub fn data(ctrl_msg: *const Header) []const u8 {
    const many_ptr = @as([*]const Header, @ptrCast(ctrl_msg));
    const data_ptr = @as([*]const u8, @ptrCast(many_ptr + 1));
    const len = ctrl_msg.cmsg_len - length(0);
    return data_ptr[0..len];
}

test "ctrl_msg" {
    // Basic alignment checks
    try std.testing.expectEqual(alignment, @"align"(1));
    try std.testing.expectEqual(alignment, @"align"(alignment));
    try std.testing.expectEqual(2 * alignment, @"align"(alignment + 1));

    // Space calculation for a single file descriptor
    const size_1 = space(1);
    try std.testing.expectEqual(@"align"(@sizeOf(Header)) + @"align"(@sizeOf(std.posix.fd_t)), size_1);

    // Mock buffer for control message
    var buf: [256]u8 align(alignment) = undefined;
    const buf_slice = buf[0..size_1];
    var msghdr: std.posix.msghdr = undefined;
    msghdr.control = buf_slice.ptr;
    msghdr.controllen = @intCast(buf_slice.len);

    // Test firstHeader with empty/invalid control buffer
    msghdr.controllen = 0;
    try std.testing.expectEqual(null, firstHeader(&msghdr));
    msghdr.controllen = @intCast(buf_slice.len);

    // Initialize a valid header
    const hdr_ptr = @as(*Header, @ptrCast(buf_slice.ptr));
    hdr_ptr.cmsg_len = length(1);
    hdr_ptr.cmsg_level = std.posix.SOL.SOCKET;
    hdr_ptr.cmsg_type = std.posix.SCM.RIGHTS;

    // Test firstHeader with valid buffer
    const first = firstHeader(&msghdr);
    try std.testing.expect(first != null);
    try std.testing.expectEqual(hdr_ptr, first.?);

    // Test data access
    const data_slice = data(first.?);
    try std.testing.expectEqual(@sizeOf(std.posix.fd_t), data_slice.len);

    // Test nextHeader (single message, so next should be null)
    try std.testing.expectEqual(null, nextHeader(&msghdr, first.?));

    // Test multiple messages if space allows
    const size_2 = space(1) + space(1);
    if (size_2 <= buf.len) {
        var msghdr2: std.posix.msghdr = undefined;
        msghdr2.control = &buf;
        msghdr2.controllen = @intCast(size_2);

        // First message
        const first_ptr = @as(*Header, @ptrCast(&buf));
        first_ptr.cmsg_len = length(1);
        first_ptr.cmsg_level = std.posix.SOL.SOCKET;
        first_ptr.cmsg_type = std.posix.SCM.RIGHTS;

        // Second message setup
        // Use 'align' to find offset for the second message using byte pointers
        const offset = @"align"(first_ptr.cmsg_len);

        // Ensure we are working with aligned pointers
        const second_ptr_raw = @intFromPtr(&buf) + offset;
        const second_ptr = @as(*Header, @ptrFromInt(second_ptr_raw));
        second_ptr.cmsg_len = length(1);
        second_ptr.cmsg_level = std.posix.SOL.SOCKET;
        second_ptr.cmsg_type = std.posix.SCM.RIGHTS;

        const first_cmsg = firstHeader(&msghdr2);
        try std.testing.expect(first_cmsg != null);
        try std.testing.expectEqual(first_ptr, first_cmsg.?);

        const second_cmsg = nextHeader(&msghdr2, first_cmsg.?);
        try std.testing.expect(second_cmsg != null);
        try std.testing.expectEqual(second_ptr, second_cmsg.?);

        // Third should be null
        try std.testing.expectEqual(null, nextHeader(&msghdr2, second_cmsg.?));
    }
}
