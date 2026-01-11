# README – Final Project: Simple SoC with AHB Bus (Cortex-M0)

## 1. Tổng quan dự án

Dự án này hiện thực một **hệ thống SoC đơn giản** dựa trên **ARM Cortex-M0**, sử dụng **bus AHB-Lite** để kết nối CPU với các ngoại vi tự thiết kế.
Mục tiêu của dự án là minh họa **nguyên lý tổ chức SoC**, **cơ chế bus AHB**, **lập trình mức thấp bằng Assembly**, và **xử lý ngắt timer** trong một hệ thống nhúng hoàn chỉnh.

Hệ thống được xây dựng phục vụ mục đích **giảng dạy – học tập**, không tối ưu theo hướng thương mại.

---

## 2. Kiến trúc hệ thống

### 2.1. Thành phần chính

Hệ thống SoC bao gồm:

* **CPU**: ARM Cortex-M0
* **Bus liên kết**: AHB-Lite (single master)
* **Các slave ngoại vi**:

  * MEMORY (Instruction/Data memory)
  * LCD controller (hiển thị 2 dòng, 16 ký tự)
  * TIMER (đếm thời gian, phát sinh ngắt)
  * GPIO (đọc switch, điều khiển LED)
* **Bộ điều khiển ngắt**: NVIC tích hợp trong Cortex-M0

---

### 2.2. Phân bố địa chỉ ngoại vi (Memory-mapped I/O)

| Ngoại vi | Base Address  |
| -------- | ------------- |
| LCD      | `0x5000_0000` |
| TIMER    | `0x5200_0000` |
| GPIO     | `0x5300_0000` |
| NVIC     | `0xE000_E100` |

---

## 3. Lập trình phần cứng (Hardware Programming)

### 3.1. Tổng quan

Phần cứng được mô tả bằng **Verilog HDL**, tuân thủ chuẩn **AHB-Lite slave interface**.
Mỗi ngoại vi được thiết kế như **một AHB slave độc lập**, phản hồi truy cập từ CPU trong một chu kỳ.

Các nội dung chính:

* Giải mã địa chỉ AHB
* Thanh ghi điều khiển (control/status registers)
* FSM điều khiển nội bộ từng ngoại vi
* Phát sinh và xoá ngắt (TIMER)

---

### 3.2. Ngoại vi LCD

LCD được thiết kế theo mô hình:

* **Display RAM 32 byte** (2 dòng × 16 ký tự)
* Thanh ghi **CTRL** (START, CLEAR)
* Thanh ghi **STATUS** (busy flag)

CPU chỉ ghi dữ liệu và kích hoạt START;
FSM trong phần cứng chịu trách nhiệm **truyền dữ liệu xuống LCD** theo đúng timing.

---

### 3.3. Ngoại vi TIMER

TIMER hoạt động theo **compare / reload mode**, bao gồm:

* LOAD register
* VALUE register
* CONTROL register
* CLEAR register

Khi VALUE đếm về 0:

* Phát sinh `timer_irq`
* Nếu periodic mode → reload từ LOAD
* Nếu one-shot → dừng timer

---

### 3.4. Ngoại vi GPIO

GPIO hỗ trợ:

* Đọc trạng thái switch (GPIOIN)
* Điều khiển LED (GPIOOUT)
* Thanh ghi DIR để chọn hướng I/O

---

## 4. Lập trình phần mềm (Software Programming)

### 4.1. Ngôn ngữ và mức lập trình

* **Assembly (ARM Thumb)**
* Không sử dụng thư viện C hoặc HAL
* Truy cập ngoại vi bằng **memory-mapped I/O**

---

### 4.2. Cấu trúc chương trình

Chương trình gồm các phần chính:

1. **Reset_Handler**

   * Khởi tạo NVIC
   * Cấu hình GPIO
   * Dừng timer
   * Hiển thị trạng thái ban đầu trên LCD

2. **Main Loop**

   * Poll trạng thái các nút nhấn (SW0–SW3)
   * Cập nhật mode hệ thống
   * Ghi LED tương ứng
   * Không xử lý logic thời gian thực

3. **Interrupt Handler (Timer_Handler)**

   * Xử lý tăng / giảm counter
   * Cập nhật LCD
   * Dừng timer khi kết thúc đếm

---

### 4.3. Các chế độ hoạt động

| Mode      | Mô tả          |
| --------- | -------------- |
| MODE_OFF  | Hệ thống tắt   |
| MODE_ON   | Hệ thống bật   |
| MODE_UP   | Đếm tăng 0 → 9 |
| MODE_DOWN | Đếm giảm 9 → 0 |

---

## 5. Luồng hoạt động tổng thể

Luồng hoạt động của hệ thống:

1. CPU reset → khởi tạo hệ thống
2. Main loop poll nút nhấn
3. Khi vào chế độ đếm:

   * Cấu hình TIMER
   * Chờ ngắt
4. TIMER phát sinh ngắt
5. ISR cập nhật counter và LCD
6. Kết thúc đếm → quay về MODE_ON

---


