Để hiểu được sự kỳ diệu của **Closure (Bao đóng)** trong JavaScript, chúng ta cần nhìn thấy sự thay đổi của bộ nhớ ở 2 trạng thái: **Khi hàm cha đang chạy** và **Khi hàm cha đã kết thúc (return)**.

Dưới đây là sơ đồ ASCII Architecture thể hiện cách `JsFunction` (Bản vẽ), `JsClosure` (Thực thể) và `JsUpvalue` (Mỏ neo) phối hợp với nhau.

Giả sử chúng ta đang chạy đoạn code sau:

```javascript
function parent() {
  let count = 0; // Biến cục bộ trên Stack
  return function () {
    // Trả về JsClosure
    return count++; // Truy cập biến 'count'
  };
}
let counter = parent();
```

---

### TRẠNG THÁI 1: HÀM CHA ĐANG CHẠY (UPVALUE "MỞ" - OPEN)

Khi hàm `parent()` đang được thực thi, biến `count` vẫn đang nằm an toàn trên **VM Stack**. Lúc này, `JsClosure` được tạo ra để chuẩn bị `return`. Mỏ neo `JsUpvalue` sẽ chĩa thẳng con trỏ `location` vào địa chỉ của biến `count` trên Stack. Trạng thái này gọi là **Open Upvalue**.

```text
      [ VIRTUAL MACHINE STACK ]
      ┌───────────────────────┐
      │ Global: parent        │
      ├───────────────────────┤ ◄── Call Frame của parent()
      │ [Slot 5] count = 0    │◄─────────────────────────┐
      │ [Slot 6] (temp vars)  │                          │
      └───────────────────────┘                          │
                                                         │
      [ HEAP MEMORY (Garbage Collected) ]                │
                                                         │
   ┌──────────────────────────┐     ┌────────────────────┴─────┐
   │ JsFunction (Bản vẽ)      │     │ JsUpvalue (Mỏ neo)       │
   ├──────────────────────────┤     ├──────────────────────────┤
   │ name: "anonymous"        │     │ closed: <trống>          │
   │ bytecode: [OP_GET_UPVAL] │     │ location: *Stack[Slot 5] │
   │ upvalue_count: 1         │     └─────────▲────────────────┘
   └───────────▲──────────────┘               │
               │                              │
               │                              │
   ┌───────────┴──────────────┐               │
   │ JsClosure (Thực thể)     │               │
   ├──────────────────────────┤               │
   │ function: *JsFunction    │               │
   │ upvalues: [*JsUpvalue] ──┼───────────────┘
   └──────────────────────────┘
```

**Hoạt động:** Nếu lúc này hàm con được gọi ngay lập tức, lệnh `OP_GET_UPVAL` sẽ đi theo con đường: `Closure -> Upvalue -> location -> Stack[Slot 5]`, và lấy được số `0` trực tiếp từ Stack với tốc độ ánh sáng.

---

### TRẠNG THÁI 2: HÀM CHA ĐÃ RETURN (UPVALUE "ĐÓNG" - CLOSED)

Khi `parent()` gọi lệnh `return`, toàn bộ Call Frame của nó trên Stack sẽ bị **tiêu hủy**. Ô `Slot 5` không còn chứa biến `count` nữa mà sẽ bị ghi đè bởi các hàm khác.

Nếu `JsUpvalue` vẫn trỏ vào Stack, ta sẽ dính lỗi _Dangling Pointer_ (Trỏ vào vùng nhớ rác) chết người.

Vì vậy, ngay khoảnh khắc `parent()` return, VM thực hiện phép thuật: Nó bốc giá trị `0` từ Stack, **copy** nó vào trường `closed` bên trong `JsUpvalue`, và bẻ gập con trỏ `location` trỏ ngược lại vào chính mình! Trạng thái này gọi là **Closed Upvalue**.

```text
      [ VIRTUAL MACHINE STACK ]
      ┌───────────────────────┐
      │ Global: counter ──────┼───────┐ (Biến counter giữ mạng Closure)
      ├───────────────────────┤       │
      │ (Call Frame của cha   │       │
      │  đã bị HỦY / XÓA BỎ)  │       │
      └───────────────────────┘       │
                                      │
      [ HEAP MEMORY ]                 │
                                      │
                                      ▼
   ┌──────────────────────────┐   ┌──────────────────────────┐
   │ JsClosure (Thực thể)     │   │ JsFunction (Bản vẽ)      │
   ├──────────────────────────┤   ├──────────────────────────┤
   │ function: *JsFunction ───┼──►│ name: "anonymous"        │
   │ upvalues: [*JsUpvalue] ──┼─┐ │ bytecode: [OP_GET_UPVAL] │
   └──────────────────────────┘ │ │ upvalue_count: 1         │
                                │ └──────────────────────────┘
                                │
                                │    ┌──────────────────────────┐
                                │    │ JsUpvalue (Mỏ neo)       │
                                └───►├──────────────────────────┤
                                  ┌─►│ closed: JsValue (Num: 0) │ ◄─ Biến 'count' đã
                                  │  │ location: *self.closed ──┼─┐  chuyển nhà lên Heap!
                                  │  └─────────▲────────────────┘ │
                                  │            │                  │
                                  │            └──────────────────┘
                                  └────────────── (Trỏ vào chính nó)
```

**Hoạt động khi gọi `counter()`:**

1. VM lấy `JsClosure` ra chạy.
2. Bytecode báo lệnh `OP_GET_UPVAL 0`.
3. VM chọc vào `upvalues[0]` để lấy `JsUpvalue`.
4. VM đi theo con trỏ `location`. Nhờ phép thuật ở trên, `location` giờ đây đang trỏ vào trường `closed`.
5. VM lấy được số `0`, cộng lên thành `1`, ghi đè lại vào trường `closed`.

### LỜI BÌNH CỦA SYSTEM ENGINEER:

Sự tách biệt thành 3 khối này là một thiết kế thiên tài (Data-Oriented):

- **JsFunction** chỉ lưu logic (Bytecode). Dù bạn có vòng lặp `for (let i=0; i<100; i++)` tạo ra 100 hàm con, thì `JsFunction` vẫn **chỉ có 1 bản duy nhất trên RAM**.
- **JsClosure** cực nhẹ, chỉ là nơi kết nối giữa Logic (Function) và Data (Upvalues).
- **JsUpvalue** cho phép biến cục bộ "sống thọ" hơn cả vòng đời của hàm sinh ra nó, chuyển đổi mượt mà từ Stack (nhanh) sang Heap (bền vững) mà Bytecode của hàm con không hề hay biết (không cần sửa code logic). Nó là trái tim của Functional Programming.
