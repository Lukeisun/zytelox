const std = @import("std");
const VM = @import("vm.zig");
const Allocator = std.mem.Allocator;
const panic = std.debug.panic;
const print = std.debug.print;
const oom = @import("memory.zig").oom;
const Value = @import("value.zig").Value;
pub const Object = struct {
    const Self = @This();
    next: ?*Self,
    tag: union(Tag) {
        string: *String,
    },
    pub fn create(allocator: Allocator, vm: *VM, tag_data: anytype) *Object {
        errdefer {
            oom();
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

pub const String = struct {
    chars: []u8,
    hash: u32,
    pub fn copy_string(allocator: Allocator, vm: *VM, chars: []const u8) *Object {
        errdefer {
            oom();
        }
        const interned = vm.strings.get_string(chars, hash_string(chars));
        if (interned) |intern| {
            return get_object_by_string(vm, intern);
        }
        const heap_chars = try allocator.dupe(u8, chars);
        const object = try create(allocator, vm, heap_chars);
        return object;
    }
    pub fn take_string(allocator: Allocator, vm: *VM, chars: []u8) *Object {
        const interned = vm.strings.get_string(chars, hash_string(chars));
        if (interned) |intern| {
            allocator.free(chars);
            return get_object_by_string(vm, intern);
        }
        return create(allocator, vm, chars) catch {
            oom();
        };
    }
    fn hash_string(key: []const u8) u32 {
        var hash: u32 = 2_166_136_261;
        for (key) |k| {
            hash ^= k;
            hash *%= 16_777_619;
        }
        return hash;
    }
    pub fn create(allocator: Allocator, vm: *VM, chars: []u8) !*Object {
        const string_object = try allocator.create(String);
        const hash = hash_string(chars);
        string_object.* = .{ .chars = chars, .hash = hash };
        _ = vm.strings.put(string_object, .nil);
        return Object.create(allocator, vm, .{ .string = string_object });
    }
    pub fn destroy(self: *String, allocator: Allocator) void {
        allocator.free(self.chars);
        allocator.destroy(self);
    }
    fn get_object_by_string(vm: *VM, string: *String) *Object {
        // NOTE: Find object in intrustive LL.
        // This is really hacky but i am not sure what else to do
        // Not sure how to achieve the type punning effect with Tags
        // need figure out a way to do/emulate type punning/
        // "struct inheritance".
        // I could maybe also just store the whole Object in the hashmap
        // but does that make sense? I guess it does but it would be
        // UGLY!!! Uglier than the existing hm impl
        // Could also just include an object pointer in the string, this
        // seems to be the best option as of now.
        // We still save on a String allocation, which is a win?
        var object = vm.objects;
        while (object) |obj| {
            if (obj.tag == .string and obj.tag.string == string) {
                return obj;
            }
            const next = obj.next;
            object = next;
        }
        panic("Interned object not in object list", .{});
    }
};
