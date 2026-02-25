const std = @import("std");
const JsValue = @import("./types.zig").JsValue;
const Token = @import("./lexer.zig").Token;
const TokenType = @import("./lexer.zig").TokenType;
const Lexer = @import("./lexer.zig").Lexer;

const ParserError = error{UnexpectedToken};

pub const AstNode = union(enum) {
    Program: []const *AstNode,

    // Statements
    VarDecl: struct { name: Token, init: *AstNode },
    FunctionDecl: struct { name: ?Token, params: []Token, body: *AstNode, is_async: bool },
    ReturnStmt: *AstNode,
    IfStmt: struct { condition: *AstNode, then_branch: *AstNode, else_branch: ?*AstNode },
    Block: []const *AstNode,

    // Expressions
    Literal: JsValue,
    Identifier: Token,
    BinaryExpr: struct { left: *AstNode, op: Token, right: *AstNode },
    UnaryExpr: struct { op: Token, operand: *AstNode },
    CallExpr: struct { callee: *AstNode, args: []const *AstNode },
    MemberExpr: struct { object: *AstNode, property: Token },
    ArrowExpr: struct { params: []Token, body: *AstNode, is_async: bool },
    AwaitExpr: *AstNode,
};
pub const Parser = struct {
    lexer: *Lexer,
    allocator: std.mem.Allocator,
    current_token: Token,

    const Self = @This();

    pub fn init(lexer: *Lexer, allocator: std.mem.Allocator) Self {
        var p = Self{
            .lexer = lexer,
            .allocator = allocator,
            .token = undefined,
        };
        p.current_token = p.lexer.next();
        return p;
    }

    fn advance(p: *Self) void {
        p.current_token = p.lexer.next();
    }
    fn expect(self: Self, tokenType: TokenType) !Token {
        if (self.current_token.tag != tokenType) {
            return error.UnexpectedToken;
        }
    }

    fn parseExpression(self: *Self) !*AstNode {
        return try self.parseUnaryOrPrimary();
    }

    fn parseUnaryOrPrimary(self: *Self) !*AstNode {
        const tok = self.current_token;
        if (isUnaryOp(tok.tag)) {
            // handle unary
            const op = self.current_token;
            const operand = self.parseUnaryOrPrimary();
            return self.createNode(.{ .UnaryExpr = .{
                .op = op,
                .operand = operand,
            } });
        }

        return self.parsePrimary();
    }

    fn parsePrimary(self: Self) !*AstNode {
        const tok = self.current_token;
        switch (tok.tag) {
            .Number => {
                self.advance();
                const numStr = tok.text(self.lexer.source);
                const num = try std.fmt.parseFloat(f64, numStr);
                return try self.createNode(.{ .Literal = .{ .Number = num } });
            },
            .Identifier => {
                self.advance();
                return self.createNode(.{ .Identifier = tok });
            },
        }
    }

    fn isUnaryOp(tokenType: TokenType) bool {
        return switch (tokenType) {
            .Not, .Plus => true,
            else => false,
        };
    }

    fn precedence(token: Token) ?u8 {
        return switch (token.tag) {
            .Or => 10,
            .And => 20,
            .Equals, .NotEquals => 30,
            .Less, .Greater, .LessEqual, .GreaterEqual => 40,
            .Plus, .Minus => 50,
            .Start, .Slash => 60,
        };
    }

    fn createNode(self: *Self, node: AstNode) !*AstNode {
        const ptr = try self.allocator.create(AstNode);
        ptr.* = node;
        return ptr;
    }
};
