const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayListUnmanaged;
const fmt = std.fmt;
const mem = std.mem;
const debug = std.debug;

/// Object model - in PorstScript everything is an object.
const ValueType = enum { integer, float, name, executable };

const Value = union(ValueType) {
    integer: i64,
    float: f64,
    name: []const u8, // literal names like `/foo`
    executable: []const u8, // executable name like `add` or `sub`

    /// Print a value to a writer
    pub fn print(self: Value, writer: anytype) !void {
        switch (self) {
            .integer => |i| try writer.print("{d}", .{i}),
            .float => |f| try writer.print("{d}", .{f}),
            .name => |n| try writer.print("/{s}", .{n}),
            .executable => |e| try writer.print("{s}", .{e}),
        }
    }
};

/// PostScript operand stack
const Stack = struct {
    items: ArrayList(Value),
    alloc: Allocator,

    pub fn init(alloc: Allocator) Stack {
        return .{ .items = .{}, .alloc = alloc };
    }

    pub fn deinit(self: *Stack) void {
        self.items.deinit(self.alloc);
    }

    pub fn push(self: *Stack, val: Value) !void {
        try self.items.append(self.alloc, val);
    }

    pub fn pop(self: *Stack) !Value {
        if (self.items.items.len == 0) return error.StackUnderflow;
        return self.items.pop().?;
    }
};

pub const Interpreter = struct {
    stack: Stack,
    io: Io = undefined,

    pub fn init(io: Io, alloc: Allocator) Interpreter {
        return .{ .io = io, .stack = Stack.init(alloc) };
    }

    pub fn deinit(self: *Interpreter) void {
        self.stack.deinit();
    }

    /// Evaluate a single token
    pub fn evaluate(self: *Interpreter, token: []const u8) !void {
        // literal name (starts with '/')
        if (token.len > 1 and token[0] == '/') {
            try self.stack.push(.{ .name = token[1..] });
            return;
        }

        // try parsing as an Integer
        if (fmt.parseInt(i64, token, 10)) |i| {
            try self.stack.push(.{ .integer = i });
            return;
        } else |_| {}

        // try parsing a Float
        if (fmt.parseFloat(f64, token)) |f| {
            try self.stack.push(.{ .float = f });
            return;
        } else |_| {}

        // must be an executable name, either operator or variable
        try self.executeOperator(token);
    }

    fn executeOperator(self: *Interpreter, op: []const u8) !void {
        if (mem.eql(u8, op, "add")) {
            try self.opMath(MathOp.Add);
        } else if (mem.eql(u8, op, "sub")) {
            try self.opMath(MathOp.Sub);
        } else if (mem.eql(u8, op, "mul")) {
            try self.opMath(MathOp.Mul);
        } else if (mem.eql(u8, op, "div")) {
            try self.opMath(MathOp.Div);
        } else if (mem.eql(u8, op, "pstack")) {
            try self.opPstack();
        } else {
            // TODO: lookup operator in dictionary stack
            debug.print("Error: Unknown operator `{s}`", .{op});
            return error.UnknownOperator;
        }
    }

    const MathOp = enum { Add, Sub, Mul, Div };

    /// Match operators
    fn opMath(self: *Interpreter, op: MathOp) !void {
        const b = try self.stack.pop();
        const a = try self.stack.pop();

        if (a == .integer and b == .integer) {
            const result = switch (op) {
                .Add => a.integer + b.integer,
                .Sub => a.integer - b.integer,
                .Mul => a.integer * b.integer,
                .Div => @divTrunc(a.integer, b.integer), // PostScript uses integer division if both operands are ints
            };
            try self.stack.push(.{ .integer = result });
        } else {
            const a_float = switch (a) {
                .integer => |i| @as(f64, @floatFromInt(i)),
                .float => |f| f,
                else => return error.TypeCheck,
            };
            const b_float = switch (b) {
                .integer => |i| @as(f64, @floatFromInt(i)),
                .float => |f| f,
                else => return error.TypeCheck,
            };
            const result = switch (op) {
                .Add => a_float + b_float,
                .Sub => a_float - b_float,
                .Mul => a_float * b_float,
                .Div => a_float / b_float,
            };
            try self.stack.push(.{ .float = result });
        }
    }

    /// Print stack non-destructively (`pstack`)
    fn opPstack(self: *Interpreter) !void {
        var out_buf: [1024]u8 = undefined;
        var out_writer = Io.File.stdout().writer(self.io, &out_buf);
        const stdout = &out_writer.interface;
        var i: usize = self.stack.items.items.len;

        while (i > 0) {
            i -= 1;
            const val = self.stack.items.items[i];
            try val.print(stdout);
            try stdout.print("\n", .{});
            try stdout.flush();
        }
    }
};

