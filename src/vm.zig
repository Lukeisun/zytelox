const std = @import("std");
const Chunk = @import("chunk.zig");
const Op = Chunk.Op;
const Value = @import("value.zig").Value;
const Size = @import("chunk.zig").Size;
const Allocator = std.mem.Allocator;
const Table = @import("table.zig");
const dbg = @import("main.zig").dbg;
const _o = @import("object.zig");
const Object = _o.Object;
const String = _o.String;
const compile = @import("compiler.zig").compile;
const print_value_writer = @import("value.zig").print_value_writer;
const print_value = @import("value.zig").print_value;
const print = std.debug.print;
const assert = std.debug.assert;
const panic = std.debug.panic;

const Self = @This();
const STACK_MAX = 256;
chunk: *Chunk,
ip: [*]u8,
stack: [STACK_MAX]Value,
stack_top: [*]Value,
writer: std.io.AnyWriter,
objects: ?*Object,
strings: *Table,
globals: *Table,
allocator: Allocator,
pub const Result = error{
    INTERPRET_COMPILE_ERROR,
    INTERPRET_RUNTIME_ERROR,
};

pub fn init(allocator: Allocator, writer: std.io.AnyWriter) *Self {
    const vm_ptr = allocator.create(Self) catch {
        panic("OOM", .{});
    };
    vm_ptr.* = Self{
        .chunk = undefined,
        .writer = writer,
        .ip = &[_]u8{},
        .stack = undefined,
        .stack_top = undefined,
        .allocator = allocator,
        .objects = null,
        .strings = Table.init(allocator),
        .globals = Table.init(allocator),
    };
    vm_ptr.reset_stack();
    return vm_ptr;
}
pub fn deinit(self: *Self) void {
    self.free_objects();
    self.globals.deinit();
    self.strings.deinit();
    self.allocator.destroy(self);
}
fn free_objects(self: *Self) void {
    var object = self.objects;
    while (object) |o| {
        const next = o.next;
        o.destroy(self.allocator);
        object = next;
    }
}
fn reset_stack(self: *Self) void {
    self.stack = .{.undefined} ** STACK_MAX;
    self.stack_top = self.stack[0..];
}
pub fn push(self: *Self, value: Value) void {
    self.stack_top[0] = value;
    self.stack_top += 1;
}
pub fn pop(self: *Self) Value {
    // TODO: probably remove this? tbh it really only effects debug so maybe only in debug
    self.stack_top[0] = .undefined;
    self.stack_top -= 1;
    return self.stack_top[0];
}
fn peek(self: *Self, dist: u8) Value {
    return (self.stack_top - (1 + dist))[0];
}

pub fn interpret(self: *Self, allocator: Allocator, source: [:0]const u8) !void {
    var chunk = Chunk.create(allocator);
    defer chunk.free_chunk();
    if (!compile(allocator, self, source, &chunk)) {
        return Result.INTERPRET_COMPILE_ERROR;
    }
    self.chunk = &chunk;
    self.ip = self.chunk.code.ptr;
    return self.run();
}

