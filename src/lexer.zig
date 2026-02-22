const std = @import("std");

pub const TokenType = enum(u8) {
    // Single & Double Chars
    Plus,
    Minus,
    Star,
    Slash,
    Assign,
    Equals,
    OpenParen,
    CloseParen,
    OpenBrace,
    CloseBrace,
    Semicolon,
    Arrow, // Arrow: "=>"
    // Literals & Keywords
    Identifier,
    Number,
    String,
    KeywordLet,
    KeywordConst,
    KeywordFunction,
    KeywordAsync,
    KeywordAwait,
    KeywordReturn,
    Eof,
    Invalid,
};

pub const Token = struct {
    tag: TokenType,
    start: u32,
    end: u32,
    line: u32,
    col: u32,

    pub fn text(self: Token, source: []const u8) []const u8 {
        return source[self.start..self.end];
    }
};

pub const Lexer = struct {
    source: []const u8,
    index: u32,
    line: u32,
    col: u32,

    const keywords = std.StaticStringMap(TokenType).initComptime(.{
        .{ "let", .KeywordLet },
        .{ "function", .KeywordFunction },
        .{ "const", .KeywordConst },
        .{ "async", .KeywordAsync },
        .{ "await", .KeywordAwait },
        .{ "return", .KeywordReturn },
    });

    pub fn init(source: []const u8) @This() {
        return .{ .source = source, .index = 0, .line = 0, .col = 0 };
    }

    pub fn next(self: *@This()) Token {
        self.skipWhitespace();
        self.skipEndline();
        if (self.index >= self.source.len) return self.makeToken(.Eof, self.index, self.line, self.col);
        const startIndex = self.index;
        const startLine = self.line;
        const startCol = self.col;

        const c = self.advance();
        return switch (c) {
            '+' => self.makeToken(.Plus, startIndex, startLine, startCol),
            '-' => self.makeToken(.Minus, startIndex, startLine, startCol),
            '=' => {
                if (self.match('>')) {
                    return self.makeToken(.Arrow, startIndex, startLine, startCol);
                }
                if (self.match('=')) {
                    return self.makeToken(.Equals, startIndex, startLine, startCol);
                }
                return self.makeToken(.Assign, startIndex, startLine, startCol);
            },
            ';' => self.makeToken(.Semicolon, startIndex, startLine, startCol),
            '*' => self.makeToken(.Star, startIndex, startLine, startCol),
            '/' => self.makeToken(.Slash, startIndex, startLine, startCol),
            '0'...'9' => {
                while (std.ascii.isDigit(self.peek())) _ = self.advance();
                return self.makeToken(.Number, startIndex, startLine, startCol);
            },
            'a'...'z', 'A'...'Z', '_' => {
                while (std.ascii.isAlphanumeric(self.peek()) or self.peek() == '_') _ = self.advance();
                const text = self.source[startIndex..self.index];
                const tag = keywords.get(text) orelse .Identifier;
                return self.makeToken(tag, startIndex, startLine, startCol);
            },
            else => {
                std.debug.print(">>>> Found Invalid {c}", .{c});
                return self.makeToken(.Invalid, startIndex, startLine, startCol);
            },
        };
    }

    pub fn makeToken(self: *@This(), tokenType: TokenType, startIndex: u32, startLine: u32, startCol: u32) Token {
        return .{
            .tag = tokenType,
            .start = startIndex,
            .end = self.index,
            .line = startLine,
            .col = startCol,
        };
    }

    /// Di chuyển con trỏ và trả về ký tự hiện tại.
    /// Cập nhật line/col khi gặp newline.
    pub fn advance(self: *@This()) u8 {
        if (self.index >= self.source.len) return 0;
        const currentChar = self.source[self.index];
        self.index += 1;
        self.col += 1;
        return currentChar;
    }

    pub fn skipWhitespace(self: *@This()) void {
        while (self.peek() == ' ') {
            self.index += 1;
            self.col += 1;
        }
    }

    pub fn skipEndline(self: *@This()) void {
        while (self.peek() == '\n') {
            self.index += 1;
            self.line += 1;
            self.col = 0;
        }
    }
    /// Xem ký tự hiện tại mà không di chuyển con trỏ.
    pub fn peek(self: @This()) u8 {
        if (self.index >= self.source.len) return 0;
        return self.source[self.index];
    }

    /// Kiểm tra ký tự hiện tại có khớp với expected không.
    /// Nếu có, di chuyển con trỏ và trả về true.
    pub fn match(self: *@This(), expected: u8) bool {
        if (self.index >= self.source.len) return false;
        if (self.source[self.index] == expected) {
            self.index += 1;
            self.col += 1;
            return true;
        }
        return false;
    }
};

