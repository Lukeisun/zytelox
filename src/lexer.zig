const std = @import("std");
const print = std.debug.print;
const Self = @This();
start: [*:0]const u8,
current: [*:0]const u8,
line: u16,

pub fn init(source: [:0]const u8) Self {
    return .{
        .start = source[0..].ptr,
        .current = source[0..].ptr,
        .line = 1,
    };
}

pub fn next(self: *Self) Token {
    self.skip_white_space();
    self.start = self.current;
    if (self.out_of_bounds()) return self.make_token(TokenType.EOF);
    const c = self.advance();
    switch (c) {
        '{' => return self.make_token(TokenType.LEFT_BRACE),
        '}' => return self.make_token(TokenType.RIGHT_BRACE),
        '(' => return self.make_token(TokenType.LEFT_PAREN),
        ')' => return self.make_token(TokenType.RIGHT_PAREN),
        ',' => return self.make_token(TokenType.COMMA),
        '.' => return self.make_token(TokenType.DOT),
        '-' => return self.make_token(TokenType.MINUS),
        '+' => return self.make_token(TokenType.PLUS),
        '*' => return self.make_token(TokenType.STAR),
        '/' => return self.make_token(TokenType.SLASH),
        ';' => return self.make_token(TokenType.SEMICOLON),
        '!' => {
            return if (self.match('=')) self.make_token(TokenType.BANG) else self.make_token(TokenType.BANG);
        },
        '=' => {
            return if (self.match('=')) self.make_token(TokenType.EQUAL_EQUAL) else self.make_token(TokenType.EQUAL);
        },
        '>' => {
            return if (self.match('=')) self.make_token(TokenType.GREATER_EQUAL) else self.make_token(TokenType.GREATER);
        },
        '<' => {
            return if (self.match('=')) self.make_token(TokenType.LESS_EQUAL) else self.make_token(TokenType.LESS);
        },
        '"' => return self.string(),
        else => {
            if (std.ascii.isDigit(c)) {
                return self.number();
            } else if (std.ascii.isAlphabetic(c) or c == '_') {
                return self.identifier();
            }
        },
    }
    return self.make_token_error("Unexepcted character");
}

// TODO: may need to advance one? but this should only enter if the first char
// is alphabetic or _ so maybe not
fn identifier(self: *Self) Token {
    while (std.ascii.isAlphanumeric(self.peek()) or self.peek() == '_') _ = self.advance();
    return self.make_token(self.identifier_type());
}
fn identifier_type(self: *Self) TokenType {
    // Not gonna do what robert does here, static string map to the rescue
    const s = self.start[0 .. self.current - self.start];
    const token_type = keywords.get(s);
    if (token_type) |t| {
        return t;
    }
    return TokenType.IDENTIFIER;
}
fn number(self: *Self) Token {
    while (std.ascii.isDigit(self.peek())) _ = self.advance();
    if (self.peek() == '.' and std.ascii.isDigit(self.peekNext())) {
        _ = self.advance();
        while (std.ascii.isDigit(self.peek())) _ = self.advance();
    }
    return self.make_token(TokenType.NUMBER);
}
fn string(self: *Self) Token {
    while (self.peek() != '"' and !self.out_of_bounds()) {
        if (self.peek() == '\n') self.line += 1;
        _ = self.advance();
    }
    if (self.out_of_bounds()) return self.make_token_error("Unterminated string");
    _ = self.advance();
    return self.make_token(TokenType.STRING);
}
fn skip_white_space(self: *Self) void {
    while (true) {
        const c = self.peek();
        if (std.ascii.isWhitespace(c)) {
            if (c == '\n') {
                self.line += 1;
            }
            _ = self.advance();
        } else if (c == '/') {
            if (self.peekNext() == '/') {
                while (self.peek() != '\n' and !self.out_of_bounds()) _ = self.advance();
            } else {
                return;
            }
        } else {
            return;
        }
    }
}
fn peekNext(self: *Self) u8 {
    if (self.out_of_bounds()) return 0;
    return self.current[1];
}
fn peek(self: *Self) u8 {
    return self.current[0];
}
fn match(self: *Self, expected: u8) bool {
    if (self.out_of_bounds()) return false;
    if (self.current[0] != expected) return false;
    self.current += 1;
    return true;
}
fn out_of_bounds(self: *Self) bool {
    return (self.current[0] == 0);
}
fn advance(self: *Self) u8 {
    self.current += 1;
    return (self.current - 1)[0];
}

pub fn make_token(self: *Self, tag: TokenType) Token {
    return .{
        .tag = tag,
        .start = self.start,
        .length = self.current - self.start,
        .line = self.line,
    };
}

pub fn make_token_error(self: *Self, message: [:0]const u8) Token {
    return .{
        .tag = TokenType.ERROR,
        .start = message.ptr,
        .length = message.len,
        .line = self.line,
    };
}

pub const Token = struct {
    tag: TokenType,
    start: [*:0]const u8,
    length: usize,
    line: u16,
};

pub const TokenType = enum(u8) {
    // Single Character Tokens
    LEFT_PAREN,
    RIGHT_PAREN,
    LEFT_BRACE,
    RIGHT_BRACE,
    COMMA,
    DOT,
    MINUS,
    PLUS,
    SEMICOLON,
    SLASH,
    STAR,
    // One/Two char tokens
    BANG,
    BANG_EQUAL,
    EQUAL,
    EQUAL_EQUAL,
    GREATER,
    GREATER_EQUAL,
    LESS,
    LESS_EQUAL,
    // Literals
    IDENTIFIER,
    STRING,
    NUMBER,
    // Keywords
    AND,
    CLASS,
    ELSE,
    FALSE,
    FUN,
    FOR,
    IF,
    NIL,
    OR,
    PRINT,
    RETURN,
    SUPER,
    THIS,
    TRUE,
    VAR,
    WHILE,
    //
    ERROR,
    EOF,
};
pub const keywords = std.StaticStringMap(TokenType).initComptime(.{
    .{ "and", TokenType.AND },
    .{ "class", TokenType.CLASS },
    .{ "else", TokenType.ELSE },
    .{ "false", TokenType.FALSE },
    .{ "for", TokenType.FOR },
    .{ "fun", TokenType.FUN },
    .{ "if", TokenType.IF },
    .{ "nil", TokenType.NIL },
    .{ "or", TokenType.OR },
    .{ "print", TokenType.PRINT },
    .{ "return", TokenType.RETURN },
    .{ "super", TokenType.SUPER },
    .{ "this", TokenType.THIS },
    .{ "true", TokenType.TRUE },
    .{ "var", TokenType.VAR },
    .{ "while", TokenType.WHILE },
});
