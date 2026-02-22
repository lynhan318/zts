//! By convention, root.zig is the root source file when making a library.
const std = @import("std");

pub const JsValueTag = enum {
    string,
    object,
    function,
    promise,
    null,
    undefined,
    boolean,
    number,
};

pub const JsValue = union(JsValueTag) {
    string: *JsString,
    object: *JsObject,
    function: *JsClosure,
    promise: *JsPromise,
    null,
    undefined,
    boolean: bool,
    number: f64,
};

pub const JsString = struct {
    data: []const u8,
};

pub const JsObject = struct {
    properties: std.StringHashMap(JsValue),
};

pub const JsClosureFn = fn (args: []const JsValue) JsValue;

pub const JsClosure = struct {
    fn_ptr: JsClosureFn,
    captures: ?*anyopaque,
};

pub const JsPromise = struct {
    state: enum {
        pending,
        fulfilled,
        rejected,
    },
    value: JsValue,
};

pub fn bufferedPrint() !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    try stdout.flush();
}

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add functionality" {
    try std.testing.expect(add(3, 7) == 10);
}
