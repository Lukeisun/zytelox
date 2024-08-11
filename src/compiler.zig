const std = @import("std");
const Lexer = @import("lexer.zig");
const Chunk = @import("chunk.zig");
const Value = @import("value.zig").Value;
const dbg = @import("main.zig").dbg;
const Op = Chunk.Op;
const TokenType = Lexer.TokenType;
const Token = Lexer.Token;
const panic = std.debug.panic;
const print = std.debug.print;

const Self = @This();
parser: Parser,
lexer: Lexer,

const parser: Parser = undefined;
var compiling_chunk: *Chunk = undefined;

pub fn compile(source: [:0]const u8, chunk: *Chunk) bool {
    compiling_chunk = chunk;
    const lexer = Lexer.init(source);
    // TODO: probably need to pass in a parser? or something
    var self = Self{ .parser = parser, .lexer = lexer };
    self.parser.had_error = false;
    self.parser.panic_mode = false;
    self.advance();
    self.expression();
    self.consume(TokenType.EOF, "Expect end of expression.");
    self.end_compiler();
    return !self.parser.had_error;
}
fn consume(self: *Self, tag: TokenType, message: []const u8) void {
    if (self.parser.current.tag == tag) {
        self.advance();
        return;
    }
    self.error_at_current(message);
}
fn advance(self: *Self) void {
    self.parser.previous = self.parser.current;
    while (true) {
        self.parser.current = self.lexer.next();
        if (self.parser.current.tag != .ERROR) break;
        self.error_at_current(self.parser.current.start[0..self.parser.current.length]);
    }
}
fn parse_precedence(self: *Self, precedence: Precedence) void {
    self.advance();
    const prefix_rule = self.get_rule(self.parser.previous.tag).prefix;
    if (prefix_rule) |rule| {
        rule(self);
    } else {
        panic("Expecting expression", .{});
    }
    while (@intFromEnum(precedence) <= @intFromEnum(self.get_rule(self.parser.current.tag).precedence)) {
        self.advance();
        const infix_rule = self.get_rule(self.parser.previous.tag).infix;
        if (infix_rule) |rule| rule(self);
    }
}
fn expression(self: *Self) void {
    self.parse_precedence(Precedence.ASSIGNMENT);
}
fn get_rule(_: *Self, tag: TokenType) ParseRule {
    return rules[@intFromEnum(tag)];
}

fn binary(self: *Self) void {
    const tag = self.parser.previous.tag;
    const rule = self.get_rule(tag);
    self.parse_precedence(@enumFromInt(@intFromEnum(rule.precedence) + 1));
    switch (tag) {
        .PLUS => self.emit_byte(@intFromEnum(Op.ADD)),
        .MINUS => self.emit_byte(@intFromEnum(Op.SUBTRACT)),
        .STAR => self.emit_byte(@intFromEnum(Op.MULTIPLY)),
        .SLASH => self.emit_byte(@intFromEnum(Op.DIVIDE)),
        else => unreachable,
    }
}
fn unary(self: *Self) void {
    self.parse_precedence(Precedence.UNARY);
    const tag = self.parser.previous.tag;
    self.expression();
    switch (tag) {
        TokenType.MINUS => self.emit_byte(@intFromEnum(Op.NEGATE)),
        else => unreachable,
    }
}
fn grouping(self: *Self) void {
    self.expression();
    self.consume(TokenType.RIGHT_PAREN, "Expect ')' after expression");
}
fn number(self: *Self) void {
    const value = std.fmt.parseFloat(f32, self.parser.previous.start[0..self.parser.previous.length]) catch |err| {
        panic("{s}", .{@errorName(err)});
    };
    self.emit_constant(.{ .float = value });
}
fn emit_constant(self: *Self, value: Value) void {
    self.current_chunk().write_constant(value, self.parser.previous.line);
}
fn end_compiler(self: *Self) void {
    self.emit_return();
    if (dbg and !self.parser.had_error) {
        self.current_chunk().disassemble_chunk("code");
    }
}
fn emit_byte(self: *Self, byte: u8) void {
    self.current_chunk().write_chunk(byte, self.parser.previous.line);
}
fn emit_bytes(self: *Self, byte1: u8, byte2: u8) void {
    self.emit_byte(byte1);
    self.emit_byte(byte2);
}
fn emit_return(self: *Self) void {
    self.emit_byte(@intFromEnum(Op.RETURN));
}
fn current_chunk(_: *Self) *Chunk {
    return compiling_chunk;
}
fn error_at_current(self: *Self, message: []const u8) void {
    self.error_at(self.parser.previous, message);
}
fn error_at(self: *Self, token: Token, message: []const u8) void {
    if (self.parser.panic_mode) return;
    self.parser.panic_mode = true;
    std.log.err("[Line {d}] Error", .{token.line});
    switch (token.tag) {
        .EOF => std.log.err(", at end", .{}),
        .ERROR => {},
        else => std.log.err(" at '{s}'", .{token.start[0..token.length]}),
    }
    std.log.err("{s}\n", .{message});
    self.parser.had_error = true;
}
const Parser = struct {
    current: Token,
    previous: Token,
    // DoD seethe cope dilate
    had_error: bool = false,
    panic_mode: bool = false,
};
const ParseRule = struct {
    const ParseFn = *const fn (*Self) void;
    prefix: ?ParseFn,
    infix: ?ParseFn,
    precedence: Precedence,
};
const rules = blk: {
    const t = TokenType;
    var r: [std.meta.fields(TokenType).len]ParseRule = undefined;
    for (std.meta.fields(TokenType)) |s| {
        r[s.value] = .{ .prefix = null, .infix = null, .precedence = Precedence.NONE };
    }
    // zig fmt: off
    r[@intFromEnum(t.LEFT_PAREN)]  = .{ .prefix = grouping, .infix = null,     .precedence = Precedence.NONE   };
    r[@intFromEnum(t.MINUS)]       = .{ .prefix = unary,    .infix = binary,   .precedence = Precedence.TERM   };
    r[@intFromEnum(t.PLUS)]        = .{ .prefix = null,     .infix = binary,   .precedence = Precedence.TERM   };
    r[@intFromEnum(t.SLASH)]       = .{ .prefix = null,     .infix = binary,   .precedence = Precedence.FACTOR };
    r[@intFromEnum(t.STAR)]        = .{ .prefix = null,     .infix = binary,   .precedence = Precedence.FACTOR };
    r[@intFromEnum(t.NUMBER)]      = .{ .prefix = number,   .infix = null,     .precedence = Precedence.NONE   };

    // zig fmt: on
    break :blk r;
};
const Precedence = enum {
    NONE,
    ASSIGNMENT,
    OR,
    AND,
    EQUALITY,
    COMPARSION,
    TERM,
    FACTOR,
    UNARY,
    CALL,
    PRIMARY,
};
pub fn compile_test(source: [:0]const u8) void {
    var lexer = Lexer.init(source);
    var line: u16 = 0;
    while (true) {
        const token = lexer.next();
        if (token.line != line) {
            print("{d:>4} ", .{token.line});
            line = token.line;
        } else {
            print("{s:>4} ", .{"|"});
        }
        // print("{d:>2} '{s:>{d}}'\n", .{ token.tag, token.start, token.length });
        print("{s:>2} '{s}'\n", .{ @tagName(token.tag), token.start[0..token.length] });
        if (token.tag == TokenType.EOF) break;
    }
}

test "remove" {
    compile_test(
        \\ fun var let  
        \\ 123 "test" 123.42
        \\ // comment
        \\ * + - /
        \\ &
    );
}
