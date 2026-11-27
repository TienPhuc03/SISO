# ADR-0002: Đơn vị thi đấu là cơ sở, xếp hạng theo Cụm

- Trạng thái: Đã chấp nhận (2026-11-27)
- Phạm vi: `backend/` (bảng `clusters`, `districts`, các cột mới của `universities` / `users` / `arenas` / `hall_of_fame`, view `v_campus_live_scores`, `close_finished_season`, module `universities`, `TurfService.claimLoop`), app Flutter (`features/university`, Bảng xếp hạng), web admin (Trường)

## Bối cảnh

SISO mở rộng từ 5 trường ở Bình Thạnh ra toàn TP.HCM. Đăng nhập không còn dùng email trường, nên Sinh viên tự chọn Trường, và có thể tự thêm Trường chưa có trong danh sách. Nhiều trường có cơ sở ở các khu khác nhau (UEH: Q3, Q10, Bình Chánh; NTTU: Q4, Q12; HCMUT: Q10, Dĩ An). Đấu trường hiện chỉ có ở Bình Thạnh.

## Quyết định

- **Mỗi dòng `universities` là một cơ sở thi đấu.** Các cơ sở cùng thương hiệu gom lại bằng `parent_name`. Sinh viên chọn cơ sở mình học nhiều nhất. Cơ sở ngoài TP.HCM thì không cho chọn.
- **Cụm theo quận.** Bảng `districts` ánh xạ quận (tên cũ, trước 7/2025) sang `clusters`. Quận nằm ngoài 4 Cụm gốc được gán vào Cụm gần nhất. Riêng Dĩ An (KĐT ĐHQG) thuộc Cụm Thủ Đức. Đổi ánh xạ chỉ cần sửa một dòng, mọi Trường của quận đó tự đổi Cụm theo.
- **Xếp hạng trong Cụm.**
  - % Lãnh thổ tính trên các Đấu trường đang hoạt động của Cụm. % Km tính trên tổng Quỹ Km của Cụm.
  - Cụm chưa có Đấu trường thì Sức mạnh Tổng hợp = % Km.
  - Mỗi Mùa có một Quán quân cho mỗi Cụm (unique `(season_number, cluster_code)`).
- **Đấu trường thuộc một Cụm** (`arenas.cluster_code`). Vòng khép ở Đấu trường của Cụm khác bị từ chối với ERR_306, nên Phiên chạy đó kết thúc như Chạy tự do. Khu thi đấu Bình Thạnh (không gửi `arenaId`) được tính là Cụm NORTH.
- **Trường tự thêm.** Trường do Sinh viên thêm được tạo ngay và tính điểm ngay, với `is_verified = false`. Hệ thống không tạo bản sao khi tên trùng (đã bỏ dấu, không phân biệt hoa thường), hoặc khi trùng tên ngắn trong cùng quận. Admin duyệt, sửa, gộp (chuyển Sinh viên, Ô đất, Quỹ Km, Quán quân) hoặc xoá các Trường này.
- **Khoá Trường theo Mùa** (`users.university_season`):
  - Chọn Trường khi chưa có thì khoá đến hết Mùa đó.
  - Sang Mùa mới được đổi cho tới Phiên chạy hợp lệ đầu tiên của Mùa. Không đổi thì coi như ở lại.

## Phương án đã cân nhắc

- **Xếp hạng theo trường mẹ (UEH là một Trường)**: một trường sẽ thuộc nhiều Cụm cùng lúc, nên không xếp được vào Cụm nào cho đúng.
- **Lưu `cluster` trực tiếp trên `universities`**: đổi ánh xạ quận thì phải cập nhật nhiều dòng, và dễ lệch với quận đã lưu.
- **Bắt admin duyệt trước khi tính điểm**: Sinh viên của trường mới phải chờ, trái với yêu cầu "nạp ngay".

## Hệ quả

- `v_campus_live_scores` có thêm `cluster_code` và `cluster_has_arena`. API `leaderboard/scores` và `hall-of-fame` nhận thêm `?cluster=`.
- Ô đất chiếm trước khi có luật Cụm mà nằm ở Đấu trường của Cụm khác không được tính vào % Lãnh thổ.
- Vẫn còn đường gian lận: tạo tài khoản ở Trường đối thủ để phá. Bị chặn một phần nhờ luật khoá theo Mùa và việc email phải được xác minh.
- Thêm Đấu trường cho Cụm Thủ Đức, Trung tâm và Khu Nam: thêm vào `arenas.geojson`, đặt `cluster_code`, rồi chạy `seed:hexagons`.