test "Lexer - basic tokens" {
    var lexer = Lexer.init("+ - * / =");
    try std.testing.expectEqual(lexer.next().tag, .Plus);
    try std.testing.expectEqual(lexer.next().tag, .Minus);
    try std.testing.expectEqual(lexer.next().tag, .Star);
    try std.testing.expectEqual(lexer.next().tag, .Slash);
    try std.testing.expectEqual(lexer.next().tag, .Assign);
    try std.testing.expectEqual(lexer.next().tag, .Eof);
}

test "Lexer - keywords" {
    var lexer = Lexer.init("let const function async await return");
    try std.testing.expectEqual(lexer.next().tag, .KeywordLet);
    try std.testing.expectEqual(lexer.next().tag, .KeywordConst);
    try std.testing.expectEqual(lexer.next().tag, .KeywordFunction);
    try std.testing.expectEqual(lexer.next().tag, .KeywordAsync);
    try std.testing.expectEqual(lexer.next().tag, .KeywordAwait);
    try std.testing.expectEqual(lexer.next().tag, .KeywordReturn);
    try std.testing.expectEqual(lexer.next().tag, .Eof);
}

test "Lexer - identifier" {
    var lexer = Lexer.init("foo bar123 _underscore");
    const tok1 = lexer.next();
    try std.testing.expectEqual(tok1.tag, .Identifier);
    try std.testing.expectEqualStrings(tok1.text(lexer.source), "foo");

    const tok2 = lexer.next();
    try std.testing.expectEqual(tok2.tag, .Identifier);
    try std.testing.expectEqualStrings(tok2.text(lexer.source), "bar123");

    const tok3 = lexer.next();
    try std.testing.expectEqual(tok3.tag, .Identifier);
    try std.testing.expectEqualStrings(tok3.text(lexer.source), "_underscore");

    try std.testing.expectEqual(lexer.next().tag, .Eof);
}

test "Lexer - number" {
    var lexer = Lexer.init("42 12345 0");
    try std.testing.expectEqual(lexer.next().tag, .Number);
    try std.testing.expectEqual(lexer.next().tag, .Number);
    try std.testing.expectEqual(lexer.next().tag, .Number);
    try std.testing.expectEqual(lexer.next().tag, .Eof);
}

test "Lexer - arrow token" {
    var lexer = Lexer.init("=>");
    try std.testing.expectEqual(lexer.next().tag, .Arrow);
    try std.testing.expectEqual(lexer.next().tag, .Eof);
}

test "Lexer - equals token" {
    var lexer = Lexer.init("==");
    try std.testing.expectEqual(lexer.next().tag, .Equals);
    try std.testing.expectEqual(lexer.next().tag, .Eof);
}

test "Lexer - token positions" {
    var lexer = Lexer.init("let x = 1");
    const tok = lexer.next();
    try std.testing.expectEqual(tok.tag, .KeywordLet);
    try std.testing.expectEqual(tok.start, 0);
    try std.testing.expectEqual(tok.end, 3);
}

test "Lexer - line and col" {
    const source =
        \\let x = 1;
        \\const y = 2;
    ;
    var lexer = Lexer.init(source);
    const tok = lexer.next();
    try std.testing.expectEqual(tok.tag, .KeywordLet);
    try std.testing.expectEqual(tok.start, 0);
    try std.testing.expectEqual(tok.end, 3);
    try std.testing.expectEqual(tok.line, 0);
    try std.testing.expectEqual(tok.col, 0);
    //skip to nextline;
    const tok1 = lexer.next();

    try std.testing.expectEqual(tok1.tag, .Identifier);
    try std.testing.expectEqual(tok1.col, 4);

    const tok2 = lexer.next();
    try std.testing.expectEqual(tok2.tag, .Assign);
    try std.testing.expectEqual(tok2.col, 6);

    const tok3 = lexer.next();
    try std.testing.expectEqual(tok3.tag, .Number);

    const tok4 = lexer.next();
    try std.testing.expectEqual(tok4.tag, .Semicolon);

    const tok5 = lexer.next();
    try std.testing.expectEqual(tok5.tag, .KeywordConst);
    try std.testing.expectEqual(tok5.line, 1);
    try std.testing.expectEqual(tok5.col, 0);

    const tok6 = lexer.next();
    try std.testing.expectEqual(tok6.tag, .Identifier);
    try std.testing.expectEqual(tok6.line, 1);
    try std.testing.expectEqual(tok6.col, 6);
}
