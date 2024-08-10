const std = @import("std");
const builtin = @import("builtin");
const Chunk = @import("chunk.zig");
const VM = @import("vm.zig");
const Op = @import("chunk.zig").Op;
const print_value = @import("value.zig").print_value;
const print = std.debug.print;
pub const dbg = builtin.mode == std.builtin.OptimizeMode.Debug;

pub var vm: VM = undefined;

pub fn main() !void {
    var _gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = _gpa.allocator();
    var chunk: Chunk = undefined;
    chunk.init(gpa);
    defer chunk.free_chunk();
    vm.init();
    defer vm.deinit();
    const constant = chunk.add_constant(.{ .float = 1.2 });
    const c: u8 = @truncate(constant);
    chunk.write_chunk(@intFromEnum(Op.OP_CONSTANT), 369);
    chunk.write_chunk(c, 369);
    chunk.write_chunk(@intFromEnum(Op.OP_RETURN), 369);
    chunk.write_constant(.{ .float = 420 }, 369);
    // chunk.disassemble_chunk("test chunk");
    _ = vm.interpret(&chunk);
    _ = chunk.code;
    vm.push(.{ .float = 69 });
    vm.push(.{ .float = 128 });
    print_value(vm.pop());
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
