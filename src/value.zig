const std = @import("std");
const Allocator = std.mem.Allocator;
const mem = @import("memory.zig");
const assert = std.debug.assert;
const print = std.debug.print;

pub const Value = f32;
pub fn print_value(value: Value) void {
    print("{d}", .{value});
}

// maybe create an interface with this and chunk ?
pub const ValueArray = struct {
    capacity: u8,
    count: u8,
    values: []Value,
    allocator: Allocator,
    const Self = @This();
    pub fn init(self: *Self, allocator: Allocator) void {
        self.* = Self{ .count = 0, .capacity = 0, .values = &[_]Value{}, .allocator = allocator };
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
        _ = mem.reallocate(self.allocator, self.values, self.capacity, 0);
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
    fn grow(self: *Self, prev_size: usize) []f32 {
        return mem.reallocate(self.allocator, self.values, prev_size, self.capacity);
    }
};