const testing = std.testing;
const Writer = std.Io.Writer;

test "Value print" {
    const alloc = testing.allocator;
    var writer = Writer.Allocating.init(alloc);
    defer writer.deinit();

    // print integer
    const int = Value{ .integer = 42 };
    try int.print(&writer.writer);

    var int_list = writer.toArrayList();
    try testing.expectEqualStrings("42", int_list.items);
    defer int_list.deinit(alloc);

    // print float
    const float = Value{ .float = 3.14159 };
    try float.print(&writer.writer);

    var float_list = writer.toArrayList();
    try testing.expectEqualStrings("3.14159", float_list.items);
    defer float_list.deinit(alloc);

    // print name
    const name = Value{ .name = "foo" };
    try name.print(&writer.writer);

    var name_list = writer.toArrayList();
    try testing.expectEqualStrings("/foo", name_list.items);
    defer name_list.deinit(alloc);

    // print executable
    const exec = Value{ .executable = "add" };
    try exec.print(&writer.writer);

    var exec_list = writer.toArrayList();
    try testing.expectEqualStrings("add", exec_list.items);
    exec_list.deinit(alloc);
}

test "Stack push and pop" {
    const alloc = testing.allocator;
    var stack = Stack.init(alloc);
    defer stack.deinit();

    try stack.push(Value{ .integer = 10 });
    try stack.push(Value{ .integer = 20 });

    const val2 = try stack.pop();
    try testing.expectEqual(val2.integer, 20);

    const val1 = try stack.pop();
    try testing.expectEqual(val1.integer, 10);

    try testing.expectError(error.StackUnderflow, stack.pop());

    try stack.push(Value{ .name = "foo" });

    const val3 = try stack.pop();
    try testing.expectEqual(val3.name, "foo");

    try testing.expectError(error.StackUnderflow, stack.pop());
}

test "Interpreter arithmetic" {
    const alloc = testing.allocator;
    // Pass undefined for IO since we only test arithmetic
    var interp = Interpreter.init(undefined, alloc);
    defer interp.deinit();

    // Test addition
    try interp.evaluate("10");
    try interp.evaluate("20");
    try interp.evaluate("add");

    var result = try interp.stack.pop();
    try testing.expectEqual(result.integer, 30);

    // Push 30 back (was popped)
    try interp.stack.push(.{ .integer = 30 });

    // Test multiplication
    try interp.evaluate("5.5");
    try interp.evaluate("mul"); // 30 * 5.5 = 165.0
    result = try interp.stack.pop();
    try testing.expectApproxEqAbs(result.float, 165.0, 0.0001);

    // Test division
    // Push 100, 20 (evaluate "add" was last, stack empty)
    try interp.evaluate("100");
    try interp.evaluate("20");
    try interp.evaluate("div"); // 100 / 20 = 5 (integer division as implemented)
    result = try interp.stack.pop();
    try testing.expectEqual(result.integer, 5);

    // Test float division
    try interp.evaluate("10.0");
    try interp.evaluate("2.0");
    try interp.evaluate("div"); // 5.0
    result = try interp.stack.pop();
    try testing.expectEqual(result.float, 5.0);

    // Test subtraction
    try interp.evaluate("10");
    try interp.evaluate("3");
    try interp.evaluate("sub"); // 7
    result = try interp.stack.pop();
    try testing.expectEqual(result.integer, 7);
}

test "Interpreter error handling" {
    const alloc = testing.allocator;
    var interp = Interpreter.init(undefined, alloc);
    defer interp.deinit();

    // Stack underflow
    try testing.expectError(error.StackUnderflow, interp.evaluate("add"));

    // Unknown operator
    try testing.expectError(error.UnknownOperator, interp.evaluate("unknown_op"));
}

test "Interpreter pstack" {
    const alloc = testing.allocator;
    var interp = Interpreter.init(testing.io, alloc);
    defer interp.deinit();

    try interp.evaluate("10");
    try interp.evaluate("pstack");
}
