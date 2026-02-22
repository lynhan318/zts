Chào bạn, để tạo ra một **Ebook Markdown hoàn chỉnh và liền mạch**, tôi đã xóa bỏ toàn bộ các phần chú thích `// ... (cũ)`. Thay vào đó, tôi tự tay hợp nhất (merge) các logic từ những phiên bản trước (vòng lặp Lexer, các toán tử cơ bản, cấu trúc AST ban đầu) với các khái niệm nâng cao (Call Stack, Async/Await, Module).

Dưới đây là phiên bản **MASTER DOCUMENT** (Tài liệu gốc). Bạn chỉ cần copy toàn bộ nội dung trong khối code bên dưới, lưu thành file `ZJS_Engine_Architecture.md` và mở bằng bất kỳ trình đọc Markdown nào (VSCode, Obsidian, Typora).

---

# GIẢI PHẪU MỘT MÁY ẢO JAVASCRIPT: TỪ TEXT ĐẾN EVENT LOOP

**Tài liệu Cốt lõi (Core Fundamentals) - Thiết kế Compiler & Virtual Machine chuẩn Production**
_Tác giả: AI System Engineer | Ngôn ngữ mô phỏng: Zig_

---

## MỞ ĐẦU: TRIẾT LÝ KIẾN TRÚC & ĐƯỜNG ỐNG (THE PIPELINE)

Một ngôn ngữ lập trình không chỉ là một chương trình dịch cú pháp, nó là một **Hệ sinh thái (Ecosystem)**. Khi bạn thực thi một file `.js`, mã nguồn của bạn đi qua một "đường ống" gồm 4 phân xưởng chính:

1. **Front-end (Lexer & Parser):** Đọc văn bản thuần (Text), kiểm tra ngữ pháp, lột bỏ các phần dư thừa (khoảng trắng, comment) và xây dựng Bản thiết kế cấu trúc (AST - Abstract Syntax Tree).
2. **Compiler (Bộ biên dịch):** Máy tính ghét cấu trúc Cây vì nó gây phân mảnh bộ nhớ. Compiler có nhiệm vụ "đập phẳng" AST thành một mảng lệnh 1 chiều gọi là **Bytecode**.
3. **Virtual Machine (Máy ảo - VM):** Một CPU mô phỏng bằng phần mềm. Nó đọc Bytecode và thực thi các phép toán trên Ngăn xếp (Stack).
4. **Runtime Environment (Môi trường):** Trái tim duy trì sự sống, bao gồm _Garbage Collector_ (Dọn rác), _Event Loop_ (Xử lý bất đồng bộ) và _Module Loader_.

---

## CHƯƠNG 1: HỆ THỐNG KIỂU DỮ LIỆU ĐỘNG (THE TYPE SYSTEM)

> **Fundamental:** Trong các ngôn ngữ System như C/Zig, biến `x` trỏ thẳng vào vùng nhớ cố định (VD: 8 bytes cho int64). Nhưng trong JS (Kiểu động), `x` có thể chứa số, rồi lát sau chứa chuỗi, rồi thành Array.

Để giải quyết, ta bọc mọi dữ liệu trong một chiếc hộp gọi là `JsValue`. Đối với các cấu trúc dữ liệu lớn (String, Array, Object, Function), chúng phải được cấp phát động trên **Heap** và bắt buộc phải có một `GcHeader` để bộ dọn rác quản lý.

```zig
const std = @import("std");

// 1. Phân loại dữ liệu (Tag)
pub const ValueType = enum(u8) {
    Null, Undefined, Boolean, Number,
    // Tham chiếu (Heap Objects)
    String, Object, Array, Function, Promise
};

// 2. Header bắt buộc cho MỌI object nằm trên Heap
pub const GcHeader = struct {
    type: ValueType,
    is_marked: bool,     // Dùng cho thuật toán GC Mark-and-Sweep
    next: ?*GcHeader,    // Danh sách liên kết để GC duyệt qua mọi object
};

// 3. Chiếc hộp chứa mọi giá trị trong JS (Tagged Union - 16 bytes)
pub const JsValue = union(ValueType) {
    Null: void,
    Undefined: void,
    Boolean: bool,
    Number: f64, // Chuẩn IEEE 754: Mọi số trong JS đều là Float 64-bit

    // Con trỏ trỏ ra vùng nhớ Heap
    String: *JsString,
    Object: *JsObject,
    Function: *JsClosure, // Chạy thực tế là chạy Closure, không phải Function chay
    Promise: *JsPromise,

    // Hàm kiểm tra logic Falsy của JS
    pub fn isFalsy(self: JsValue) bool {
        return switch (self) {
            .Null, .Undefined => true,
            .Boolean => |b| !b,
            .Number => |n| n == 0 or std.math.isNan(n),
            else => false,
        };
    }
};
```

