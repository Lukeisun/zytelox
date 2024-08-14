const std = @import("std");
const Allocator = std.mem.Allocator;
const panic = std.debug.panic;
const Value = @import("value.zig").Value;
pub const Object = struct {
    const Self = @This();
    tag: Tag,

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
    pub fn create(allocator: Allocator, tag: Tag) *Object {
        errdefer {
            panic("OOM", .{});
        }
        const object = try allocator.create(Object);
        object.* = .{ .tag = tag };
        return object;
    }
    pub fn to_string(self: Self) []const u8 {
        switch (self.tag) {
            Tag.String => {},
        }
    }

    const Tag = enum {
        String,
    };
};
pub const String = struct {
    obj: Object,
    chars: []u8,
    pub fn copy_string(allocator: Allocator, chars: []const u8) *String {
        errdefer {
            panic("OOM", .{});
        }
        const str = try allocator.dupe(u8, chars);
        const string_object = try create(allocator, str);
        return string_object;
    }
    pub fn create(allocator: Allocator, str: []const u8) !*String {
        const object = Object.create(allocator, .String);
        const data = String{ .chars = copy_chars };
        return Object.create(allocator, .{ .tag = data });
    }
};
