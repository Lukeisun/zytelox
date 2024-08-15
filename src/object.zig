const std = @import("std");
const VM = @import("vm.zig");
const Allocator = std.mem.Allocator;
const panic = std.debug.panic;
const Value = @import("value.zig").Value;
pub const Object = struct {
    const Self = @This();
    next: ?*Self,
    tag: union(Tag) {
        string: *String,
    },
    // maybe wont need this
    pub fn is_string(value: Value) bool {
        return is_type(value, Tag.String);
    }
    fn is_type(value: Value, tag: Tag) bool {
        return switch (value) {
            .object => |o| o.tag == tag,
            else => false,
        };
    }
    pub fn create(allocator: Allocator, vm: *VM, tag_data: anytype) *Object {
        errdefer {
            panic("OOM", .{});
        }
        const object = try allocator.create(Object);
        object.tag = tag_data;
        object.next = vm.objects;
        vm.objects = object;
        return object;
    }
    pub fn destroy(self: *Self, allocator: Allocator) void {
        switch (self.tag) {
            inline else => |o| o.destroy(allocator),
        }
        allocator.destroy(self);
    }
    pub fn to_string(self: Self) []const u8 {
        switch (self.tag) {
            .string => |s| return s.chars,
        }
    }

    const Tag = enum {
        string,
    };
};
// Might need to have pointer back to object but I'm not sure
pub const String = struct {
    chars: []u8,
    hash: u32,
    pub fn copy_string(allocator: Allocator, vm: *VM, chars: []const u8) *Object {
        errdefer {
            panic("OOM", .{});
        }
        const heap_chars = try allocator.dupe(u8, chars);
        const object = try create(allocator, vm, heap_chars);
        return object;
    }
    pub fn take_string(allocator: Allocator, vm: *VM, chars: []u8) *Object {
        return create(allocator, vm, chars) catch {
            panic("OOM", .{});
        };
    }
    pub fn create(allocator: Allocator, vm: *VM, chars: []u8) !*Object {
        const string_object = try allocator.create(String);
        string_object.* = .{ .chars = chars, .hash = hash_string(chars) };
        return Object.create(allocator, vm, .{ .string = string_object });
    }
    fn hash_string(key: []const u8) u32 {
        std.HashMap
        var hash: u32 = 2166136261;
        for (key) |k| {
            hash ^= k;
            hash *= 16777619;
        }
        return hash;
    }
    pub fn destroy(self: *String, allocator: Allocator) void {
        allocator.free(self.chars);
        allocator.destroy(self);
    }
};