---

## CHƯƠNG 2: FRONT-END TỐI ƯU (LEXER & PARSER)

### 2.1 Lexer (Zero-Allocation)

Trình phân tích từ vựng (Lexer) không được phép cấp phát bộ nhớ động (Heap Allocation) để tránh làm chậm hệ thống. Nó chỉ trượt một con trỏ trên source code và trả về vị trí `start`, `end` (gọi là Span).

Việc kiểm tra từ khóa (let, fn, async) được tối ưu bằng `ComptimeStringMap` (Bảng băm tạo sẵn lúc biên dịch bộ Compiler).

```zig
pub const TokenType = enum(u8) {
    // Single & Double Chars
    Plus, Minus, Star, Slash, Assign, Equals,
    OpenParen, CloseParen, OpenBrace, CloseBrace, Semicolon, Arrow, // Arrow: "=>"
    // Literals & Keywords
    Identifier, Number, String,
    SingleQuote, DoubleQuote,  // '...' and "..."
    KeywordLet, KeywordConst, KeywordFunction, KeywordAsync, KeywordAwait, KeywordReturn,
    Eof, Invalid,
};

pub const Token = struct {
    tag: TokenType,
    start: u32,
    end: u32,
    line: u32,
    col: u32,
};

pub const Lexer = struct {
    source: []const u8,
    index: u32, line: u32, col: u32,

    // Zero-cost keyword lookup
    const keywords = std.ComptimeStringMap(TokenType, .{
        .{ "let", .KeywordLet },
        .{ "const", .KeywordConst },
        .{ "function", .KeywordFunction },
        .{ "async", .KeywordAsync },
        .{ "await", .KeywordAwait },
        .{ "return", .KeywordReturn },
    });

    // Lặp qua mã nguồn để lấy Token tiếp theo
    pub fn next(self: *Lexer) Token {
        self.skipWhitespace();
        if (self.index >= self.source.len) return self.makeToken(.Eof, self.index);

        const start_idx = self.index;
        const c = self.advance();

        switch (c) {
            '+' => return self.makeToken(.Plus, start_idx),
            '-' => return self.makeToken(.Minus, start_idx),
            ';' => return self.makeToken(.Semicolon, start_idx),
            '=' => {
                if (self.match('>')) return self.makeToken(.Arrow, start_idx); // "=>"
                if (self.match('=')) return self.makeToken(.Equals, start_idx); // "=="
                return self.makeToken(.Assign, start_idx);
            },
            '0'...'9' => {
                while (std.ascii.isDigit(self.peek())) _ = self.advance();
                return self.makeToken(.Number, start_idx);
            },
            'a'...'z', 'A'...'Z', '_' => {
                while (std.ascii.isAlphanumeric(self.peek()) or self.peek() == '_') _ = self.advance();
                const text = self.source[start_idx..self.index];
                const tag = keywords.get(text) orelse .Identifier;
                return self.makeToken(tag, start_idx);
            },
            else => return self.makeToken(.Invalid, start_idx),
        }
    }

    // Các hàm tiện ích cho Lexer
    pub fn peek(self: @This()) u8 {
        return self.source[self.index];
    }

    pub fn match(self: *@This(), expected: u8) bool {
        if (self.peek() == expected) {
            self.index += 1;
            return true;
        }
        return false;
    }
};
```

### 2.2 Parser & Cây Cú Pháp Trừu Tượng (AST)

Để xử lý hàng triệu AST Node mà không bị rò rỉ bộ nhớ (Memory Leak), ta phải dùng **Arena Allocator**.

