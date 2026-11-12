# Mẫu IMU thật cho Cổng Sinh trắc (ticket #9)

Log `.jsonl` ghi bằng màn "Ghi log cảm biến" trên iPhone (nhấn giữ nút "Chạy" trên bản đồ),
**đã bỏ toạ độ** trước khi commit. Thư mục này không đóng gói vào app.

- Test: `src/modules/telemetry/anti-gigo.real-imu.spec.ts` (tự bỏ qua khi chưa có log của một nhãn).
- Báo cáo + gợi ý ngưỡng: `npm run imu:analyze` (mặc định đọc thư mục này).

## Thêm log mới

```bash
# 1. Xem báo cáo trên log gốc (còn toạ độ, để ngoài repo)
npm run imu:analyze -- <thư mục log gốc>

# 2. Chép bản đã bỏ lat/lng vào đây
npm run imu:analyze -- --strip-gps test-fixtures/imu-logs <thư mục log gốc>
```

## Kịch bản cần có (mỗi kịch bản >= 2 phút, lặp 2–3 lần, nếu được thì 2 người)

| Nhãn | Kịch bản | Ghi chú nên ghi trong app |
|---|---|---|
| Chạy bộ | Máy trong túi quần; máy cầm tay hoặc đeo bắp tay | `túi quần, sân HUTECH` |
| Đi bộ | Đi bộ nhanh, máy trong túi quần | `túi quần, ...` |
| Xe máy | ~12 km/h máy gắn giá đỡ; ~12 km/h máy trong túi người lái; ~20 km/h | `giá đỡ, 12km/h, D2` |
| Khác | Chạy chậm sát ngưỡng (~9 km/h) | `jog 9km/h, ...` |

## Tiêu chí đạt (test)

- Chạy bộ: >= 90% cửa sổ được xét (>= 2,5 m/s) qua cổng; không phiên nào bị loại vì ERR_202.
- Xe máy: >= 90% cửa sổ được xét bị ERR_202; mỗi phiên bị loại trong 6 cửa sổ (~30 s) kể từ khi đủ tốc độ.
- Đi bộ: không phiên nào bị loại vì ERR_202.
