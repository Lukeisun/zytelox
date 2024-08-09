const std = @import("std");
const Chunk = @import("chunk.zig");
const Op = @import("chunk.zig").Op;
const print = std.debug.print;
pub fn main() !void {
    var chunk: Chunk = undefined;
    var _gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = _gpa.allocator();
    chunk.init(gpa);
    const constant = chunk.add_constant(1.2);
    const c: u8 = @truncate(constant);
    chunk.write_chunk(@intFromEnum(Op.OP_CONSTANT), 369);
    chunk.write_chunk(c, 369);
    chunk.write_chunk(@intFromEnum(Op.OP_RETURN), 369);
    chunk.write_constant(420, 369);
    chunk.disassemble_chunk("test chunk");
    _ = chunk.code;
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
