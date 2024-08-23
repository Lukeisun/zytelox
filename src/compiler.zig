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
const LocalError = error{NotFound};
parser: Parser,
lexer: Lexer,
allocator: Allocator,
compiling_chunk: *Chunk,
compiler: Compiler,
vm: *VM,

pub fn compile(allocator: Allocator, vm: *VM, source: [:0]const u8, chunk: *Chunk) bool {
    const lexer = Lexer.init(source);
    const compiler = Compiler.init();
    var self = Self{
        .parser = .{
            .current = undefined,
            .previous = undefined,
        },
        .lexer = lexer,
        .allocator = allocator,
        .vm = vm,
        .compiling_chunk = chunk,
        .compiler = compiler,
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
    } else if (self.match(TokenType.LEFT_BRACE)) {
        self.begin_scope();
        self.block();
        self.end_scope();
    } else if (self.match(TokenType.IF)) {
        self.if_statement();
    } else if (self.match(TokenType.WHILE)) {
        self.while_statement();
    } else if (self.match(TokenType.FOR)) {
        self.for_statement();
    } else {
        self.expression_statement();
    }
}
fn for_statement(self: *Self) void {
    self.begin_scope();
    self.consume(TokenType.LEFT_PAREN, "Expecting '(' after 'for'.");
    // Initializer
    if (self.match(TokenType.SEMICOLON)) {} else if (self.match(TokenType.VAR)) {
        self.var_declaration();
    } else {
        self.expression_statement();
    }
    // Cond
    var loop_start = self.compiling_chunk.count;
    var found = false;
    var exit: u16 = 0;
    if (!self.match(TokenType.SEMICOLON)) {
        found = true;
        self.expression();
        self.consume(TokenType.SEMICOLON, "Expecting ';' after loop condition");
        exit = self.emit_jump(Op.JUMP_IF_FALSE);
        self.emit_byte(Op.POP);
    }
    // Inc
    if (!self.match(TokenType.RIGHT_PAREN)) {
        const body = self.emit_jump(Op.JUMP);
        const inc = self.compiling_chunk.count;
        self.expression();
        self.emit_byte(Op.POP);
        self.consume(TokenType.RIGHT_PAREN, "Expecting ')' after for clauses");
        self.emit_loop(loop_start);
        loop_start = inc;
        self.patch_jump(body);
    }
    self.statement();
    self.emit_loop(loop_start);
    if (found) {
        self.patch_jump(exit);
        self.emit_byte(Op.POP);
    }
    self.end_scope();
}

