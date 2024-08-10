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
ip: ?[]u8,
offset: Size = 0,
stack: [STACK_MAX]Value = [_]Value{.{.null}} ** STACK_MAX,
stack_top: [*]Value,
const Result = enum {
    INTERPRET_OK,
    INTERPRET_COMPILE_ERROR,
    INTERPRET_RUNTIME_ERROR,
};

pub fn init(self: *Self) void {
    self.chunk = null;
    self.ip = null;
    self.reset_stack();
}
pub fn deinit(_: *Self) void {
    // print("{any}", .{self});
}
fn reset_stack(self: *Self) void {
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
    self.ip = chunk.code;
    return self.run();
}

pub fn run(self: *Self) Result {
    while (true) {
        if (dbg) {
            print("DEBUG\n", .{});
            _ = self.chunk.?.disassemble_instruction(self.offset);
        }
        const instruction: Op = @enumFromInt(self.read_byte());
        switch (instruction) {
            .OP_RETURN => return Result.INTERPRET_OK,
            .OP_CONSTANT => {
                const constant = self.read_constant();
                print_value(constant);
                print("\n", .{});
                return Result.INTERPRET_OK;
            },
            else => unreachable,
        }
    }
}

fn read_byte(self: *Self) u8 {
    if (self.ip) |ip| {
        defer self.ip = ip[1..];
        self.offset += 1;
        return ip[0];
    }
    panic("IP is NULL", .{});
}

fn read_constant(self: *Self) Value {
    if (self.chunk) |chunk| {
        return chunk.constants.values[self.read_byte()];
    }
    panic("CHUNK is NULL", .{});
}