```zig
pub const AstNode = union(enum) {
    Literal: JsValue,
    Identifier: Token,
    BinaryExpr: struct { left: *AstNode, op: Token, right: *AstNode },
    VarDecl: struct { name: Token, init: *AstNode },

    // Hỗ trợ hàm tiêu chuẩn
    FunctionDecl: struct {
        name: ?Token,
        params: []Token,
        body: *AstNode, // Block code
        is_async: bool
    },

    // Hỗ trợ Arrow Function
    ArrowExpr: struct {
        params: []Token,
        body: *AstNode,
        is_async: bool
    },

    // Hỗ trợ Bất đồng bộ
    AwaitExpr: struct { promise_expr: *AstNode },
};
```

---

## CHƯƠNG 3: BỘ BIÊN DỊCH VÀ BẢN CHẤT CỦA HÀM (CLOSURE)

> **Fundamental:** Lập trình viên lầm tưởng Arrow Function `() => {}` chỉ là cách viết ngắn gọn. Thực tế ở tầng Memory, Arrow Function khác Regular Function ở cách nó tạo ra **Execution Context (this)**.

Máy tính không chạy "Hàm", nó chạy **Closure (Bao đóng)**.

1. **JsFunction:** Bản thiết kế tĩnh (Chứa Bytecode, tạo ra 1 lần lúc biên dịch).
2. **JsClosure:** Thực thể sống lúc Runtime. Nó chứa con trỏ tới `JsFunction` cộng với "chiếc ba-lô" chứa các biến môi trường mà nó mượn từ bên ngoài (bao gồm cả `this` đối với Arrow Function).

```zig
// Tập lệnh máy ảo (Instruction Set Architecture)
pub const OpCode = enum(u8) {
    OP_CONST,       // Đẩy hằng số lên đỉnh Stack
    OP_ADD,         // Lấy 2 số từ Stack, cộng lại
    OP_GET_LOCAL,   // Lấy biến cục bộ
    OP_SET_LOCAL,   // Gán biến cục bộ
    OP_CALL,        // Gọi hàm
    OP_RETURN,      // Trả kết quả về hàm cha
    OP_AWAIT,       // Đóng băng (Suspend) Frame hiện tại
};

// Bản thiết kế hàm tĩnh
pub const JsFunction = struct {
    obj_header: GcHeader,
    bytecode: []const u8,       // Mảng lệnh biên dịch phẳng
    constants: []const JsValue, // Chứa chuỗi, số lớn...
    arity: u8,                  // Số tham số đầu vào
    is_async: bool,
};

// Thực thể hàm chạy lúc Runtime
pub const JsClosure = struct {
    obj_header: GcHeader,
    function: *JsFunction,
    captured_values: []*JsValue, // Mảng con trỏ giữ các biến môi trường
};
```

---

## CHƯƠNG 4: VIRTUAL MACHINE (VM) VÀ NGĂN XẾP GỌI HÀM

Để VM có thể gọi hàm đệ quy (A gọi B, B gọi C, C trả về B), nó cần một **Call Stack** (Ngăn xếp gọi hàm) chứa các **Call Frames** (Khung thực thi). Lỗi _Maximum call stack size exceeded_ xảy ra chính là khi mảng `frames` này bị quá tải.

