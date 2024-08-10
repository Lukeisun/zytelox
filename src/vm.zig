const std = @import("std");
const Chunk = @import("chunk.zig");
const Op = Chunk.Op;
const Value = @import("value.zig").Value;
const Size = @import("chunk.zig").Size;
const dbg = @import("main.zig").dbg;
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
const Result = enum {
    INTERPRET_OK,
    INTERPRET_COMPILE_ERROR,
    INTERPRET_RUNTIME_ERROR,
};

pub fn init(self: *Self) void {
    self.chunk = null;
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
    self.stack_top -= 1;
    return self.stack_top[0];
}

pub fn interpret(self: *Self, chunk: *Chunk) Result {
    self.chunk = chunk;
    self.ip = chunk.code.ptr;
    return self.run();
}

pub fn run(self: *Self) Result {
    while (true) {
        if (dbg) {
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
            .OP_RETURN => {
                print_value(self.pop());
                print("\n", .{});
                return Result.INTERPRET_OK;
            },
            .OP_CONSTANT => {
                const constant = self.read_constant();
                self.push(constant);
            },
            .OP_CONSTANT_LONG => {
                const constant = self.read_constant_long();
                self.push(constant);
            },
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
