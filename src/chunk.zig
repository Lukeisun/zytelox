const std = @import("std");
const mem = @import("memory.zig");
const Value = @import("value.zig").Value;
const ValueArray = @import("value.zig").ValueArray;
const print_value = @import("value.zig").print_value;
const Allocator = std.mem.Allocator;
const panic = std.debug.panic;
const assert = std.debug.assert;
const print = std.debug.print;

pub const Size = u24;

const Self = @This();
code: []u8,
lines: []u16,
count: Size,
capacity: Size,
constants: ValueArray,
allocator: Allocator,

pub fn create(allocator: Allocator) Self {
    const constants = ValueArray.init(allocator);
    return Self{
        .count = 0,
        .capacity = 0,
        .code = &[_]u8{},
        .lines = &[_]u16{},
        .constants = constants,
        .allocator = allocator,
    };
}
pub fn write_chunk(self: *Self, byte: u8, line: u16) void {
    if (self.capacity < self.count + 1) {
        const prev_cap = self.capacity;
        self.capacity = self.next_capacity();
        self.code = self.grow(prev_cap);
        self.lines = self.grow_lines(prev_cap);
    }
    self.code[self.count] = byte;
    self.lines[self.count] = line;
    self.count += 1;
}
// Challenge 2 Part 14
pub fn write_constant(self: *Self, value: Value, line: u16) Size {
    const count = self.constants.count;
    if (count > std.math.maxInt(Size)) panic("Too many constants in one chunk", .{});
    const op = if (count > std.math.maxInt(u8)) Op.CONSTANT_LONG else Op.CONSTANT;
    self.write_chunk(@intFromEnum(op), line);
    const constant = self.add_constant(value);
    switch (op) {
        .CONSTANT => {
            self.write_chunk(@truncate(constant), line);
        },
        .CONSTANT_LONG => {
            const bits = [_]u8{ @truncate(constant), @truncate(constant >> 8), @truncate(constant >> 16) };
            for (bits) |bit| {
                self.write_chunk(bit, line);
            }
        },
        else => unreachable,
    }
    return constant;
}
pub fn add_constant(self: *Self, value: Value) Size {
    self.constants.write_value_array(value);
    return self.constants.count - 1;
}
pub fn free_chunk(self: *Self) void {
    mem.free(self.allocator, self.code);
    mem.free(self.allocator, self.lines);
    self.constants.free_value_array();
    // TODO: maybe just zero it out manually
    // self.create(self.allocator);
}
fn next_capacity(self: *Self) Size {
    if (self.capacity < 8) {
        return 8;
    } else {
        const res = @mulWithOverflow(self.capacity, 2);
        if (res[1] == 1) return std.math.maxInt(Size) else return res[0];
    }
}
// TODO: fun little exercise but honestly, just switch to regular allocator functions
// if capacity is 0 this will act as a free
fn grow(self: *Self, prev_size: usize) []u8 {
    return mem.reallocate(self.allocator, self.code, prev_size, self.capacity);
}
fn grow_lines(self: *Self, prev_size: usize) []u16 {
    return mem.reallocate(self.allocator, self.lines, prev_size, self.capacity);
}
// --------------- Debug Functions ---------------
pub fn disassemble_chunk(self: *Self, name: []const u8) void {
    const width = name.len + 4;
    print("{s:=^[1]}\n", .{ name, width });
    var offset: Size = 0;
    while (offset < self.count) {
        offset = self.disassemble_instruction(offset);
    }
}
pub fn disassemble_instruction(self: *Self, offset: Size) Size {
    print("{d:0>4} ", .{offset});
    if (offset > 0 and self.lines[offset] == self.lines[offset - 1]) {
        print("\t| ", .{});
    } else {
        print("{d:0>4} ", .{self.lines[offset]});
    }
    const instruction: Op = @enumFromInt(self.code[offset]);
    switch (instruction) {
        .CONSTANT, .DEFINE_GLOBAL, .GET_GLOBAL, .SET_GLOBAL => |i| return self.constant_instruction(@tagName(i), offset),
        .CONSTANT_LONG => |i| return self.constant_long_instruction(@tagName(i), offset),
        .GET_LOCAL, .SET_LOCAL => |i| return self.byte_instruction(@tagName(i), offset),
        .JUMP_IF_FALSE, .JUMP => |i| return self.jump_instruction(@tagName(i), 1, offset),
        .LOOP => |i| return self.jump_instruction(@tagName(i), -1, offset),
        else => |i| return self.simple_instruction(@tagName(i), offset),
    }
}
pub fn simple_instruction(_: *Self, tag_name: []const u8, offset: Size) Size {
    print("{s}\n", .{tag_name});
    return offset + 1;
}
pub fn byte_instruction(self: *Self, tag_name: []const u8, offset: Size) Size {
    const slot = self.code[offset + 1];
    print("{s: <16} {d:>4}", .{ tag_name, slot });
    return offset + 2;
}
pub fn constant_instruction(self: *Self, tag_name: []const u8, offset: Size) Size {
    const constant = self.code[offset + 1];
    print("{s: <16} {d:>4} '", .{ tag_name, constant });
    print_value(self.constants.values[constant]);
    print("'\n", .{});
    return offset + 2;
}
pub fn constant_long_instruction(self: *Self, tag_name: []const u8, offset: Size) Size {
    const constant: u24 =
        self.code[offset + 1] +
        (@as(u24, self.code[offset + 2]) << 8) +
        (@as(u24, self.code[offset + 3]) << 16);
    print("{s: <16} {d:>4}", .{ tag_name, constant });
    print("\n", .{});
    return offset + 4;
}
pub fn jump_instruction(self: *Self, tag_name: []const u8, sign: i2, offset: Size) Size {
    const jump = @as(u16, self.code[offset + 1]) << 8 | self.code[offset + 2];
    // const ip_end: i32 = @intCast(@as(i32, (offset + 3 + sign * jump)));
    const ip_end: i32 = @as(i32, offset) + 3 + sign * @as(i32, jump);
    print("{s: <16} {d:>4} -> {d:>4}", .{
        tag_name,
        offset,
        ip_end,
    });
    print("\n", .{});
    return offset + 4;
}
pub const Op = enum(u8) {
    RETURN,
    CONSTANT,
    CONSTANT_LONG,
    NEGATE,
    ADD,
    SUBTRACT,
    MULTIPLY,
    DIVIDE,
    NIL,
    TRUE,
    FALSE,
    NOT,
    EQUAL,
    GREATER,
    LESS,
    PRINT,
    POP,
    DEFINE_GLOBAL,
    GET_GLOBAL,
    SET_GLOBAL,
    GET_LOCAL,
    SET_LOCAL,
    JUMP_IF_FALSE,
    JUMP,
    LOOP,
};

test "init" {
    var chunk = Self.create(std.testing.allocator);
    defer chunk.free_chunk();
    assert(chunk.capacity == 0 and chunk.count == 0 and chunk.code.len == 0);
    assert(chunk.lines.len == 0);
}
test "grow" {
    var chunk = Self.create(std.testing.allocator);
    defer chunk.free_chunk();
    chunk.write_chunk(@intFromEnum(Op.CONSTANT), 0);
    assert(chunk.capacity == 8 and chunk.count == 1 and chunk.code.len == 8);
    assert(chunk.lines.len == 8);
}
// hmm this is kinda scuffed now since i made it so it will switch
// once we go past u8
// reevaluate this test
test "max constants" {
    var chunk = Self.create(std.testing.allocator);
    defer chunk.free_chunk();
    var i: Size = 0;
    while (i < 16777215 / 4) : (i += 1) {
        _ = chunk.write_constant(.{ .float = 69 }, 0);
    }
    const max = std.math.maxInt(Size);
    assert(chunk.capacity == max);
}
