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
    // Dont need to do this
    // per std "If new_n is 0, same as free"
    // if (new_size == 0) {
    //     allocator.free(ptr);
    //     return ptr;
    // }
    const res = allocator.realloc(ptr, new_size) catch {
        oom();
    };
    return res;
}
pub fn oom() noreturn {
    std.debug.panic("OOM\n", .{});
}
