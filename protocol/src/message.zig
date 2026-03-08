const UnionFieldAttrs = @import("std").builtin.Type.UnionField.Attributes;

/// Creates a union of all messages defined in the given `protocols`.
///
/// The resulting type is a tagged union where:
/// - The tag names are the interface names (e.g., "wl_display", "wl_registry").
/// - The payload of each variant is itself a tagged union of the messages defined in that interface.
pub fn MessageUnion(comptime protocols: anytype) type {
    comptime var field_names: []const []const u8 = &.{};
    comptime var enum_values: []const u32 = &.{};
    comptime var union_types: []const type = &.{};
    comptime var union_attrs: []const UnionFieldAttrs = &.{};
    comptime var next_value: u32 = 0;

    inline for (@typeInfo(@TypeOf(protocols)).@"struct".fields) |protocol_field| {
        const protocol = @field(protocols, protocol_field.name);
        inline for (@typeInfo(protocol).@"struct".decls) |interface_decl| {
            const interface = @field(protocol, interface_decl.name);
            if (InterfaceMessageUnion(interface)) |Message| {
                field_names = field_names ++ [_][]const u8{interface.interface};
                union_types = union_types ++ [_]type{Message};
                union_attrs = union_attrs ++ [_]UnionFieldAttrs{.{ .@"align" = @alignOf(Message) }};
                enum_values = enum_values ++ [_]u32{next_value};
                next_value += 1;
            }
        }
    }

    const backing_enum = @Enum(u32, .exhaustive, field_names, @ptrCast(enum_values.ptr));
    return @Union(.auto, backing_enum, field_names, @ptrCast(union_types.ptr), @ptrCast(union_attrs.ptr));
}

/// Creates a union of all messages defined within a specific `Interface`.
///
/// This function scans the `Interface` type (which is expected to be a struct/enum acting as a namespace)
/// for declarations that look like messages. A declaration is considered a message if it is a struct
/// that has the following public declarations:
/// - `_name`: string literal
/// - `_signature`: string literal
/// - `_opcode`: integer value
///
/// Returns `null` if no messages are found in the interface.
fn InterfaceMessageUnion(comptime Interface: type) ?type {
    comptime var field_names: []const []const u8 = &.{};
    comptime var enum_values: []const u32 = &.{};
    comptime var union_types: []const type = &.{};
    comptime var union_attrs: []const UnionFieldAttrs = &.{};
    comptime var next_value: u32 = 0;

    inline for (@typeInfo(Interface).@"enum".decls) |maybe_message_decl| {
        const maybe_message = @field(Interface, maybe_message_decl.name);
        switch (@typeInfo(@TypeOf(maybe_message))) {
            .type => {
                if (@hasDecl(maybe_message, "_name") and
                    @hasDecl(maybe_message, "_signature") and
                    @hasDecl(maybe_message, "_opcode"))
                {
                    field_names = field_names ++ [_][]const u8{@field(maybe_message, "_name")};
                    union_types = union_types ++ [_]type{maybe_message};
                    union_attrs = union_attrs ++ [_]UnionFieldAttrs{.{ .@"align" = @alignOf(maybe_message) }};
                    enum_values = enum_values ++ [_]u32{next_value};
                    next_value += 1;
                }
            },
            else => {},
        }
    }

    if (field_names.len == 0) return null;

    const backing_enum = @Enum(u32, .exhaustive, field_names, @ptrCast(enum_values));
    return @Union(.auto, backing_enum, field_names, @ptrCast(union_types.ptr), @ptrCast(union_attrs.ptr));
}

test "MessageUnion" {
    const std = @import("std");
    const TestProtocol = struct {
        pub const TestInterface = enum(u32) {
            invalid = 0,
            _,

            pub const interface = "test_interface";

            pub const Message1 = struct {
                pub const _name = "message1";
                pub const _signature = "u";
                pub const _opcode = 0;
            };
            pub const Message2 = struct {
                pub const _name = "message2";
                pub const _signature = "i";
                pub const _opcode = 1;
            };
        };
    };

    const Union = MessageUnion(.{TestProtocol});

    // Check top level field
    const info = @typeInfo(Union).@"union";
    try std.testing.expectEqual(1, info.fields.len);
    try std.testing.expectEqualStrings("test_interface", info.fields[0].name);

    // Check inner union
    const Inner = info.fields[0].type;
    const inner_info = @typeInfo(Inner).@"union";
    try std.testing.expectEqual(2, inner_info.fields.len);

    var found_m1: bool = false;
    var found_m2: bool = false;

    inline for (inner_info.fields) |field| {
        if (std.mem.eql(u8, field.name, "message1")) {
            found_m1 = true;
            try std.testing.expect(field.type == TestProtocol.TestInterface.Message1);
        } else if (std.mem.eql(u8, field.name, "message2")) {
            found_m2 = true;
            try std.testing.expect(field.type == TestProtocol.TestInterface.Message2);
        }
    }
    try std.testing.expect(found_m1);
    try std.testing.expect(found_m2);
}