fn while_statement(self: *Self) void {
    const loop_start = self.compiling_chunk.count;
    self.consume(TokenType.LEFT_PAREN, "Expecting '(' after 'while'.");
    self.expression();
    self.consume(TokenType.RIGHT_PAREN, "Expecting ')' after condition.");
    const exit = self.emit_jump(Op.JUMP_IF_FALSE);
    self.emit_byte(Op.POP);
    self.statement();
    self.emit_loop(loop_start);
    self.patch_jump(exit);
    self.emit_byte(Op.POP);
}
fn if_statement(self: *Self) void {
    self.consume(TokenType.LEFT_PAREN, "Expecting '(' after 'if'.");
    self.expression();
    self.consume(TokenType.RIGHT_PAREN, "Expecting ')' after condition.");
    const then_jump = self.emit_jump(Op.JUMP_IF_FALSE);
    self.emit_byte(Op.POP);
    self.statement();
    const else_jump = self.emit_jump(Op.JUMP);
    self.patch_jump(then_jump);
    self.emit_byte(Op.POP);
    if (self.match(TokenType.ELSE)) self.statement();
    self.patch_jump(else_jump);
}
fn block(self: *Self) void {
    while (!self.check(TokenType.RIGHT_BRACE) and !self.check(TokenType.EOF)) {
        self.declaration();
    }
    self.consume(TokenType.RIGHT_BRACE, "Expecting '}' after block.");
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
    if (self.compiler.scope_depth > 0) {
        self.mark_initialized();
        return;
    }
    self.emit_bytes_val(@intFromEnum(Op.DEFINE_GLOBAL), idx);
}
fn mark_initialized(self: *Self) void {
    self.compiler.locals[self.compiler.local_count - 1].depth = self.compiler.scope_depth;
}
fn parse_variable(self: *Self, error_message: []const u8) u8 {
    _ = self.consume(TokenType.IDENTIFIER, error_message);
    self.declare_variable();
    if (self.compiler.scope_depth > 0) return 0;
    return self.identifier_constant(self.parser.previous);
}
fn declare_variable(self: *Self) void {
    if (self.compiler.scope_depth == 0) return;
    const name = self.parser.previous;
    var i = self.compiler.local_count;
    while (i > 0) : (i -= 1) {
        const local = self.compiler.locals[i];
        if (local.depth != -1 and local.depth < self.compiler.scope_depth) break;
        if (self.ident_equal(name, local.name)) {
            self.error_at_current("Already a variable with name in scope");
        }
    }
    self.add_local(name);
}
fn resolve_local(self: *Self, name: Token) !u8 {
    var i = self.compiler.local_count;
    while (i > 0) {
        i -= 1;
        const local = self.compiler.locals[i];
        if (self.ident_equal(name, local.name)) {
            if (local.depth == -1) {
                self.error_at_current("Can't read local variable in own initializer");
            }
            return @truncate(i);
        }
    }
    return LocalError.NotFound;
}
fn ident_equal(_: *Self, a: Token, b: Token) bool {
    if (a.length != b.length) return false;
    return std.mem.eql(u8, a.start[0..a.length], b.start[0..b.length]);
}
fn add_local(self: *Self, name: Token) void {
    if (self.compiler.local_count == std.math.maxInt(u8)) {
        self.error_at_current("Too many local vars in function");
        return;
    }
    const local: *Local = &self.compiler.locals[self.compiler.local_count];
    self.compiler.local_count += 1;
    local.* = Local{ .name = name, .depth = -1 };
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
        .GREATER_EQUAL => self.emit_bytes(Op.LESS, Op.NOT),
        .LESS => self.emit_byte(Op.LESS),
        .LESS_EQUAL => self.emit_bytes(Op.GREATER, Op.NOT),
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
fn and_(self: *Self, _: bool) void {
    const end = self.emit_jump(Op.JUMP_IF_FALSE);
    self.emit_byte(Op.POP);
    self.parse_precedence(Precedence.AND);
    self.patch_jump(end);
}
fn or_(self: *Self, _: bool) void {
    const else_jump = self.emit_jump(Op.JUMP_IF_FALSE);
    const end = self.emit_jump(Op.JUMP);
    self.patch_jump(else_jump);
    self.emit_byte(Op.POP);
    self.parse_precedence(Precedence.OR);
    self.patch_jump(end);
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
fn named_variable(self: *Self, name: Token, can_assign: bool) void {
    // const arg = self.identifier_constant(name);
    var get_op: Op = undefined;
    var set_op: Op = undefined;
    var found = true;
    var arg = self.resolve_local(name) catch blk: {
        found = false;
        break :blk 0;
    };
    if (found) {
        get_op = Op.GET_LOCAL;
        set_op = Op.SET_LOCAL;
    } else {
        arg = self.identifier_constant(name);
        get_op = Op.GET_GLOBAL;
        set_op = Op.SET_GLOBAL;
    }
    if (can_assign and self.match(TokenType.EQUAL)) {
        self.expression();
        self.emit_bytes_val(@intFromEnum(set_op), arg);
    } else {
        self.emit_bytes_val(@intFromEnum(get_op), arg);
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
fn begin_scope(self: *Self) void {
    self.compiler.scope_depth += 1;
}
fn end_scope(self: *Self) void {
    self.compiler.scope_depth -= 1;
    while (self.compiler.local_count > 0 and self.compiler.locals[self.compiler.local_count - 1].depth > self.compiler.scope_depth) {
        self.emit_byte(Op.POP);
        self.compiler.local_count -= 1;
    }
}
fn make_constant(self: *Self, value: Value) u8 {
    const constant = self.compiling_chunk.add_constant(value);
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
        self.compiling_chunk.disassemble_chunk("code");
    }
}
fn emit_bytes(self: *Self, byte1: Op, byte2: Op) void {
    self.emit_byte(byte1);
    self.emit_byte(byte2);
}
fn emit_byte(self: *Self, byte: Op) void {
    self.compiling_chunk.write_chunk(@intFromEnum(byte), self.parser.previous.line);
}
fn emit_bytes_val(self: *Self, byte1: u8, byte2: u8) void {
    self.emit_byte_val(byte1);
    self.emit_byte_val(byte2);
}
fn emit_byte_val(self: *Self, byte: u8) void {
    self.compiling_chunk.write_chunk(byte, self.parser.previous.line);
}
fn emit_return(self: *Self) void {
    self.emit_byte(Op.RETURN);
}
fn emit_loop(self: *Self, count: Size) void {
    self.emit_byte(Op.LOOP);
    const offset = self.compiling_chunk.count - count + 2;
    if (offset > std.math.maxInt(u16)) self.error_at_current("Loop too large");
    self.emit_byte_val(@truncate(offset >> 8));
    self.emit_byte_val(@truncate(offset));
}
fn emit_jump(self: *Self, byte: Op) u16 {
    self.emit_byte(byte);
    self.emit_byte_val(0xff);
    self.emit_byte_val(0xff);
    return @truncate(self.compiling_chunk.count - 2);
}
fn patch_jump(self: *Self, offset: u16) void {
    const jump = self.compiling_chunk.count - offset - 2;
    if (jump > std.math.maxInt(u16)) self.error_at_current("Too much code to jump over");
    self.compiling_chunk.code[offset] = @truncate(jump >> 8);
    self.compiling_chunk.code[offset + 1] = @truncate(jump);
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
const Compiler = struct {
    locals: [std.math.maxInt(u8)]Local,
    local_count: u8,
    scope_depth: u8,
    pub fn init() Compiler {
        const local = [_]Local{.{ .name = undefined, .depth = undefined }} ** std.math.maxInt(u8);
        return .{ .locals = local, .local_count = 0, .scope_depth = 0 };
    }
};
const Local = struct {
    name: Token,
    depth: i16,
};
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
    r[@intFromEnum(t.AND)]           = .{ .prefix = null,     .infix = and_,     .precedence = Precedence.AND        };
    r[@intFromEnum(t.OR)]            = .{ .prefix = null,     .infix = or_,     .precedence  = Precedence.OR         };
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
