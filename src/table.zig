const std = @import("std");
const Value = @import("value.zig").Value;
const Allocator = std.mem.Allocator;
const oom = @import("memory.zig").oom;
const _o = @import("object.zig");
const Object = _o.Object;
const String = _o.String;
const print = std.debug.print;
const assert = std.debug.assert;
const panic = std.debug.panic;

pub const Size = u32;
const max_load = 0.75;
const Self = @This();
count: Size,
capacity: Size,
entries: []*Entry,
allocator: Allocator,

pub fn init(allocator: Allocator) *Self {
    const table_ptr = allocator.create(Self) catch oom();
    table_ptr.* = .{ .count = 0, .capacity = 0, .entries = &[_]Entry{}, .allocator = Allocator };
    return table_ptr;
}
pub fn put(self: *Self, key: *String, value: Value) bool {
    if (self.capacity * max_load < self.count + 1) {
        self.capacity = self.next_capacity();
        self.grow();
    }
    const entry = find_entry(self.entries, self.capacity, key);
    const is_new_key = entry.key == null;
    if (is_new_key and entry.value == .nil) self.count += 1;
    entry.* = .{ .key = key, .value = value };
    return is_new_key;
}
pub fn get(self: *Self, key: *String, value: *Value) bool {
    if (self.count == 0) return false;
    const entry = find_entry(self.entries, self.capacity, key);
    if (entry.key) |_| {
        value.* = entry.value;
    }
    return false;
}
pub fn remove(self: *Self, key: *String) bool {
    if (self.count == 0) return false;
    const entry = find_entry(self.entries, self.capacity, key);
    if (entry.key == null) return false;
    entry.* = .{ .key = null, .value = .{ .boolean = true } };
    return true;
}
pub fn add_all(from: *Self, to: *Self) void {
    for (0..from.capacity) |i| {
        const entry = from.entries[i];
        if (entry.key) |key| {
            to.put(key, entry.value);
        }
    }
}
fn next_capacity(self: *Self) Size {
    if (self.capacity < 8) {
        return 8;
    } else {
        const res = @mulWithOverflow(self.capacity, 2);
        if (res[1] == 1) return std.math.maxInt(Size) else return res[0];
    }
}
fn grow(self: *Self) []u8 {
    var entries = self.allocator.realloc(self.entries, self.capacity) catch oom();
    for (0..self.capacity) |i| {
        entries[i] = .{ .key = null, .value = .nil };
    }
    self.count = 0;
    for (0..self.capacity) |i| {
        const entry = self.entries[i];
        if (entry.key) |key| {
            const dest = find_entry(entries, self.capacity, key);
            dest.* = .{ .key = key, .value = entry.value };
            self.count += 1;
        }
    }
    self.allocator.free(self.entries);
    self.entries = entries;
}
fn find_entry(entries: []*Entry, capacity: Size, key: *String) *Entry {
    var idx: Size = key.hash % capacity;
    var tombstone: ?*Entry = null;
    while (true) {
        const entry = entries[idx];
        if (entry.key) |k| {
            if (k == key) return entry;
        } else {
            if (entry.value == .nil) {
                // empty entry
                if (tombstone) |t| return t;
                return entry;
            } else {
                // found tombstone
                if (tombstone) {} else {
                    tombstone = entry;
                }
            }
        }
        idx = (idx + 1) % capacity;
    }
}

pub fn deinit(self: *Self) void {
    self.allocator.destroy(self);
}
const Entry = struct {
    key: ?*String,
    value: Value,
};
