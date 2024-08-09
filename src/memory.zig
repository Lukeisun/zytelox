const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
pub const Error = error{OutOfMemory};
// ret type stolen from std lib :D
pub fn reallocate(allocator: Allocator, ptr: anytype, _: usize, new_size: usize) t: {
    const Slice = @typeInfo(@TypeOf(ptr)).Pointer;
    break :t []align(Slice.alignment) Slice.child;
} {
    assert(@typeInfo(@TypeOf(ptr)) == .Pointer);
    const res = allocator.realloc(ptr, new_size) catch {
        oom();
    };
    return res;
}

pub fn free(allocator: Allocator, ptr: anytype) void {
    _ = reallocate(allocator, ptr, 0, 0);
}
pub fn oom() noreturn {
    std.debug.panic("OOM\n", .{});
}
