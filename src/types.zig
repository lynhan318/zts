const std = @import("std");

//Một biến trong javascript khi được khai báo sẽ được gán lại với nhiều kiểu dữ liệu
pub const ValueType = enum(u8) {
    Null,
    Undefined,
    Bool,
    Number,
    // Heap pointer (need GC)
    String,
    Object,
    Array,
    Function,
    Promise,
};

pub const GcHeader = struct {
    type: ValueType,
    is_marked: bool,
    next: ?*GcHeader,
};

pub const JsValue = union(ValueType) {
    Null: void,
    Undefined: void,
    Boolean: bool,
    Number: f64,
    String: *JsString,
    Object: *JsObject,
    Array: *JsArray,
    Function: *JsFunction,
    Promise: *JsPromise,

    pub fn isFalsy(self: @This()) bool {
        return switch (self) {
            .Null, .Undefined => false,
            .Boolean => |b| !b,
            .Number => |n| n == 0 || std.math.isNan(n),
            .String => |s| std.mem.eql(u8, s, ""),
            else => false,
        };
    }
};

pub const JsString = struct {
    header: GcHeader,
    bytes: []const u8,
    length: usize,

    //Cache lại hashed string, tối ưu khi string được sử dụng như 1 key của object ví dụ user['name']
    hash: u32,
};

pub const JsObject = struct {
    header: GcHeader,
    properties: std.AutoHashMap(*JsString, JsValue),
    // Object prototype ví dụ toString,...
    prototype: ?*JsObject,
};

pub const JsArray = struct {
    header: GcHeader,
    elements: std.ArrayList(JsValue),
    properties: std.AutoHashMap(*JsString, JsValue),
    //Array prototype ví dụ pop,map,find,...
    prototype: ?*JsObject,
};

pub const JsFunction = struct {
    header: GcHeader,
    name: ?*JsString, // Tên hàm để in ra stack khi có lỗi
    arity: u32, //Số lượng tham số: (a,b) -> arity = 2
    upvalue_count: u32, //Số lượng biến đang sử dụng ở bên ngoài function(Closurejkjk)
    chunk: Chunk,
};

pub const JsUpValue = struct {
    header: GcHeader,
    // Khi hàm cha đang chạy, 'location' trỏ thẳng vào vùng nhớ Stack của VM.
    // Khi hàm cha kết thúc, VM sẽ copy giá trị từ Stack vào biến 'closed' bên dưới,
    // và trỏ 'location' vào biến 'closed' này.
    location: *JsValue,
    closed: *JsValue,
    next: ?*JsUpValue,
};

pub const JsClosure = struct {
    header: GcHeader,
    function: *JsFunction, // trỏ về function gốc
    upvalues: []*JsUpValue,
};

pub const JsPromise = struct {
    header: GcHeader,
};

pub const Chunk = struct {
    // 1. Mảng Bytecode (Chứa các OpCode và Toán hạng)
    // Ví dụ: [OP_CONST, 0, OP_ADD, OP_RETURN]
    code: std.ArrayList(u8),

    // 2. Mảng Hằng số (Constants Pool)
    // Máy tính không thể nhét chuỗi "Hello" hay số 3.14 trực tiếp vào mảng 1 byte ở trên.
    // Nó lưu vào mảng constants này. Bytecode chỉ lưu Index (0, 1, 2...) trỏ vào đây.
    constants: std.ArrayList(JsValue),

    // 3. (Bổ sung cho Production) Ghi nhớ Dòng code gốc
    // Cứ mỗi byte trong mảng `code`, mảng `lines` lưu số dòng tương ứng trong file .js
    // Dùng để in ra lỗi: "Error at line 15"
    lines: std.ArrayList(u32),

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) @This() {
        return .{ .code = std.ArrayList(u8).empty, .constants = std.ArrayList(JsUpValue).empty, .lines = std.ArrayList(u32).empty, .allocator = allocator };
    }
    pub fn deinit(self: *@This()) void {
        self.code.deinit(self.allocator);
        self.constants.deinit(self.allocator);
        self.lines.deinit(self.allocator);
    }
};
