const std = @import("std");
const Allocator = std.mem.Allocator;
const panic = std.debug.panic;
const Value = @import("value.zig").Value;
pub const Object = struct {
    const Self = @This();
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
    pub fn create(allocator: Allocator, tag_data: anytype) *Object {
        errdefer {
            panic("OOM", .{});
        }
        const object = try allocator.create(Object);
        object.tag = tag_data;
        return object;
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
pub const String = struct {
    chars: []u8,
    pub fn copy_string(allocator: Allocator, chars: []const u8) *Object {
        errdefer {
            panic("OOM", .{});
        }
        const heap_chars = try allocator.dupe(u8, chars);
        const object = try create(allocator, heap_chars);
        return object;
    }
    pub fn create(allocator: Allocator, chars: []u8) !*Object {
        const string_object = try allocator.create(String);
        string_object.* = .{ .chars = chars };
        return Object.create(allocator, .{ .string = string_object });
    }
};
