const std = @import("std");
const builtin = @import("builtin");
const Chunk = @import("chunk.zig");
const VM = @import("vm.zig");
const Op = @import("chunk.zig").Op;
const print_value = @import("value.zig").print_value;
const print = std.debug.print;
pub const dbg = (builtin.mode == std.builtin.OptimizeMode.Debug);

pub var vm: VM = undefined;
const stdout = std.io.getStdOut();

pub fn main() !void {
    var _gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = _gpa.allocator();
    var chunk: Chunk = undefined;
    chunk.init(gpa);
    defer chunk.free_chunk();
    vm.init(stdout.writer().any());
    defer vm.deinit();
    const constant = chunk.add_constant(.{ .float = 1.2 });
    // [ OP idx idx +1 ... OP ... ]
    const c: u8 = @truncate(constant);
    chunk.write_chunk(@intFromEnum(Op.CONSTANT), 369);
    chunk.write_chunk(c, 369);
    chunk.write_constant(.{ .float = 420 }, 369);
    chunk.write_chunk(@intFromEnum(Op.NEGATE), 369);
    chunk.write_chunk(@intFromEnum(Op.ADD), 369);
    chunk.write_chunk(@intFromEnum(Op.RETURN), 369);
    // chunk.disassemble_chunk("test chunk");
    _ = vm.interpret(&chunk) catch |err| {
        std.debug.panic("{s}\n", .{@errorName(err)});
    };
    // print("RES: {s}", .{x.items});
    _ = chunk.code;
    negate_time_test(gpa);
}
// Chapter 15 Challenge 4.
// In ReleaseSafe without POP PUSH - 11 ms
//                with    POP PUSH - 12 ms
// In debug though without POP PUSH its about twice as fast
pub fn negate_time_test(allo: std.mem.Allocator) void {
    var chunk: Chunk = undefined;
    chunk.init(allo);
    defer chunk.free_chunk();
    vm.init(stdout.writer().any());
    defer vm.deinit();
    chunk.write_constant(.{ .float = 169 }, 69);
    var i: Chunk.Size = undefined;
    while (i < std.math.maxInt(Chunk.Size)) : (i += 1) {
        chunk.write_chunk(@intFromEnum(Op.NEGATE), 69);
    }
    var timer = std.time.Timer.start() catch unreachable;
    _ = vm.interpret(&chunk) catch |err| {
        std.debug.panic("{s}\n", .{@errorName(err)});
    };
    print("TIME {d}\n", .{timer.read() / std.time.ns_per_ms});
}
