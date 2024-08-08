const std = @import("std");
const Chunk = @import("chunk.zig");
const print = std.debug.print;
pub fn main() !void {
    var chunk: Chunk = undefined;
    var _gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = _gpa.allocator();
    chunk.init(gpa);
    print("{any}\n", .{chunk.code});
    _ = chunk.code;
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