```zig
// Đại diện cho MỘT LẦN gọi hàm đang chạy
pub const CallFrame = struct {
    closure: *JsClosure, // Hàm đang chạy
    ip: [*]const u8,     // Instruction Pointer: Trỏ tới dòng lệnh tiếp theo của hàm này
    stack_base: usize,   // Vị trí bắt đầu của các biến cục bộ của hàm này trên Stack tổng
};

pub const VM = struct {
    // Ngăn xếp dữ liệu tổng (Chứa biến cục bộ của TẤT CẢ các hàm đang chạy)
    stack: [8192]JsValue,
    stack_top: usize,

    // Chồng CallFrames
    frames: [256]CallFrame,
    frame_count: usize,

    // TRÁI TIM CỦA MÁY ẢO: Vòng lặp Dispatch Loop
    pub fn run(self: *VM) !void {
        var frame = &self.frames[self.frame_count - 1];

        while (true) {
            const instruction = @as(OpCode, @enumFromInt(frame.ip[0]));
            frame.ip += 1;

            switch (instruction) {
                .OP_CONST => {
                    const constant_idx = frame.ip[0];
                    frame.ip += 1;
                    self.push(frame.closure.function.constants[constant_idx]);
                },
                .OP_ADD => {
                    const b = self.pop();
                    const a = self.pop();
                    self.push(JsValue{ .Number = a.Number + b.Number });
                },
                .OP_GET_LOCAL => {
                    const slot = frame.ip[0];
                    frame.ip += 1;
                    self.push(self.stack[frame.stack_base + slot]);
                },

                // --- XỬ LÝ GỌI HÀM ---
                .OP_CALL => {
                    const arg_count = frame.ip[0];
                    frame.ip += 1;
                    const callee = self.stack[self.stack_top - arg_count - 1];

                    // TẠO CALL FRAME MỚI
                    var new_frame = &self.frames[self.frame_count];
                    new_frame.closure = callee.Function; // Lấy Closure
                    new_frame.ip = callee.Function.function.bytecode.ptr;
                    new_frame.stack_base = self.stack_top - arg_count;

                    self.frame_count += 1;
                    frame = new_frame; // Trượt ngữ cảnh sang hàm con!
                },
                .OP_RETURN => {
                    const result = self.pop();
                    self.frame_count -= 1; // Hủy Call Frame hiện tại

                    if (self.frame_count == 0) return; // Code chạy xong hoàn toàn

                    // Phục hồi Frame của hàm cha
                    frame = &self.frames[self.frame_count - 1];
                    self.stack_top = frame.stack_base - 1;
                    self.push(result); // Đẩy kết quả về cho hàm cha tính tiếp
                },

                // --- MAGIC CỦA ASYNC/AWAIT Ở ĐÂY ---
                .OP_AWAIT => {
                    const promise = self.pop();

                    // 1. Lưu Call Frame hiện tại (Suspend) vào Heap
                    const suspended_state = self.saveCurrentCoroutineState(frame);

                    // 2. Gắn callback: "Khi nào Promise xong, lôi trạng thái kia ra chạy tiếp"
                    promise.Promise.onResolve(suspended_state);

                    // 3. Phá hủy Call Frame hiện tại khỏi Stack đồng bộ để VM rảnh tay
                    self.frame_count -= 1;
                    if (self.frame_count == 0) return; // Nhường quyền lại cho Event Loop!

                    frame = &self.frames[self.frame_count - 1];
                },
            }
        }
    }
};
```

---

## CHƯƠNG 5: EVENT LOOP & MODULE SYSTEM (THE RUNTIME)

### 5.1 Sự ảo ảnh của Event Loop

> **Fundamental:** `Async/Await` KHÔNG PHẢI là chạy đa luồng (Parallelism). VM chỉ có 1 thread. Phép thuật nằm ở chỗ: Nhờ lệnh `OP_AWAIT` biết cách **Đóng băng (Suspend)** hàm hiện tại ra ngoài bộ nhớ, Event Loop có thể lấy các hàm khác ra chạy xen kẽ trong lúc đợi I/O, tạo cảm giác như nhiều thứ đang chạy cùng lúc.

```zig
pub const Runtime = struct {
    vm: VM,
    microtask_queue: std.ArrayList(*JsClosure), // Chứa các Promise đã có kết quả (then/await)
    macrotask_queue: std.ArrayList(*JsClosure), // Chứa setTimeout, I/O callbacks

    pub fn startEventLoop(self: *Runtime) !void {
        // 1. Chạy file main ban đầu (Đồng bộ)
        try self.vm.run();

        // 2. Vòng lặp bất tử (Event Loop)
        while (true) {
            // Ưu tiên 1: Chạy SẠCH Microtask Queue
            while (self.microtask_queue.items.len > 0) {
                const task = self.microtask_queue.orderedRemove(0);
                self.vm.loadFunction(task);
                try self.vm.run(); // Hàm Await được RESUME và chạy tiếp từ dòng code bị ngắt!
            }

            if (!self.hasPendingTasks()) break;

            // Ưu tiên 2: Ngủ và chờ HĐH báo có mạng/disk I/O xong (thông qua epoll/kqueue)
            const macro_task = try self.waitForOperatingSystem();
            self.vm.loadFunction(macro_task);
            try self.vm.run();
        }
    }
};
```

