const std = @import("std");
const Chunk = @import("chunk.zig");
const Op = Chunk.Op;
const Value = @import("value.zig").Value;
const Size = @import("chunk.zig").Size;
const dbg = @import("main.zig").dbg;
const print_value_writer = @import("value.zig").print_value_writer;
const print_value = @import("value.zig").print_value;
const print = std.debug.print;
const assert = std.debug.assert;
const panic = std.debug.panic;

const Self = @This();
const STACK_MAX = 256;
chunk: ?*Chunk,
ip: [*]u8,
stack: [STACK_MAX]Value,
stack_top: [*]Value,
writer: std.io.AnyWriter,
const Result = enum {
    INTERPRET_OK,
    INTERPRET_COMPILE_ERROR,
    INTERPRET_RUNTIME_ERROR,
};

pub fn init(self: *Self, writer: std.io.AnyWriter) void {
    self.chunk = null;
    self.writer = writer;
    self.ip = &[_]u8{};
    self.reset_stack();
}
pub fn deinit(_: *Self) void {
    // print("{any}", .{self});
}
fn reset_stack(self: *Self) void {
    self.stack = .{.null} ** STACK_MAX;
    self.stack_top = self.stack[0..];
}
pub fn push(self: *Self, value: Value) void {
    self.stack_top[0] = value;
    self.stack_top += 1;
}
pub fn pop(self: *Self) Value {
    // TODO: probably remove this? tbh it really only effects debug so maybe only in debug
    self.stack_top[0] = .null;
    self.stack_top -= 1;
    return self.stack_top[0];
}

pub fn interpret(self: *Self, chunk: *Chunk) !Result {
    self.chunk = chunk;
    self.ip = chunk.code.ptr;
    return self.run();
}

pub fn run(self: *Self) !Result {
    while (true) {
        if (dbg) {
            //
            print("DEBUG\n", .{});
            for (self.stack) |value| {
                print("[ ", .{});
                print_value(value);
                print(" ]", .{});
            }
            print("\n", .{});
            const offset: u24 = @intCast(self.ip - self.chunk.?.code.ptr);
            _ = self.chunk.?.disassemble_instruction(offset);
        }
        const instruction: Op = @enumFromInt(self.read_byte());
        switch (instruction) {
            .RETURN => {
                try print_value_writer(self.pop(), self.writer);
                try self.writer.print("\n", .{});
                return Result.INTERPRET_OK;
            },
            .CONSTANT => {
                const constant = self.read_constant();
                self.push(constant);
            },
            .CONSTANT_LONG => {
                const constant = self.read_constant_long();
                self.push(constant);
            },
            .NEGATE => {
                const constant = self.pop();
                switch (constant) {
                    .float => |f| self.push(Value{ .float = -f }),
                    else => unreachable,
                }
            },
            .ADD, .SUBTRACT, .MULTIPLY, .DIVIDE => |op| self.binary_op(op),
            // else => unreachable,
        }
    }
}

fn read_byte(self: *Self) u8 {
    defer self.ip += 1;
    return self.ip[0];
}

fn read_constant(self: *Self) Value {
    if (self.chunk) |chunk| {
        return chunk.constants.values[self.read_byte()];
    }
    panic("CHUNK is NULL", .{});
}
fn read_constant_long(self: *Self) Value {
    if (self.chunk) |chunk| {
        const idx: u24 =
            self.read_byte() +
            (@as(u24, self.read_byte()) << 8) +
            (@as(u24, self.read_byte()) << 16);
        return chunk.constants.values[idx];
    }
    panic("CHUNK is NULL", .{});
}
fn binary_op(self: *Self, op: Op) void {
    const b = self.pop();
    const a = self.pop();
    assert(std.meta.activeTag(b) == std.meta.activeTag(a));
    assert(b == .float);
    switch (op) {
        Op.ADD => self.push(.{ .float = a.float + b.float }),
        Op.SUBTRACT => self.push(.{ .float = a.float - b.float }),
        Op.MULTIPLY => self.push(.{ .float = a.float * b.float }),
        Op.DIVIDE => self.push(.{ .float = a.float / b.float }),
        else => unreachable,
    }
}
