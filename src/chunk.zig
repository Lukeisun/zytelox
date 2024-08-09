const std = @import("std");
const mem = @import("memory.zig");
const Value = @import("value.zig").Value;
const ValueArray = @import("value.zig").ValueArray;
const print_value = @import("value.zig").print_value;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const print = std.debug.print;

const Self = @This();
code: []u8,
count: u8,
capacity: u8,
constants: ValueArray,
allocator: Allocator,

pub fn init(self: *Self, allocator: Allocator) void {
    var constants: ValueArray = undefined;
    constants.init(allocator);
    self.* = Self{
        .count = 0,
        .capacity = 0,
        .code = &[_]u8{},
        .constants = constants,
        .allocator = allocator,
    };
}
pub fn write_chunk(self: *Self, byte: u8) void {
    if (self.capacity < self.count + 1) {
        const prev_cap = self.capacity;
        self.capacity = self.next_capacity();
        self.code = self.grow(prev_cap);
    }
    self.code[self.count] = byte;
    self.count += 1;
}
pub fn add_constant(self: *Self, value: Value) u8 {
    self.constants.write_value_array(value);
    return self.constants.count - 1;
}
pub fn free_chunk(self: *Self) void {
    _ = mem.reallocate(self.allocator, self.code, self.capacity, 0);
    self.constants.free_value_array();
    // TODO: maybe just zero it out manually
    self.init(self.allocator);
}
fn next_capacity(self: *Self) u8 {
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
// Debug Functions
pub fn disassemble_chunk(self: *Self, name: []const u8) void {
    const width = name.len + 4;
    print("{s:=^[1]}\n", .{ name, width });
    var offset: u8 = 0;
    while (offset < self.count) {
        offset = self.disassemble_instruction(offset);
    }
}
pub fn disassemble_instruction(self: *Self, offset: u8) u8 {
    print("{d:0>4} ", .{offset});
    const instruction: Op = @enumFromInt(self.code[offset]);
    switch (instruction) {
        .OP_RETURN => |i| return self.simple_instruction(@tagName(i), offset),
        .OP_CONSTANT => |i| return self.constant_instruction(@tagName(i), offset),
        // else => unreachable,
    }
}
pub fn simple_instruction(_: *Self, tag_name: []const u8, offset: u8) u8 {
    print("{s}\n", .{tag_name});
    return offset + 1;
}
pub fn constant_instruction(self: *Self, tag_name: []const u8, offset: u8) u8 {
    const constant = self.code[offset + 1];
    print("{s} {d:0>4} '", .{ tag_name, constant });
    print_value(self.constants.values[constant]);
    print("'\n", .{});
    return offset + 2;
}
pub const Op = enum(u8) {
    OP_RETURN,
    OP_CONSTANT,
};

test "init" {
    var chunk: Self = undefined;
    chunk.init(std.testing.allocator);
    assert(chunk.capacity == 0 and chunk.count == 0 and chunk.code.len == 0);
}
test "grow" {
    var chunk: Self = undefined;
    defer chunk.free_chunk();
    chunk.init(std.testing.allocator);
    chunk.write_chunk();
    assert(chunk.capacity == 8 and chunk.count == 0 and chunk.code.len == 8);
}
