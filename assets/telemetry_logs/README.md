# Log GPS/IMU thật (issue #8)

Các file `.jsonl` trong thư mục này được đóng gói vào app và hiện trong màn Chạy,
mục "Nguồn dữ liệu" > "Phát lại log". Demo Simulator (Ngày 29) cũng dùng các file này.

## Cách lấy log

1. Cài IPA mới nhất (GitHub Actions > SISO-Runner-IPA) bằng Sideloadly.
2. Trên bản đồ, **nhấn giữ nút "Chạy"** để mở màn "Ghi log cảm biến".
3. Chọn nhãn (Chạy bộ / Đi bộ / Xe máy / Khác), ghi chú, bấm "Bắt đầu ghi". Màn hình được giữ sáng; đừng khoá máy.
4. "Dừng và lưu", rồi bấm nút Chia sẻ của file (AirDrop/Zalo/Mail), hoặc mở ứng dụng Tệp:
   Trên iPhone > SISO > telemetry_logs.
5. Chép file vào thư mục này rồi chạy lại app.

## Quy ước

- Repo công khai, log chứa toạ độ thật: **chỉ ghi ở nơi công cộng** (sân trường, bờ kè), không bắt đầu ghi từ nhà.
  Mở file kiểm tra các dòng `"k":"g"` trước khi commit.
- Giữ tên file như app đặt: `siso_<nhãn>_<yyyyMMdd-HHmmss>.jsonl`.

## Định dạng (JSON Lines, mỗi dòng một bản ghi)

| `k` | Ý nghĩa                        | Trường                                                                                           |
| --- | ------------------------------ | ------------------------------------------------------------------------------------------------ |
| `h` | Header (dòng đầu)              | `v`, `startedAt` (UTC), `label` (`run`/`walk`/`motorbike`/`other`), `note`, `device`, `platform` |
| `a` | Gia tốc kế, m/s², có trọng lực | `t` (ms từ lúc bấm Bắt đầu), `x`, `y`, `z`                                                       |
| `g` | GPS                            | `t`, `lat`, `lng`, `acc` (m), `spd` (m/s, iOS trả -1 khi chưa có), `mock`                        |

Chi tiết: `lib/src/features/tracking/domain/telemetry_log.dart`.
