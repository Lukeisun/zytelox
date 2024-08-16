const std = @import("std");
const Lexer = @import("lexer.zig");
const Chunk = @import("chunk.zig");
const VM = @import("vm.zig");
const Value = @import("value.zig").Value;
const dbg = @import("main.zig").dbg;
const _o = @import("object.zig");
const Size = Chunk.Size;
const Object = _o.Object;
const String = _o.String;
const Allocator = std.mem.Allocator;
const Op = Chunk.Op;
const TokenType = Lexer.TokenType;
const Token = Lexer.Token;
const panic = std.debug.panic;
const print = std.debug.print;

const Self = @This();
parser: Parser,
lexer: Lexer,
allocator: Allocator,
compiling_chunk: *Chunk,
vm: *VM,

pub fn compile(allocator: Allocator, vm: *VM, source: [:0]const u8, chunk: *Chunk) bool {
    const lexer = Lexer.init(source);
    // TODO: probably need to pass in a parser? or something
    var self = Self{
        .parser = .{
            .current = undefined,
            .previous = undefined,
        },
        .lexer = lexer,
        .allocator = allocator,
        .vm = vm,
        .compiling_chunk = chunk,
    };
    self.parser.had_error = false;
    self.parser.panic_mode = false;
    self.advance();
    while (!self.match(TokenType.EOF)) {
        self.declaration();
    }
    self.end_compiler();
    return !self.parser.had_error;
}
fn parse_precedence(self: *Self, precedence: Precedence) void {
    self.advance();
    const can_assign = @intFromEnum(precedence) <= @intFromEnum(Precedence.ASSIGNMENT);
    const prefix_rule = self.get_rule(self.parser.previous.tag).prefix;
    if (prefix_rule) |rule| {
        rule(self, can_assign);
    } else {
        panic("Expecting expression", .{});
    }
    while (@intFromEnum(precedence) <= @intFromEnum(self.get_rule(self.parser.current.tag).precedence)) {
        self.advance();
        const infix_rule = self.get_rule(self.parser.previous.tag).infix;
        if (infix_rule) |rule| rule(self, can_assign);
        if (can_assign and self.match(TokenType.EQUAL)) {
            self.error_at_current("Invalid assignment target\n");
        }
    }
}
fn declaration(self: *Self) void {
    if (self.match(TokenType.VAR)) {
        self.var_declaration();
    } else {
        self.statement();
    }
    if (self.parser.panic_mode) self.synchronize();
}
fn statement(self: *Self) void {
    if (self.match(TokenType.PRINT)) {
        self.print_statement();
    } else {
        self.expression_statement();
    }
}
fn var_declaration(self: *Self) void {
    const global = self.parse_variable("Expect variable name");
    if (self.match(TokenType.EQUAL)) {
        self.expression();
    } else {
        self.emit_byte(Op.NIL);
    }
    _ = self.consume(TokenType.SEMICOLON, "Expect ';' after expression");
    self.define_variable(global);
}
fn define_variable(self: *Self, idx: u8) void {
    self.emit_bytes_val(@intFromEnum(Op.DEFINE_GLOBAL), idx);
}
fn parse_variable(self: *Self, error_message: []const u8) u8 {
    _ = self.consume(TokenType.IDENTIFIER, error_message);
    return self.identifier_constant(self.parser.previous);
}
fn identifier_constant(self: *Self, token: Token) u8 {
    const str = token.start[0..token.length];
    return self.make_constant(.{ .object = String.copy_string(self.allocator, self.vm, str) });
}
fn expression_statement(self: *Self) void {
    self.expression();
    self.consume(TokenType.SEMICOLON, "Expect ';' after expression");
    self.emit_byte(Op.POP);
}
fn print_statement(self: *Self) void {
    self.expression();
    self.consume(TokenType.SEMICOLON, "Expect ';' after value");
    self.emit_byte(Op.PRINT);
}
fn expression(self: *Self) void {
    self.parse_precedence(Precedence.ASSIGNMENT);
}
fn get_rule(_: *Self, tag: TokenType) ParseRule {
    return rules[@intFromEnum(tag)];
}
fn binary(self: *Self, _: bool) void {
    const tag = self.parser.previous.tag;
    const rule = self.get_rule(tag);
    self.parse_precedence(@enumFromInt(@intFromEnum(rule.precedence) + 1));
    switch (tag) {
        .PLUS => self.emit_byte(Op.ADD),
        .MINUS => self.emit_byte(Op.SUBTRACT),
        .STAR => self.emit_byte(Op.MULTIPLY),
        .SLASH => self.emit_byte(Op.DIVIDE),
        .BANG_EQUAL => self.emit_bytes(Op.EQUAL, Op.NOT),
        .GREATER => self.emit_byte(Op.GREATER),
        .GREATER_EQUAL => self.emit_bytes(Op.GREATER, Op.NOT),
        .LESS => self.emit_byte(Op.LESS),
        .LESS_EQUAL => self.emit_bytes(Op.LESS, Op.NOT),
        .EQUAL_EQUAL => self.emit_byte(Op.EQUAL),
        else => unreachable,
    }
}
fn unary(self: *Self, _: bool) void {
    const tag = self.parser.previous.tag;
    self.parse_precedence(Precedence.UNARY);
    switch (tag) {
        .MINUS => self.emit_byte(Op.NEGATE),
        .BANG => self.emit_byte(Op.NOT),
        else => unreachable,
    }
}
fn grouping(self: *Self, _: bool) void {
    self.expression();
    self.consume(TokenType.RIGHT_PAREN, "Expect ')' after expression");
}
fn consume(self: *Self, tag: TokenType, message: []const u8) void {
    if (self.parser.current.tag == tag) {
        self.advance();
        return;
    }
    self.error_at_current(message);
}
fn match(self: *Self, tag: TokenType) bool {
    if (!self.check(tag)) {
        return false;
    }
    self.advance();
    return true;
}
fn check(self: *Self, tag: TokenType) bool {
    return self.parser.current.tag == tag;
}
fn advance(self: *Self) void {
    self.parser.previous = self.parser.current;
    while (true) {
        self.parser.current = self.lexer.next();
        if (self.parser.current.tag != .ERROR) break;
        self.error_at_current(self.parser.current.start[0..self.parser.current.length]);
    }
}
fn number(self: *Self, _: bool) void {
    const value = std.fmt.parseFloat(f32, self.parser.previous.start[0..self.parser.previous.length]) catch |err| {
        panic("{s}", .{@errorName(err)});
    };
    _ = self.emit_constant(.{ .float = value });
}
fn variable(self: *Self, can_assign: bool) void {
    self.named_variable(self.parser.previous, can_assign);
}
fn named_variable(self: *Self, name: Token, can_assign: bool) void {
    const arg = self.identifier_constant(name);
    if (can_assign and self.match(TokenType.EQUAL)) {
        self.expression();
        self.emit_bytes_val(@intFromEnum(Op.SET_GLOBAL), arg);
    } else {
        self.emit_bytes_val(@intFromEnum(Op.GET_GLOBAL), arg);
    }
}
fn string(self: *Self, _: bool) void {
    // Strip off quotation marks.
    const slice = self.parser.previous.start[1 .. self.parser.previous.length - 1];
    const object = String.copy_string(self.allocator, self.vm, slice);
    _ = self.emit_constant(.{ .object = object });
}
fn literal(self: *Self, _: bool) void {
    switch (self.parser.previous.tag) {
        .FALSE => self.emit_byte(Op.FALSE),
        .TRUE => self.emit_byte(Op.TRUE),
        .NIL => self.emit_byte(Op.NIL),
        else => unreachable,
    }
}
fn make_constant(self: *Self, value: Value) u8 {
    const constant = self.current_chunk().add_constant(value);
    if (constant > std.math.maxInt(u8)) {
        // hmm could just have a DEFINE_GLOBAL_LONG?
        panic("More than 256 constants, not supported yet", .{});
    }
    return @truncate(constant);
}
fn emit_constant(self: *Self, value: Value) Size {
    const constant = self.make_constant(value);
    self.emit_bytes_val(@intFromEnum(Op.CONSTANT), constant);
    return constant;
}
fn end_compiler(self: *Self) void {
    self.emit_return();
    if (dbg and !self.parser.had_error) {
        self.current_chunk().disassemble_chunk("code");
    }
}
fn emit_bytes(self: *Self, byte1: Op, byte2: Op) void {
    self.emit_byte(byte1);
    self.emit_byte(byte2);
}
fn emit_byte(self: *Self, byte: Op) void {
    self.current_chunk().write_chunk(@intFromEnum(byte), self.parser.previous.line);
}
fn emit_bytes_val(self: *Self, byte1: u8, byte2: u8) void {
    self.emit_byte_val(byte1);
    self.emit_byte_val(byte2);
}
fn emit_byte_val(self: *Self, byte: u8) void {
    self.current_chunk().write_chunk(byte, self.parser.previous.line);
}
fn emit_return(self: *Self) void {
    self.emit_byte(Op.RETURN);
}
fn current_chunk(self: *Self) *Chunk {
    return self.compiling_chunk;
}
fn error_at_current(self: *Self, message: []const u8) void {
    self.error_at(self.parser.previous, message);
}
fn synchronize(self: *Self) void {
    while (self.parser.current.tag != TokenType.EOF) {
        if (self.parser.previous.tag == TokenType.SEMICOLON) return;
        switch (self.parser.current.tag) {
            .CLASS, .FUN, .VAR, .FOR, .IF, .WHILE, .PRINT, .RETURN => return,
            else => {},
        }
        self.advance();
    }
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
    const ParseFn = *const fn (*Self, bool) void;
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
    r[@intFromEnum(t.LEFT_PAREN)]    = .{ .prefix = grouping, .infix = null,     .precedence = Precedence.NONE       };
    r[@intFromEnum(t.BANG)]          = .{ .prefix = unary,    .infix = null,     .precedence = Precedence.NONE       };
    r[@intFromEnum(t.MINUS)]         = .{ .prefix = unary,    .infix = binary,   .precedence = Precedence.TERM       };
    r[@intFromEnum(t.PLUS)]          = .{ .prefix = null,     .infix = binary,   .precedence = Precedence.TERM       };
    r[@intFromEnum(t.SLASH)]         = .{ .prefix = null,     .infix = binary,   .precedence = Precedence.FACTOR     };
    r[@intFromEnum(t.STAR)]          = .{ .prefix = null,     .infix = binary,   .precedence = Precedence.FACTOR     };
    r[@intFromEnum(t.NUMBER)]        = .{ .prefix = number,   .infix = null,     .precedence = Precedence.NONE       };
    r[@intFromEnum(t.FALSE)]         = .{ .prefix = literal,  .infix = null,     .precedence = Precedence.NONE       };
    r[@intFromEnum(t.TRUE)]          = .{ .prefix = literal,  .infix = null,     .precedence = Precedence.NONE       };
    r[@intFromEnum(t.NIL)]           = .{ .prefix = literal,  .infix = null,     .precedence = Precedence.NONE       };
    r[@intFromEnum(t.BANG_EQUAL)]    = .{ .prefix = unary,    .infix = null,     .precedence = Precedence.EQUALITY   };
    r[@intFromEnum(t.EQUAL_EQUAL)]   = .{ .prefix = null,     .infix = binary,   .precedence = Precedence.EQUALITY   };
    r[@intFromEnum(t.GREATER_EQUAL)] = .{ .prefix = null,     .infix = binary,   .precedence = Precedence.COMPARSION };
    r[@intFromEnum(t.GREATER)]       = .{ .prefix = null,     .infix = binary,   .precedence = Precedence.COMPARSION };
    r[@intFromEnum(t.LESS_EQUAL)]    = .{ .prefix = null,     .infix = binary,   .precedence = Precedence.COMPARSION };
    r[@intFromEnum(t.LESS)]          = .{ .prefix = null,     .infix = binary,   .precedence = Precedence.COMPARSION };
    r[@intFromEnum(t.STRING)]        = .{ .prefix = string,   .infix = null,     .precedence = Precedence.NONE       };
    r[@intFromEnum(t.IDENTIFIER)]    = .{ .prefix = variable, .infix = null,     .precedence = Precedence.NONE       };
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