pub fn run(self: *Self) !void {
    while (true) {
        const instruction: Op = @enumFromInt(self.read_byte());
        switch (instruction) {
            .RETURN => {
                _ = self.pop();
                return;
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
                var constant: [*]Value = (self.stack_top - 1);
                if (constant[0] != .float) {
                    self.runtime_error("Operand must be a number");
                    return Result.INTERPRET_RUNTIME_ERROR;
                }
                constant[0].float *= -1;
            },
            .PRINT => {
                const value = self.pop();
                try print_value_writer(value, self.writer);
                try self.writer.print("\n", .{});
            },
            .POP => _ = self.pop(),
            .DEFINE_GLOBAL => {
                const constant = self.read_constant();
                assert(constant.object.tag == .string);
                _ = self.globals.put(constant.object.tag.string, self.peek(0));
                _ = self.pop();
            },
            .GET_GLOBAL => {
                const constant = self.read_constant();
                assert(constant.object.tag == .string);
                const global = self.globals.get(constant.object.tag.string);
                if (global) |_| {} else {
                    var buf: [128]u8 = undefined;
                    const written = std.fmt.bufPrint(&buf, "Undefined Variable: {s}", .{constant.object.tag.string.chars}) catch unreachable;
                    self.runtime_error(written);
                    return Result.INTERPRET_RUNTIME_ERROR;
                }
                self.push(global.?);
            },
            .SET_GLOBAL => {
                const constant = self.read_constant();
                assert(constant.object.tag == .string);
                if (self.globals.put(constant.object.tag.string, self.peek(0))) {
                    _ = self.globals.remove(constant.object.tag.string);
                    var buf: [128]u8 = undefined;
                    const written = std.fmt.bufPrint(&buf, "Undefined Variable: {s}", .{constant.object.tag.string.chars}) catch unreachable;
                    self.runtime_error(written);
                    return Result.INTERPRET_RUNTIME_ERROR;
                }
            },
            .GET_LOCAL => {
                const slot = self.read_byte();
                self.push(self.stack[slot]);
            },
            .SET_LOCAL => {
                const slot = self.read_byte();
                self.stack[slot] = self.peek(0);
            },
            .JUMP_IF_FALSE => {
                const offset = self.read_short();
                if (self.falsey(self.peek(0))) self.ip += offset;
            },
            .JUMP => {
                const offset = self.read_short();
                self.ip += offset;
            },
            .LOOP => {
                const offset = self.read_short();
                self.ip -= offset;
            },
            .NIL => self.push(.{ .nil = {} }),
            .FALSE => self.push(.{ .boolean = false }),
            .TRUE => self.push(.{ .boolean = true }),
            .NOT => self.push(.{ .boolean = self.falsey(self.pop()) }),
            .ADD => |op| {
                const b = self.peek(0);
                const a = self.peek(1);
                if (@intFromEnum(a) != @intFromEnum(b)) {
                    self.runtime_error("Values must have same active tag");
                    return Result.INTERPRET_RUNTIME_ERROR;
                }
                switch (a) {
                    .float => {
                        try self.binary_op(op);
                    },
                    .object => {
                        if (a.object.tag != .string or b.object.tag != .string) {
                            self.runtime_error("Value objects must be strings");
                            return Result.INTERPRET_RUNTIME_ERROR;
                        }
                        self.concat();
                    },
                    else => {
                        self.runtime_error("Values must either be numbers or strings");
                        return Result.INTERPRET_RUNTIME_ERROR;
                    },
                }
            },
            .SUBTRACT, .MULTIPLY, .DIVIDE, .GREATER, .LESS => |op| try self.binary_op(op),
            .EQUAL => {
                const b = self.pop();
                const a = self.pop();
                self.push(.{ .boolean = a.equals(b) });
            },

            // else => unreachable,
        }
        if (dbg) {
            //
            print("DEBUG\n", .{});
            for (self.stack) |value| {
                if (value == .undefined) continue;
                print("[ ", .{});
                print_value(value);
                print(" ]", .{});
            }
            print("\n", .{});
            const offset: u24 = @intCast(self.ip - self.chunk.code.ptr);
            _ = self.chunk.disassemble_instruction(offset);
        }
    }
}

fn concat(self: *Self) void {
    const b = self.pop();
    const a = self.pop();
    const chars = std.mem.concat(self.allocator, u8, &[_][]u8{ a.object.tag.string.chars, b.object.tag.string.chars }) catch {
        panic("OOM", .{});
    };
    const object = String.take_string(self.allocator, self, chars);
    self.push(.{ .object = object });
}
fn falsey(_: *Self, value: Value) bool {
    return value == .nil or (value == .boolean and !value.boolean);
}

fn read_byte(self: *Self) u8 {
    defer self.ip += 1;
    return self.ip[0];
}

fn read_constant(self: *Self) Value {
    return self.chunk.constants.values[self.read_byte()];
}
fn read_constant_long(self: *Self) Value {
    const idx: u24 =
        self.read_byte() +
        (@as(u24, self.read_byte()) << 8) +
        (@as(u24, self.read_byte()) << 16);
    return self.chunk.constants.values[idx];
}
fn read_short(self: *Self) u16 {
    const val = (@as(u16, self.read_byte()) << 8) | self.read_byte();
    return val;
}
fn binary_op(self: *Self, op: Op) !void {
    const b = self.pop();
    const a = self.pop();
    if (b != .float or a != .float) {
        self.runtime_error("Operands must be numbers");
        return Result.INTERPRET_RUNTIME_ERROR;
    }
    switch (op) {
        Op.ADD => self.push(.{ .float = a.float + b.float }),
        Op.SUBTRACT => self.push(.{ .float = a.float - b.float }),
        Op.MULTIPLY => self.push(.{ .float = a.float * b.float }),
        Op.DIVIDE => self.push(.{ .float = a.float / b.float }),
        Op.GREATER => self.push(.{ .boolean = a.float > b.float }),
        Op.LESS => self.push(.{ .boolean = a.float < b.float }),
        else => unreachable,
    }
    return;
}
fn runtime_error(self: *Self, message: []const u8) void {
    const line = self.chunk.lines[self.ip - self.chunk.code.ptr - 1];
    std.log.err("[line {d}] in script\n\t{s}", .{ line, message });
    self.reset_stack();
}
