# ADR-0001: Lưu Đường chạy dạng JSONB theo từng Cửa sổ

- Trạng thái: Đã chấp nhận (2026-11-20)
- Phạm vi: `backend/` — bảng `session_windows`, `TelemetryService`, `TurfService.claimLoop`

## Bối cảnh

Trước đây server chỉ lưu tổng quãng đường và thời gian của Phiên chạy. Ứng dụng cần vẽ Đường chạy, xem Lịch sử Phiên chạy với biểu đồ tốc độ / Nhịp bước, và Cổng Hình học cần đối chiếu Vòng khép client gửi với vệt GPS thật (trước đây server tin đường biên của client). Mỗi giờ chạy có khoảng 700 Cửa sổ và 3.600 điểm GPS.

## Quyết định

Một bảng `session_windows`, mỗi Cửa sổ qua Cổng Động học là một dòng (khoá `(session_id, seq)`), gồm tốc độ, Nhịp bước, cờ `passed` và cột `gps_points JSONB` chứa các điểm `{lat, lng, timestamp, accuracy}`. Ghi trong cùng transaction với việc cộng quãng đường ở `verifyWindow`. Bật RLS, không có policy: chỉ backend đọc được.

Trước khi lưu, chỉ giữ điểm có sai số 0–20 m và đi tới được từ điểm đã lưu trước đó (điểm neo: điểm cuối của Cửa sổ gần nhất có điểm) với tốc độ ≤ 9 m/s (`filterPlausiblePoints`). Điểm bị bỏ không làm điểm neo, nên toạ độ bịa hay dịch chuyển tức thời không kéo được Đường chạy đi xa.

Đối chiếu Vòng khép làm trong backend bằng `h3-js`: mỗi ô biên phải nằm trong 1 vòng ô quanh một điểm GPS có sai số 0–20 m (ERR_305).

## Phương án đã cân nhắc

- **Bảng điểm riêng (`session_points`, một dòng mỗi điểm)**: gấp ~5 lần số dòng, thêm một lần ghi mỗi Cửa sổ, không có truy vấn nào cần lọc theo từng điểm.
- **Cột PostGIS `geometry(LineString)`**: không có truy vấn không gian nào chạy trong DB; mất `timestamp` / `accuracy` của từng điểm (cần để tách đoạn khi Tạm dừng và bỏ điểm sai số lớn).

## Hệ quả

- Lịch sử Phiên chạy đọc một lần theo `session_id`, ghép Đường chạy trong `buildRoute` (tách đoạn khi hai điểm cách nhau > 15 s).
- Tạm dừng không cần xử lý riêng ở server: không có Cửa sổ thì không có điểm, nên Vòng khép vắt qua quãng đi xe không khớp Đường chạy.
- Phiên chạy không gửi `gpsPoints` (client cũ) không chiếm đất được nữa.
- Client vẫn tự báo toạ độ: kẻ gian bịa được Đường chạy nếu chịu "chạy" đúng tốc độ người trong đúng thời gian thật, giống mức tin hiện tại với `averageSpeedMps`. Lọc không nới theo sai số GPS, nên GPS rung mạnh có thể làm thưa Đường chạy (ngưỡng tạm).
- Cửa sổ ERR_203 (mất tín hiệu) không được lưu, nên Đường chạy có khoảng trống ở đó; mất tín hiệu dài trên đường biên có thể làm Vòng khép thật bị ERR_305.
- Nếu sau này cần truy vấn không gian (ví dụ bản đồ nhiệt), có thể thêm cột PostGIS sinh từ `gps_points` mà không đổi API.
