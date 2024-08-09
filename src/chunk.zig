const std = @import("std");
const mem = @import("memory.zig");
const Value = @import("value.zig").Value;
const ValueArray = @import("value.zig").ValueArray;
const print_value = @import("value.zig").print_value;
const Allocator = std.mem.Allocator;
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

pub fn init(self: *Self, allocator: Allocator) void {
    var constants: ValueArray = undefined;
    constants.init(allocator);
    self.* = Self{
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
pub fn write_constant(self: *Self, value: Value, line: u16) void {
    self.write_chunk(@intFromEnum(Op.OP_CONSTANT_LONG), line);
    _ = self.add_constant(value);
    const constant = 16_777_216 - 1;
    const lower_bits: u8 = @truncate(constant);
    const middle_bits: u8 = @truncate(constant >> 8);
    const high_bits: u8 = @truncate(constant >> 16);
    var x: u24 = lower_bits;
    x += @as(u24, middle_bits) << 8;
    x += @as(u24, high_bits) << 16;
    print("{d}\n\t lower = {d}\n\t middle = {d}\n\t upper = {d}\n{d}\n", .{ constant, lower_bits, middle_bits, high_bits, x });
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
    self.init(self.allocator);
}
fn next_capacity(self: *Self) Size {
    if (self.capacity < 8) {
        return 8;
    } else {
        // TODO: check this?
        return self.capacity * 2;
    }
}
// if capacity is 0 this will act as a free
fn grow(self: *Self, prev_size: usize) []u8 {
    return mem.reallocate(self.allocator, self.code, prev_size, self.capacity);
}
fn grow_lines(self: *Self, prev_size: usize) []u16 {
    return mem.reallocate(self.allocator, self.lines, prev_size, self.capacity);
}
// Debug Functions
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
        .OP_RETURN => |i| return self.simple_instruction(@tagName(i), offset),
        .OP_CONSTANT => |i| return self.constant_instruction(@tagName(i), offset),
        // .OP_CONSTANT_LONG => |i| return self.constant_instruction(@tagName(i), offset),
        .OP_CONSTANT_LONG => return offset + 1,
        // else => unreachable,
    }
}
pub fn simple_instruction(_: *Self, tag_name: []const u8, offset: Size) Size {
    print("{s}\n", .{tag_name});
    return offset + 1;
}
pub fn constant_instruction(self: *Self, tag_name: []const u8, offset: Size) Size {
    const constant = self.code[offset + 1];
    print("{s: <16} {d:>4} '", .{ tag_name, constant });
    print_value(self.constants.values[constant]);
    print("'\n", .{});
    return offset + 2;
}
pub const Op = enum(u8) {
    OP_RETURN,
    OP_CONSTANT,
    OP_CONSTANT_LONG,
};

test "init" {
    var chunk: Self = undefined;
    chunk.init(std.testing.allocator);
    assert(chunk.capacity == 0 and chunk.count == 0 and chunk.code.len == 0);
    assert(chunk.lines.len == 0);
}
test "grow" {
    var chunk: Self = undefined;
    defer chunk.free_chunk();
    chunk.init(std.testing.allocator);
    chunk.write_chunk(@intFromEnum(Op.OP_CONSTANT), 0);
    assert(chunk.capacity == 8 and chunk.count == 1 and chunk.code.len == 8);
    assert(chunk.lines.len == 8);
}