### 5.2 Module Loader (Giải quyết lặp vô tận)

Khó khăn lớn nhất của lệnh `import`/`require` là **Circular Dependency** (A gọi B, B gọi ngược A). Để giải quyết, Module System cần một Bộ đệm Cache (Registry). Nó tạo ra một Object Module rỗng và lưu vào Cache _trước khi_ thực sự chạy file đó.

```zig
pub const ModuleSystem = struct {
    registry: std.StringHashMap(*JsObject),
    vm: *VM,

    pub fn require(self: *ModuleSystem, path: []const u8) !JsValue {
        // 1. Hit Cache (Giải quyết vòng lặp A -> B -> A)
        if (self.registry.get(path)) |cached_exports| return JsValue{ .Object = cached_exports };

        // 2. Cấp phát Object rỗng và LƯU NGAY VÀO CACHE
        var exports_obj = createJsObject();
        try self.registry.put(path, exports_obj);

        // 3. IO & Pipeline: Đọc File -> Tokens -> AST -> Bytecode
        const source = try std.fs.cwd().readFileAlloc(...);
        const bytecode = try Compiler.compileSource(source);

        // 4. Chạy File để nhồi các biến export vào `exports_obj`
        try self.vm.executeModule(bytecode, exports_obj);

        return JsValue{ .Object = exports_obj };
    }
};
```

---

## CHƯƠNG 6: TỔNG HỢP PIPELINE (`main.zig`)

Dưới đây là điểm neo khởi nguồn của vũ trụ ZJS, nơi kết nối toàn bộ 5 chương lại với nhau:

```zig
pub fn main() !void {
    const source_code =
        \\ import { log } from 'sys';
        \\ async function fetchUser() { return 42; }
        \\
        \\ const run = async () => {
        \\     let data = await fetchUser();
        \\     log(data + 10);
        \\ };
        \\ run();
    ;

    // 1. Quản lý bộ nhớ siêu tốc cho Front-end (Arena)
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit(); // Hủy toàn bộ Tokens & AST ngay khi compile xong (Zero Memory Leak)

    // 2. FRONT-END: Text -> Tokens -> AST
    var lexer = Lexer.init(source_code);
    var parser = Parser.init(&lexer, arena.allocator());
    const ast = try parser.parse();

    // 3. COMPILER: AST -> Bytecode (Mảng tuyến tính)
    var chunk = Chunk.init(std.heap.page_allocator);
    defer chunk.deinit();
    try Compiler.compile(ast, &chunk);

    // 4. Khởi tạo Không gian chạy (VM + Event Loop + GC + Module System)
    var vm = VM.init(&chunk);
    var runtime = Runtime{ .vm = vm };

    // 5. RUNTIME: Kích hoạt nhịp tim của máy ảo!
    std.debug.print("🚀 ZJS Engine is running...\n", .{});
    try runtime.startEventLoop();
}
```

---

## TỔNG KẾT BÀI HỌC KIẾN TRÚC TỪ ENGINE

Bằng cách nhìn thấu hệ thống này, bạn đã giải mã được các bí ẩn của V8 và Node.js:

1. **Tại sao `JSON.parse` file lớn làm giật trình duyệt?** Vì nó phải qua bước _Lexer & Parser_ để xây dựng Cây AST trên Thread chính, tốn rất nhiều chu kỳ CPU.
2. **Tại sao bộ nhớ rò rỉ (Memory Leak) thường xảy ra ở Closure?** Vì `JsClosure` chứa mảng `captured_values`. Mảng này trỏ ra các biến bên ngoài, khiến Garbage Collector thấy chúng "vẫn đang bị giữ tham chiếu" và không chịu dọn dẹp.
3. **Sức mạnh của Single-Thread:** Node.js xử lý hàng chục ngàn Request/giây không phải bằng sức mạnh cơ bắp của CPU, mà bằng sự khéo léo của **Event Loop** và lệnh **OP_AWAIT** nhường việc (yielding) một cách chính xác.

_Hãy sử dụng tài liệu này làm kim chỉ nam. Khi bạn tự tay implement từng thành phần một bằng Zig, Rust hoặc C++, tư duy Kỹ sư Hệ thống của bạn sẽ vĩnh viễn thay đổi._
