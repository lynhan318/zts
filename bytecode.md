Đây là một phần kiến thức cực kỳ "khó nhằn" nhưng cũng là phần **mở mang tầm mắt nhất** khi học về Compiler.

Rất nhiều lập trình viên nghĩ rằng "Bytecode" là một thứ ma thuật đen tối. Thực ra, nó đơn giản đến mức đáng kinh ngạc.

Hãy tưởng tượng thế này:

- **Cây AST** giống như một bản vẽ kiến trúc 3D, rất tốt để con người và các công cụ phân tích (như linter) nhìn vào để hiểu ngữ cảnh.
- Nhưng CPU máy tính thì ghét bản vẽ 3D. CPU giống như một **công nhân đứng ở dây chuyền lắp ráp**. Nó chỉ muốn một danh sách các chỉ thị một chiều (1D) rõ ràng: _"Đưa cho tôi cái ốc vít, tiếp theo đưa tôi cái búa, tiếp theo đập cái búa xuống"_.

**Bytecode chính là danh sách chỉ thị một chiều đó.** Và `Chunk` chính là **"cuộn băng từ" (cassette)** chứa danh sách này.

Hãy cùng "giải phẫu" `Chunk` và xem Bytecode thực sự chạy như thế nào.

---

### PHẦN 1: TẠI SAO PHẢI CÓ STRUCT `Chunk`?

Bytecode (mã byte) bản chất chỉ là một **mảng các con số nguyên từ 0 đến 255 (u8 trong Zig)**. Mỗi con số đại diện cho một lệnh (OpCode).

Ví dụ: Quy ước số `1` là lệnh ĐẨY DỮ LIỆU VÀO NGĂN XẾP (`OP_CONST`), số `5` là lệnh CỘNG (`OP_ADD`).

**Câu hỏi đặt ra:** Nếu Bytecode chỉ là mảng các số `u8` (chỉ chứa được giá trị tối đa 255), làm sao ta nhét một số khổng lồ như `999999` hoặc một chuỗi `"Xin chào"` vào trong mảng Bytecode đó được?

**Đó là lý do `Chunk` ra đời.** `Chunk` là một cái thùng chứa 2 thứ quan trọng nhất:

1. Mảng Bytecode (Code).
2. Mảng Hằng số (Constants Pool) - Nơi chứa các cục dữ liệu lớn.

```zig
pub const Chunk = struct {
    // 1. MẢNG LỆNH (BYTECODE)
    // Chứa các chỉ thị (OpCode) và các con số nhỏ (Operand).
    // Ví dụ: [OP_CONST, 0, OP_CONST, 1, OP_ADD, OP_RETURN]
    code: std.ArrayList(u8),

    // 2. KHO CHỨA HẰNG SỐ (CONSTANTS POOL)
    // Nơi cất giữ các dữ liệu lớn (Số Float64, Chuỗi, Object...).
    // Mảng Bytecode ở trên sẽ dùng các con số 0, 1, 2 để TRỎ (Index) vào mảng này.
    constants: std.ArrayList(JsValue),

    // 3. MẢNG ĐỊNH VỊ DÒNG LỖI (Dùng cho Debug)
    // Lưu lại thông tin: Lệnh Bytecode thứ 'i' tương ứng với dòng code thứ mấy trong file gốc.
    lines: std.ArrayList(u32),
};
```

---

### PHẦN 2: BYTECODE THỰC SỰ ĐƯỢC TẠO RA NHƯ THẾ NÀO?

Hãy xem một đoạn code JavaScript cực kỳ đơn giản:

```javascript
10 + 20;
```

Khi đi qua **Compiler**, nó sẽ chuyển hóa Cây AST của đoạn code trên thành dữ liệu nhét vào `Chunk`. Quá trình diễn ra như sau:

1. Compiler thấy số `10`. Nó nhét `10` vào mảng `constants` -> Nó nằm ở vị trí **Index 0**.
2. Compiler ghi vào mảng `code` 2 byte: `OP_CONST` (Đẩy hằng số) và `0` (Index 0).
3. Compiler thấy số `20`. Nó nhét `20` vào mảng `constants` -> Nó nằm ở vị trí **Index 1**.
4. Compiler ghi vào mảng `code` 2 byte: `OP_CONST` và `1`.
5. Compiler thấy dấu `+`. Nó ghi vào mảng `code` 1 byte: `OP_ADD`.

Sau khi Compile xong, cái `Chunk` của chúng ta trông như thế này dưới bộ nhớ RAM:

```text
=== BÊN TRONG CHUNK ===

Mảng 'constants' (Kho chứa):
[ 10.0, 20.0 ]
   ^     ^
 idx 0  idx 1

Mảng 'code' (Bytecode):
[ OP_CONST, 0, OP_CONST, 1, OP_ADD ]
```

