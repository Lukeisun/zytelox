const std = @import("std");
const builtin = @import("builtin");
const Chunk = @import("chunk.zig");
const VM = @import("vm.zig");
const Op = @import("chunk.zig").Op;
const Result = VM.Result;
const print_value = @import("value.zig").print_value;
const print = std.debug.print;
pub const dbg = (builtin.mode == std.builtin.OptimizeMode.Debug);

pub fn runFile(allocator: std.mem.Allocator, filename: [:0]const u8, vm: *VM) !void {
    const file = std.fs.cwd().openFile(filename, .{ .mode = .read_only }) catch |err| {
        std.log.err("Error: {s}", .{@errorName(err)});
        std.process.exit(74);
    };
    const stat = try file.stat();
    defer file.close();
    // const source = try file.readToEndAlloc(allocator, stat.size);
    const source = try file.readToEndAllocOptions(allocator, stat.size, null, @alignOf(u8), 0);
    std.debug.assert(source.len != 0);
    vm.interpret(allocator, source) catch |err| {
        switch (err) {
            Result.INTERPRET_COMPILE_ERROR => std.process.exit(65),
            Result.INTERPRET_RUNTIME_ERROR => std.process.exit(70),
            else => unreachable,
        }
    };
}
pub fn repl(allocator: std.mem.Allocator, vm: *VM) !void {
    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();
    try stdout.writeAll("> ");
    while (try stdin.readUntilDelimiterOrEofAlloc(allocator, '\n', 1024)) |s| {
        const x = try allocator.dupeZ(u8, s);
        _ = try vm.interpret(allocator, x);
    }
    print("\n", .{});
}

pub fn main() !void {
    var _gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = _gpa.allocator();
    var args = try std.process.argsWithAllocator(gpa);
    defer args.deinit();
    var collected_args = std.ArrayList([:0]const u8).init(gpa);
    _ = args.skip();
    var vm = VM.init(gpa, std.io.getStdOut().writer().any());
    defer vm.deinit();
    while (args.next()) |arg| {
        try collected_args.append(arg);
    }
    switch (collected_args.items.len) {
        1 => {
            try runFile(gpa, collected_args.items[0], vm);
        },
        0 => {
            try repl(gpa, vm);
        },
        else => {
            const stderr = std.io.getStdErr().writer();
            try stderr.writeAll("Usage: zlox [script]\n");
        },
    }
}
// Chapter 15 Challenge 4.
// In ReleaseSafe without POP PUSH - 11 ms
//                with    POP PUSH - 12 ms
// In debug though without POP PUSH its about twice as fast
// I tried doing ReleaseFast, but the program segfaults.
// Probably cause doing weird things memory.zig
pub fn negate_time_test(allo: std.mem.Allocator) void {
    var chunk: Chunk = undefined;
    chunk.init(allo);
    defer chunk.free_chunk();
    const stdout = std.io.getStdOut();
    const vm = VM.init(stdout.writer().any());
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
