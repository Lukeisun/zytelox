const std = @import("std");
const Allocator = std.mem.Allocator;
const mem = @import("memory.zig");
const assert = std.debug.assert;
const print = std.debug.print;
const Size = @import("chunk.zig").Size;

pub const Value = union(enum) { float: f32, boolean: bool, nil };
pub fn print_value(value: Value) void {
    switch (value) {
        .float => |f| print("{d}", .{f}),
        .boolean => |b| print("{}", .{b}),
        .nil => print("nil", .{}),
    }
}
pub fn print_value_writer(value: Value, writer: std.io.AnyWriter) !void {
    switch (value) {
        .float => |f| try writer.print("{d}", .{f}),
        .boolean => |b| try writer.print("{}", .{b}),
        .nil => print("nil", .{}),
    }
}
// maybe create an interface with this and chunk ?
pub const ValueArray = struct {
    capacity: Size,
    count: Size,
    values: []Value,
    allocator: Allocator,
    const Self = @This();
    pub fn init(allocator: Allocator) Self {
        return Self{ .count = 0, .capacity = 0, .values = &[_]Value{}, .allocator = allocator };
    }
    pub fn write_value_array(self: *Self, value: Value) void {
        if (self.capacity < self.count + 1) {
            const prev_cap = self.capacity;
            self.capacity = self.next_capacity();
            self.values = self.grow(prev_cap);
        }
        self.values[self.count] = value;
        self.count += 1;
    }
    pub fn free_value_array(self: *Self) void {
        mem.free(self.allocator, self.values);
        // self.init(self.allocator);
    }
    fn next_capacity(self: *Self) Size {
        if (self.capacity < 8) {
            return 8;
        } else {
            return self.capacity * 2;
        }
    }
    // if capacity is 0 this will act as a free
    fn grow(self: *Self, prev_size: usize) []Value {
        return mem.reallocate(self.allocator, self.values, prev_size, self.capacity);
    }
};
test "init" {
    var value_array: ValueArray = undefined;
    value_array.init(std.testing.allocator);
    assert(value_array.capacity == 0 and value_array.count == 0 and value_array.values.len == 0);
}
test "grow" {
    var value_array: ValueArray = undefined;
    defer value_array.free_value_array();
    value_array.init(std.testing.allocator);
    value_array.write_value_array(.{ .float = 32 });
    assert(value_array.capacity == 8 and value_array.count == 1 and value_array.values.len == 8);
}