_(Thực tế trong RAM, nó chỉ là một dải số tĩnh: `[1, 0, 1, 1, 5]` giả sử OP_CONST=1, OP_ADD=5)_

---

### PHẦN 3: VIRTUAL MACHINE (VM) ĐỌC BYTECODE NHƯ THẾ NÀO?

Bây giờ là lúc "công nhân" (Virtual Machine) đi làm việc. VM có 2 công cụ chính:

- **Mảng Stack (Ngăn xếp):** Cái bàn làm việc tạm thời.
- **Con trỏ IP (Instruction Pointer):** Ngón tay chỉ vào lệnh Bytecode đang đọc.

Hãy xem VM chạy mảng `code` ở trên từng bước một:

**BƯỚC 1: Lệnh đầu tiên**

- Ngón tay (IP) trỏ vào `OP_CONST`. VM hiểu: _"À, phải lấy hằng số"_.
- IP tiến lên 1 bước, đọc số `0`. VM hiểu: _"Lấy hằng số ở vị trí 0 trong kho chứa"_.
- VM vào mảng `constants[0]` lấy ra số **10.0**.
- VM ném số `10.0` lên bàn làm việc (Stack).
- _Trạng thái Stack: `[ 10.0 ]`_

**BƯỚC 2: Lệnh thứ hai**

- IP tiến lên, trỏ vào `OP_CONST` tiếp theo.
- IP tiến lên, đọc số `1`.
- VM vào mảng `constants[1]` lấy ra số **20.0**.
- VM ném số `20.0` lên đè lên bàn làm việc (Stack).
- _Trạng thái Stack: `[ 10.0, 20.0 ]`_

**BƯỚC 3: Lệnh thứ ba (Thực thi toán học)**

- IP tiến lên, trỏ vào `OP_ADD`. VM hiểu: _"À, lấy 2 thằng trên cùng của Stack ra cộng lại"_.
- VM Pop thằng trên cùng: `b = 20.0`.
- VM Pop thằng tiếp theo: `a = 10.0`.
- VM thực hiện phép cộng CPU thực: `10.0 + 20.0 = 30.0`.
- VM ném kết quả `30.0` lại vào Stack.
- _Trạng thái Stack: `[ 30.0 ]`_

**=> Bùm! Bạn vừa thực thi thành công một phép tính bằng kiến trúc Stack-based Virtual Machine!**

---

### PHẦN 4: SỰ TINH TẾ CỦA BIẾN CỤC BỘ (LOCAL VARIABLES)

Một trong những sức mạnh khủng khiếp nhất của Bytecode là cách nó xử lý biến cục bộ.

Nếu bạn viết code JS:

```javascript
let mySuperLongVariableName = 42;
console.log(mySuperLongVariableName);
```

**Sự thật phũ phàng:** Máy ảo VM lúc chạy **KHÔNG HỀ BIẾT** tên biến là `mySuperLongVariableName`. Cái tên dài ngoằng đó đã bị "giết chết" ngay từ khâu Compiler.

Lúc biên dịch, Compiler nhận ra: _"Biến này là biến cục bộ đầu tiên được khai báo. Vậy tôi sẽ ép nó nằm ở **ô số 0 trên Stack** (Slot 0)"_.

Mã Bytecode sinh ra sẽ cực kỳ tàn nhẫn và ngắn gọn:

```text
[ OP_CONST, 0 ]   // Đẩy số 42 lên Stack
[ OP_SET_LOCAL, 0 ] // Lưu giá trị đang ở đỉnh Stack vào ô Slot 0
[ OP_GET_LOCAL, 0 ] // Khi cần console.log, lấy giá trị từ ô Slot 0 ra
[ OP_CALL... ]
```

Nhờ loại bỏ hoàn toàn các chuỗi String (tên biến) và thay bằng các con số Index (`Slot 0`), VM không phải làm phép băm (Hash) hay so sánh chuỗi nào lúc Runtime. Nó chọc thẳng vào Index của mảng Stack. Nhờ vậy, Bytecode chạy với tốc độ ngang ngửa tia chớp!

### TỔNG KẾT

1. **Bytecode** là mảng các con số, "đập phẳng" cấu trúc phức tạp của ngôn ngữ con người thành các lệnh đơn giản tuần tự.
2. **Chunk** là cấu trúc chứa mảng Bytecode đó, kèm theo một kho chứa các "vật cồng kềnh" (Constants Pool) mà mảng Bytecode không chứa nổi.
3. Việc đập phẳng này giúp loại bỏ chuỗi (string), tên biến, ngoặc đơn, ngoặc kép... giúp CPU máy tính có thể đọc và tính toán với hiệu suất cao nhất. Tới bước này, đoạn code bay bướm của bạn đã thực sự biến thành "ngôn ngữ máy".
