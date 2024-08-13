const std = @import("std");
const Chunk = @import("chunk.zig");
const Op = Chunk.Op;
const Value = @import("value.zig").Value;
const Size = @import("chunk.zig").Size;
const Allocator = std.mem.Allocator;
const dbg = @import("main.zig").dbg;
const compile = @import("compiler.zig").compile;
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
allocator: Allocator,
const Result = enum {
    INTERPRET_OK,
    INTERPRET_COMPILE_ERROR,
    INTERPRET_RUNTIME_ERROR,
};

pub fn init(allocator: Allocator, writer: std.io.AnyWriter) *Self {
    const vm_ptr = allocator.create(Self) catch {
        panic("OOM", .{});
    };
    vm_ptr.* = Self{
        .chunk = null,
        .writer = writer,
        .ip = &[_]u8{},
        .stack = undefined,
        .stack_top = undefined,
        .allocator = allocator,
    };
    vm_ptr.reset_stack();
    return vm_ptr;
}
pub fn deinit(self: *Self) void {
    self.allocator.destroy(self);
    // print("{any}", .{self});

}
fn reset_stack(self: *Self) void {
    self.stack = .{.nil} ** STACK_MAX;
    self.stack_top = self.stack[0..];
}
pub fn push(self: *Self, value: Value) void {
    self.stack_top[0] = value;
    self.stack_top += 1;
}
pub fn pop(self: *Self) Value {
    // TODO: probably remove this? tbh it really only effects debug so maybe only in debug
    self.stack_top[0] = .nil;
    self.stack_top -= 1;
    return self.stack_top[0];
}

pub fn interpret(self: *Self, allocator: Allocator, source: [:0]const u8) !Result {
    var chunk = Chunk.create(allocator);
    defer chunk.free_chunk();
    if (!compile(source, &chunk)) {
        return Result.INTERPRET_COMPILE_ERROR;
    }
    self.chunk = &chunk;
    self.ip = self.chunk.?.code.ptr;
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
                const value = self.pop();
                try print_value_writer(value, self.writer);
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
                // no pop push
                var constant: [*]Value = (self.stack_top - 1);
                if (constant[0] != .float) {
                    self.runtime_error("Operand must be a number");
                    return Result.INTERPRET_RUNTIME_ERROR;
                }
                constant[0].float *= -1;
                // pop push
                // const constant = self.pop();
                // switch (constant) {
                //     .float => |f| self.push(Value{ .float = -f }),
                //     else => unreachable,
                // }
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
fn runtime_error(self: *Self, message: []const u8) void {
    const line = self.chunk.?.lines[self.ip - self.chunk.?.code.ptr - 1];
    std.log.err("[line {d}] in script\n\t{s}", .{ line, message });
    self.reset_stack();
}
