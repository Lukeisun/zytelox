const std = @import("std");
const Allocator = std.mem.Allocator;
const mem = @import("memory.zig");
const assert = std.debug.assert;
const print = std.debug.print;

const Self = @This();
code: []u8,
count: u8,
capacity: u8,
allocator: Allocator,

pub fn init(self: *Self, allocator: Allocator) void {
    self.* = Self{ .count = 0, .capacity = 0, .code = &[_]u8{}, .allocator = allocator };
}
pub fn writeChunk(self: *Self) void {
    if (self.capacity < self.count + 1) {
        const prev_cap = self.capacity;
        self.capacity = self.next_capacity();
        self.code = self.grow(prev_cap);
    }
}
pub fn freeChunk(self: *Self) void {
    _ = mem.reallocate(self.allocator, self.code, self.capacity, 0);
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
fn grow(self: *Self, prev_size: usize) []u8 {
    if (self.capacity == 0) {
        self.allocator.free(self.code);
    }
    return mem.reallocate(self.allocator, self.code, prev_size, self.capacity);
}
pub const Op = enum {
    OP_RETURN,
};

test "init" {
    var chunk: Self = undefined;
    chunk.init(std.testing.allocator);
    assert(chunk.capacity == 0 and chunk.count == 0 and chunk.code.len == 0);
}
test "grow" {
    var chunk: Self = undefined;
    defer chunk.freeChunk();
    chunk.init(std.testing.allocator);
    chunk.writeChunk();
    assert(chunk.capacity == 8 and chunk.count == 0 and chunk.code.len == 8);
}
