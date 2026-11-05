# Kịch bản kiểm thử Module 2: Bản đồ H3 & Đấu trường

Phạm vi:

- **Backend (NestJS):** `GET /api/v1/turf/hexagons` (`TurfService.getArenaHexagons`) và `GET /api/v1/turf/arenas` (`TurfService.getArenas`).
- **Client (Flutter):** `HexagonLayer` + `MapStateNotifier` + `HexagonRepository`, gồm cập nhật realtime qua `hex_claimed`.

Tài liệu liên quan: [walkthrough_getArenaHexagons.md](walkthrough_getArenaHexagons.md), [walkthrough_HexagonLayer.md](walkthrough_HexagonLayer.md).

Quy ước: **TC-API-xx** = API ô đất, **TC-ARN-xx** = API Đấu trường, **TC-UI-xx** = giao diện Flutter, **TC-AUTO-xx** = test tự động. Mỗi test case có cột **Kết quả** (Pass/Fail) để bạn điền.

---

## 1. Pre-conditions

### 1.1. Môi trường

| Thành phần | Yêu cầu | Kiểm tra nhanh |
|---|---|---|
| Backend | `backend/.env` trỏ tới Supabase (hoặc `docker-compose up -d`), đã `npm install` | `npm run start:dev` in ra `SISO API Server is running on: http://localhost:3000` |
| Database | Đã chạy `src/database/init_schema.sql`: có 5 trường và 4 Đấu trường seed | SQL ở 1.3 trả đủ dòng |
| Flutter | `flutter pub get` xong; file `.env` gốc có `API_BASE_URL=http://localhost:3000`, `SOCKET_URL=http://localhost:3000/turf-ws` | `flutter devices` thấy Chrome |
| `web/index.html` | Có dòng nạp `h3-js@3.7.2` trước `flutter_bootstrap.js` | Thiếu dòng này thì bản đồ không vẽ được ô trên Chrome |
| Công cụ gọi API | Postman, hoặc `curl` trong Git Bash | Lệnh cURL dưới đây viết cho Git Bash; trong PowerShell dùng `curl.exe` |
| Mạng | Có Internet để tải tile OpenStreetMap | Không có mạng thì nền bản đồ trống, ô vẫn phải vẽ được |

Chạy backend và app (mỗi lệnh một terminal):

```bash
cd backend && npm run start:dev
```

```bash
flutter run -d chrome --web-port 5000
```

Cố định cổng `5000` để mở được tab thứ hai cùng địa chỉ (`http://localhost:5000`) cho phần realtime.

### 1.2. Tài khoản và token

- Hai API `GET` **không cần token** (công khai).
- Chỉ phần realtime (TC-UI-05, TC-UI-07) cần JWT để gọi `claim-loop`. Lấy token demo như sau:

```bash
curl -s -X POST http://localhost:3000/api/v1/auth/edu-login -H "Content-Type: application/json" -d '{"email":"tester01@uef.edu.vn"}'
```

```bash
curl -s -X POST http://localhost:3000/api/v1/auth/verify-otp -H "Content-Type: application/json" -d '{"email":"tester01@uef.edu.vn","otp":"123456"}'
```

Copy giá trị `accessToken` trong kết quả, rồi gán vào biến:

```bash
export TOKEN="<dán accessToken vào đây>"
```

Lần đầu `verify-otp` sẽ **tạo một dòng mới trong `users`** cho `tester01@uef.edu.vn`. OTP hết hạn sau 5 phút và chỉ dùng được một lần.

### 1.3. Dữ liệu mẫu

Chạy trong Supabase SQL Editor. Đây là **dữ liệu thử**: 7 ô quanh tâm bản đồ (10.800, 106.718), sinh bằng `h3-js gridDisk(latLngToCell(10.800, 106.718, 10), 1)`. 3 ô gán vào Đấu trường Landmark 81, 4 ô không thuộc Đấu trường nào.

```sql
-- [TEST DATA] Module 2: xoá bằng SQL ở mục 1.4 sau khi test
INSERT INTO public.h3_hexagons (h3_index, arena_id, owner_university_id, shield_hp)
VALUES
  ('8a65b56718b7fff', (SELECT id FROM public.arenas WHERE name = 'Công Viên Landmark 81'),
                      (SELECT id FROM public.universities WHERE short_code = 'HUTECH'), 100),
  ('8a65b5671d6ffff', (SELECT id FROM public.arenas WHERE name = 'Công Viên Landmark 81'),
                      (SELECT id FROM public.universities WHERE short_code = 'HUTECH'), 80),
  ('8a65b5671d4ffff', (SELECT id FROM public.arenas WHERE name = 'Công Viên Landmark 81'),
                      (SELECT id FROM public.universities WHERE short_code = 'UEF'), 100),
  ('8a65b5671897fff', NULL, NULL, 100),
  ('8a65b5671887fff', NULL, NULL, 100),
  ('8a65b56718a7fff', NULL, NULL, 100),
  ('8a65b567199ffff', NULL, NULL, 100)
ON CONFLICT (h3_index) DO NOTHING;
```

Lấy các giá trị cần dùng trong test case:

```sql
SELECT id, name, is_active FROM public.arenas ORDER BY name;          -- ghi lại id Landmark 81 = <LANDMARK_ID>
SELECT h3_index, arena_id, owner_university_id, shield_hp, updated_at
FROM public.h3_hexagons ORDER BY h3_index;                            -- ảnh chụp "trước"
SELECT short_code, total_season_km FROM public.universities ORDER BY short_code;
```

```bash
export LANDMARK_ID="<id Landmark 81>"
```

### 1.4. Dọn dẹp sau khi test

```sql
DELETE FROM public.h3_hexagons WHERE h3_index IN
  ('8a65b56718b7fff','8a65b5671d6ffff','8a65b5671d4ffff','8a65b5671897fff',
   '8a65b5671887fff','8a65b56718a7fff','8a65b567199ffff');
-- Nếu đã chạy TC-UI-05 / TC-UI-07:
DELETE FROM public.running_sessions WHERE user_id = (SELECT id FROM public.users WHERE email = 'tester01@uef.edu.vn');
-- Trả lại km cho UEF: trừ đi tổng distanceMeters/1000 đã gửi trong claim-loop (TC-UI-05 gửi 0.5 km)
UPDATE public.universities SET total_season_km = total_season_km - 0.5 WHERE short_code = 'UEF';
DELETE FROM public.users WHERE email = 'tester01@uef.edu.vn';
-- Nếu đã đổi is_active ở TC-ARN-04:
UPDATE public.arenas SET is_active = TRUE WHERE name = 'Khu Đô Thị Sala';
```

---

## 2. Bảng tổng hợp test case

| Mã | Loại | Nội dung | Mức |
|---|---|---|---|
| TC-API-01 | Happy | Lấy toàn bộ ô (không `arenaId`) | Cao |
| TC-API-02 | Happy | Lọc ô theo `arenaId` hợp lệ | Cao |
| TC-API-03 | Happy | Gọi không token / token rác vẫn 200 (API công khai) | TB |
| TC-API-04 | Edge | DB chưa có ô nào → `data: []` | TB |
| TC-API-05 | Failure | `arenaId` không phải UUID → 400 | Cao |
| TC-API-06 | Failure | `arenaId` rỗng (`?arenaId=`) → 400 | Thấp |
| TC-API-07 | Failure | `arenaId` đúng UUID nhưng không tồn tại → 404 `ERR_303` | Cao |
| TC-API-08 | Edge | `arenaId` của Đấu trường đã tắt → vẫn 200 | Thấp |
| TC-API-09 | Failure | Mất kết nối DB → 500, ẩn chi tiết | TB |
| TC-ARN-01 | Happy | Danh sách Đấu trường, `boundary` là GeoJSON | Cao |
| TC-ARN-02 | Happy | `hexCount` là số ô đếm thật | Cao |
| TC-ARN-03 | Happy | Không cần token | Thấp |
| TC-ARN-04 | Edge | Đấu trường `is_active = false` bị loại | TB |
| TC-ARN-05 | Failure | Sai method (`POST /arenas`) → 404 | Thấp |
| TC-SWG-01 | Happy | Swagger hiện đúng schema phản hồi | Thấp |
| TC-UI-01 | Edge | Chưa có ô → nhãn "Chưa có dữ liệu ô đất" | Cao |
| TC-UI-02 | Happy | Có dữ liệu → vẽ đúng 7 ô, đúng màu | Cao |
| TC-UI-03 | Happy | Kéo / zoom → ô bám đúng vị trí | TB |
| TC-UI-04 | Happy | Tải lại trang → giữ đúng trạng thái từ DB | TB |
| TC-UI-05 | Happy | Realtime: chiếm ô → đổi màu ngay ở mọi tab | Cao |
| TC-UI-06 | Edge | Sự kiện có ô không nằm trên bản đồ → không thêm ô lạ | TB |
| TC-UI-07 | Failure | `claim-loop` không token → 401, bản đồ không đổi | TB |
| TC-UI-08 | Failure | Backend tắt (timeout) → nhãn, không crash | Cao |
| TC-UI-09 | Failure | Mất mạng Internet → nền trống, ô vẫn hiện | Thấp |
| TC-AUTO-01 | Tự động | `npm test` backend | Cao |
| TC-AUTO-02 | Tự động | `flutter test` client | Cao |

---

## 3. Test case chi tiết: API `GET /api/v1/turf/hexagons`

Schema phản hồi thành công (dùng để verify mọi TC 200 bên dưới):

```text
{
  success: true                       (boolean)
  message: "Lấy trạng thái ô đất thành công."
  data: [                             (array)
    {
      h3Index: string (15 ký tự hex)
      arenaId: string(uuid) | null
      ownerUniversityId: string(uuid) | null
      universityCode: string | null    ("HUTECH", "UEF", ...)
      hexColor: string                 ("#RRGGBB" của trường, hoặc "#44FFFFFF" khi trung lập)
      shieldHp: number                 (0..100)
      lastPatrolledAt: string(ISO 8601)
    }
  ]
  timestamp: string(ISO 8601)
}
```

Schema phản hồi lỗi (do `AllExceptionsFilter` tạo):

```text
{ success: false, code: string, message: string|string[], timestamp: string, path: string }
```

### TC-API-01: Lấy toàn bộ ô

- **Pre:** đã nạp dữ liệu mẫu 1.3.
- **Bước:**

```bash
curl -s -i "http://localhost:3000/api/v1/turf/hexagons"
```

- **Expected:**
  - HTTP `200 OK`.
  - `success: true`; `data` có **7** phần tử (cộng thêm ô khác nếu DB đã có sẵn).
  - `8a65b56718b7fff`: `universityCode: "HUTECH"`, `hexColor: "#FFCC00"`, `arenaId: <LANDMARK_ID>`, `shieldHp: 100`.
  - `8a65b5671d6ffff`: `shieldHp: 80`.
  - `8a65b5671d4ffff`: `universityCode: "UEF"`, `hexColor: "#ED1C24"`.
  - 4 ô còn lại: `ownerUniversityId: null`, `universityCode: null`, `arenaId: null`, `hexColor: "#44FFFFFF"`.
- **Verify DB:** chạy lại câu `SELECT ... FROM h3_hexagons` ở 1.3, cột `updated_at` **không đổi** (API chỉ đọc).
- **Verify log:** console backend không có dòng `ERROR`.

### TC-API-02: Lọc theo `arenaId` hợp lệ

```bash
curl -s -i "http://localhost:3000/api/v1/turf/hexagons?arenaId=$LANDMARK_ID"
```

- **Expected:** `200`; `data` có **đúng 3** phần tử (`8a65b56718b7fff`, `8a65b5671d6ffff`, `8a65b5671d4ffff`), tất cả có `arenaId = <LANDMARK_ID>`. Không có ô trung lập nào.
- **Verify DB:** `SELECT count(*) FROM h3_hexagons WHERE arena_id = '<LANDMARK_ID>';` → 3, khớp số phần tử.

### TC-API-03: Không cần quyền

```bash
curl -s -o /dev/null -w "%{http_code}\n" "http://localhost:3000/api/v1/turf/hexagons"
```

```bash
curl -s -o /dev/null -w "%{http_code}\n" -H "Authorization: Bearer token-rac-khong-hop-le" "http://localhost:3000/api/v1/turf/hexagons"
```

- **Expected:** cả hai in `200`. Endpoint này không gắn `JwtAuthGuard`, nên token rác bị bỏ qua chứ không gây 401.

### TC-API-04: DB chưa có ô nào

- **Pre:** chạy SQL dọn dẹp ô ở 1.4 (hoặc test trước khi nạp 1.3).
- **Bước:** gọi lại lệnh của TC-API-01.
- **Expected:** `200`, `success: true`, `data: []` (mảng rỗng, **không phải** `null` hay lỗi).

### TC-API-05: `arenaId` không phải UUID

```bash
curl -s -i "http://localhost:3000/api/v1/turf/hexagons?arenaId=abc"
```

- **Expected:** `400 Bad Request`; body `success: false`, `code: "HTTP_400"`, `message` chứa `uuid is expected`, `path: "/api/v1/turf/hexagons?arenaId=abc"`.
- **Verify log:** **không** có dòng `ERROR` (lỗi 4xx không ghi log lỗi). Trước khi sửa, trường hợp này trả 500 do Postgres báo lỗi kiểu UUID.

### TC-API-06: `arenaId` rỗng

```bash
curl -s -i "http://localhost:3000/api/v1/turf/hexagons?arenaId="
```

- **Expected:** `400`, giống TC-API-05. `ParseUUIDPipe({ optional: true })` chỉ bỏ qua khi tham số **vắng mặt**; chuỗi rỗng vẫn bị kiểm và bị từ chối.
- **Ghi chú:** client Flutter không bao giờ gửi `arenaId=` rỗng (nó bỏ hẳn tham số), nên đây là hành vi chấp nhận được. Nếu bạn muốn chuỗi rỗng được coi như "lấy tất cả", báo để sửa.

### TC-API-07: `arenaId` không tồn tại

```bash
curl -s -i "http://localhost:3000/api/v1/turf/hexagons?arenaId=00000000-0000-4000-8000-000000000000"
```

- **Expected:** `404 Not Found`; `success: false`, `code: "ERR_303"`, `message: "ARENA_NOT_FOUND: Không tìm thấy Đấu trường."`.

### TC-API-08: Đấu trường đã tắt

- **Pre:** `UPDATE public.arenas SET is_active = FALSE WHERE name = 'Khu Đô Thị Sala';` và lấy id của Sala.
- **Bước:** `curl -s -i "http://localhost:3000/api/v1/turf/hexagons?arenaId=<SALA_ID>"`.
- **Expected:** `200`, `data: []`. Theo thiết kế hiện tại, API chỉ kiểm Đấu trường **có tồn tại**, không kiểm `is_active`.
- **Hậu kiểm:** bật lại `is_active = TRUE` (hoặc để dùng tiếp cho TC-ARN-04).

### TC-API-09: Mất kết nối database

- **Pre:** dừng backend, sửa tạm `backend/.env` cho sai mật khẩu DB (hoặc `docker stop` container Postgres nếu chạy local), rồi chạy lại backend. **Nhớ trả lại cấu hình sau khi test.**
- **Bước:** gọi lệnh của TC-API-01.
- **Expected:**
  - Nếu backend không khởi động được: TypeORM log lỗi kết nối và lặp lại việc thử kết nối; mọi request bị từ chối kết nối (curl báo `Failed to connect`).
  - Nếu DB rớt **sau** khi backend đã chạy: `500`, body `code: "HTTP_500"`, `message: "Đã xảy ra lỗi hệ thống nội bộ. Vui lòng thử lại sau."`. **Không** được lộ câu SQL, host DB hay stack trace.
- **Verify log:** console backend có dòng `ERROR [AllExceptionsFilter] [GET] /api/v1/turf/hexagons -> ...` với chi tiết lỗi thật (chi tiết chỉ nằm trong log, không trả cho client).

---

## 4. Test case chi tiết: API `GET /api/v1/turf/arenas`

Schema phản hồi thành công:

```text
{
  success: true
  message: "Lấy danh sách Đấu trường thành công."
  data: [
    {
      id: string(uuid)
      name: string
      description: string | null
      hexCount: number          (số dòng h3_hexagons có arena_id này)
      boundary: { type: "Polygon", coordinates: [[[lng, lat], ...]] } | null
    }
  ]
  timestamp: string
}
```

### TC-ARN-01: Danh sách Đấu trường và ranh giới GeoJSON

```bash
curl -s -i "http://localhost:3000/api/v1/turf/arenas"
```

- **Expected:**
  - `200`; `data` có các Đấu trường đang hoạt động (ít nhất 4 bản seed: Cụm Đại Học Bình Thạnh (Khu D2), Công Viên Landmark 81, Khu Đô Thị Sala, Khu Vực Bờ Kè Thanh Đa), **xếp theo tên A→Z**.
  - `boundary` là **object** `{ "type": "Polygon", "coordinates": [...] }`.
  - Toạ độ theo thứ tự `[kinh độ, vĩ độ]`: số đầu khoảng `106.7`, số sau khoảng `10.7`–`10.8`.
  - Vòng ranh giới khép kín: điểm đầu bằng điểm cuối.
- **Fail nếu:** `boundary` là chuỗi dạng `0103000020E6...` (WKB). Khi đó TypeORM chưa đọc cột `geometry` thành GeoJSON.
- **Verify DB:** `SELECT name, ST_AsGeoJSON(boundary_polygon) FROM arenas WHERE is_active;`, toạ độ khớp với API.

### TC-ARN-02: `hexCount` là số đếm thật

- **Pre:** đã nạp dữ liệu mẫu 1.3.
- **Bước:** gọi lại TC-ARN-01.
- **Expected:** Landmark 81 có `hexCount: 3`; các Đấu trường khác `hexCount: 0`. **Không** được trả `180`/`250`/`120`/`160` (số trong cột `total_hexes` của seed).
- **Verify DB:** `SELECT a.name, a.total_hexes, count(h.h3_index) FROM arenas a LEFT JOIN h3_hexagons h ON h.arena_id = a.id GROUP BY a.id;`, cột `count` khớp `hexCount`.

### TC-ARN-03: Không cần quyền

```bash
curl -s -o /dev/null -w "%{http_code}\n" -H "Authorization: Bearer token-rac" "http://localhost:3000/api/v1/turf/arenas"
```

- **Expected:** `200`.

### TC-ARN-04: Loại Đấu trường đã tắt

- **Pre:** `UPDATE public.arenas SET is_active = FALSE WHERE name = 'Khu Đô Thị Sala';`
- **Bước:** gọi lại TC-ARN-01.
- **Expected:** `200`, danh sách **không còn** "Khu Đô Thị Sala"; các Đấu trường khác vẫn đủ.
- **Hậu kiểm:** `UPDATE public.arenas SET is_active = TRUE WHERE name = 'Khu Đô Thị Sala';`, gọi lại thì Sala xuất hiện trở lại.

### TC-ARN-05: Sai method

```bash
curl -s -i -X POST "http://localhost:3000/api/v1/turf/arenas"
```

- **Expected:** `404`, `code: "HTTP_404"`, `message` dạng `Cannot POST /api/v1/turf/arenas`. Không tạo dòng nào trong `arenas`.

### TC-SWG-01: Schema Swagger

- **Bước:** mở `http://localhost:3000/docs`, mục **Turf**.
- **Expected:**
  - Có `GET /api/v1/turf/arenas` và `GET /api/v1/turf/hexagons`.
  - Response 200 của `/hexagons` trỏ tới `HexagonListResponseDto`, có thêm mô tả response 400 và 404 (`ERR_303`). Response 200 của `/arenas` trỏ tới `ArenaListResponseDto`.
  - Mục **Schemas** có `HexagonResponseDto` (7 trường như mục 3), `ArenaResponseDto` và `GeoJsonPolygonDto`.
  - Nút **Try it out** của cả hai API chạy được, cho kết quả giống cURL.

---

## 5. Test case chi tiết: Flutter `HexagonLayer`

Chuẩn bị chung: backend đang chạy, app mở bằng `flutter run -d chrome --web-port 5000`. Mở **DevTools của Chrome (F12)**, chuyển sang tab **Network** (lọc `turf` và `WS`) và tab **Console**.

Quy ước màu khi vẽ (nền OSM sáng):

| Loại ô | Màu tô | Viền |
|---|---|---|
| HUTECH | vàng `#FFCC00`, đậm 45% | xám mảnh |
| UEF | đỏ `#ED1C24`, đậm 45% | xám mảnh |
| Trung lập | trắng, đậm 35% | xám mảnh |

### TC-UI-01: Chưa có dữ liệu

- **Pre:** DB không có ô nào (chạy dọn dẹp ở 1.4).
- **Bước:** tải lại trang (`F5`).
- **Expected:**
  - Bản đồ OSM quanh khu D2 và Landmark 81, zoom 15.
  - Thanh `PercentDominanceBar` ở trên cùng.
  - Chip **"Chưa có dữ liệu ô đất"** ở giữa đáy.
  - Ghi nguồn "OpenStreetMap contributors" ở góc.
- **Verify Network:** `GET /api/v1/turf/hexagons` trả `200`, body `data: []`. Request **không có** tham số `arenaId`.
- **Verify Console:** không có lỗi đỏ, nhất là không có lỗi kiểu `h3 is not defined` (dấu hiệu thiếu script h3-js).

### TC-UI-02: Có dữ liệu, vẽ đúng ô

- **Pre:** đã nạp dữ liệu mẫu 1.3.
- **Bước:** tải lại trang.
- **Expected:**
  - Chip "Chưa có dữ liệu" biến mất.
  - Một cụm **7 lục giác** liền nhau ở giữa màn hình: 1 ô ở giữa và 6 ô bao quanh.
  - Đúng **2 ô vàng** (HUTECH), **1 ô đỏ** (UEF), **4 ô trắng mờ**.
- **Verify Network:** response `/hexagons` có 7 phần tử; đối chiếu `h3Index` có chủ với màu trên bản đồ.
- **Verify bằng mắt:** chiều rộng mỗi ô cỡ 130 m (cạnh khoảng 66 m ở res 10). Ô không bị méo, không lệch hẳn sang chỗ khác (dấu hiệu đảo lat/lng).

### TC-UI-03: Kéo và zoom

- **Bước:** kéo bản đồ theo các hướng; cuộn chuột zoom từ 13 tới 18; kéo cụm ô ra khỏi màn hình rồi kéo lại.
- **Expected:** ô luôn dính đúng vị trí trên nền; không nhấp nháy, không mất ô khi kéo lại. Không có request `/hexagons` mới khi kéo/zoom (dữ liệu chỉ tải một lần).
- **Verify Network:** số request `/hexagons` vẫn là **1** sau khi kéo/zoom.

### TC-UI-04: Tải lại giữ trạng thái

- **Pre:** đổi chủ một ô bằng SQL: `UPDATE public.h3_hexagons SET owner_university_id = (SELECT id FROM universities WHERE short_code='UEF') WHERE h3_index = '8a65b5671897fff';`
- **Bước:** tải lại trang.
- **Expected:** ô `8a65b5671897fff` chuyển từ trắng sang **đỏ UEF**. Đổi DB trực tiếp không phát sự kiện realtime, nên **phải tải lại** mới thấy; trước khi tải lại thì ô vẫn trắng.

### TC-UI-05: Realtime khi chiếm ô (`hex_claimed`)

- **Pre:**
  - Có `$TOKEN` (mục 1.2) và dữ liệu mẫu 1.3.
  - Mở **2 tab** `http://localhost:5000`, đặt cạnh nhau.
  - Ghi lại `total_season_km` của UEF.
- **Bước:** trong cửa sổ thứ ba (Git Bash), gửi yêu cầu chiếm 3 ô trung lập. Có kèm `arenaId` để ô không bị mất gán Đấu trường (xem lưu ý ở mục 7).

```bash
curl -s -i -X POST "http://localhost:3000/api/v1/turf/claim-loop" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d "{\"boundaryH3Indexes\":[\"8a65b56718a7fff\",\"8a65b567199ffff\",\"8a65b5671887fff\"],\"distanceMeters\":500,\"durationSeconds\":180,\"arenaId\":\"$LANDMARK_ID\"}"
```

- **Expected API:** `201 Created`; body có `success: true`, `claimedCount` ≥ 3, `claimedHexes` chứa 3 ô trên, `addedKm: 0.5`.
- **Expected UI:** ở **cả hai tab**, 3 ô đó chuyển sang **đỏ UEF trong khoảng 1 giây**, **không cần tải lại**. Các ô khác giữ nguyên màu.
- **Verify Network (tab WS):** kết nối `turf-ws` có một frame nhận dạng `42/turf-ws,["hex_claimed",{...}]`, trong đó có `universityCode: "UEF"` và `claimedHexes`.
- **Verify log backend:** có dòng `[Broadcast] Trường UEF đã chiếm N ô lục giác!`. Lúc mở mỗi tab có dòng `Client kết nối WebSocket: <id>`.
- **Verify DB:**

```sql
SELECT h3_index, owner_university_id, shield_hp, arena_id, last_patrolled_at
FROM h3_hexagons WHERE h3_index IN ('8a65b56718a7fff','8a65b567199ffff','8a65b5671887fff');
-- owner = id UEF, shield_hp = 100, last_patrolled_at = thời điểm vừa gọi, arena_id = LANDMARK_ID

SELECT session_type, distance_meters, duration_seconds, hex_count, is_valid
FROM running_sessions WHERE user_id = (SELECT id FROM users WHERE email = 'tester01@uef.edu.vn');
-- thêm 1 dòng: ARENA_LOOP, 500, 180, hex_count = claimedCount, is_valid = true

SELECT short_code, total_season_km FROM universities WHERE short_code = 'UEF';
-- tăng đúng 0.5 so với số đã ghi
```

- **Hậu kiểm:** tải lại một tab, 3 ô vẫn đỏ (đã lưu trong DB).

### TC-UI-06: Sự kiện có ô không nằm trên bản đồ

- **Ngữ cảnh:** `H3Service` hiện đảo lat/lng, nên `claimedHexes` có thể chứa thêm ô "bên trong vòng" nằm ở vị trí khác hẳn hoặc không có trong lần tải ban đầu.
- **Bước:** sau TC-UI-05, so `claimedCount` trong response với số ô đổi màu trên bản đồ.
- **Expected:** chỉ những ô **đã có trên bản đồ** đổi màu; **không xuất hiện ô mới** ở bất kỳ đâu (kéo bản đồ ra xa để kiểm). Không có lỗi trong Console.
- **Lưu ý:** nếu `claimedCount` > 3 thì backend đã tạo thêm dòng `h3_hexagons` mới. Tải lại trang thì các ô này mới hiện (nếu nằm trong khung nhìn). Đó là hành vi của Module 5 (DEV 1), không thuộc phạm vi test này.

### TC-UI-07: Chiếm ô khi không có token

```bash
curl -s -i -X POST "http://localhost:3000/api/v1/turf/claim-loop" -H "Content-Type: application/json" -d '{"boundaryH3Indexes":["8a65b5671897fff"],"distanceMeters":100,"durationSeconds":60}'
```

- **Expected:** `401 Unauthorized`, `success: false`, `code: "HTTP_401"`.
- **Expected UI:** không ô nào đổi màu; WS không nhận frame `hex_claimed`.
- **Verify DB:** `running_sessions` và `h3_hexagons` không đổi.

### TC-UI-08: Backend tắt (timeout / mất kết nối)

- **Bước:**
  1. Dừng backend (`Ctrl+C` ở terminal backend).
  2. Tải lại trang app.
  3. Chờ tối đa khoảng **10 giây**, bằng `connectTimeout` của Dio.
- **Expected:**
  - App **không crash**, không màn hình đỏ hay trắng.
  - Bản đồ nền vẫn hiện và chip "Chưa có dữ liệu ô đất" hiện ra.
- **Verify Network:** request `/hexagons` báo `failed` (`ERR_CONNECTION_REFUSED`).
- **Verify Console:** có thể có cảnh báo kết nối socket thất bại. Đây là hành vi chấp nhận được, chỉ cần không có exception của Flutter làm treo app.
- **Hậu kiểm:** bật lại backend, tải lại trang, ô hiện lại. App **không tự tải lại** khi backend sống lại; việc thử lại tự động chưa nằm trong phạm vi.

### TC-UI-09: Mất Internet (tile không tải được)

- **Bước:** DevTools → Network → chọn **Offline** (hoặc chặn domain `tile.openstreetmap.org` bằng *Block request domain*), rồi kéo bản đồ sang vùng chưa tải.
- **Expected:** vùng nền mới để trống hoặc xám, nhưng **lục giác vẫn vẽ** ở vùng đã có dữ liệu. App không crash.
- **Ghi chú:** chế độ Offline cũng chặn `localhost` trong một số phiên bản Chrome. Nếu ô biến mất ngay từ lần tải đầu thì dùng cách chặn domain thay vì Offline.

---

## 6. Test tự động (chạy trước khi test tay)

### TC-AUTO-01: Backend

```bash
cd backend && npm test
```

- **Expected:** `Tests: 17 passed, 17 total`. Riêng `turf.service.spec.ts` có 8 test (lọc theo Đấu trường, `ERR_303`, ô trung lập, `hexCount` đếm thật, loại Đấu trường đã tắt...).

### TC-AUTO-02: Client

```bash
flutter test
```

- **Expected:** `All tests passed!` (18 test). Gồm 11 test `MapStateNotifier` (tải ô, đọc màu, áp `hex_claimed`, bỏ ô lạ, payload sai, notifier đã huỷ) và 4 test `parseListPayload` (đọc `BaseResponseDto`, bỏ định dạng mảng thô cũ).
- Dòng `ClientException ... status 400` trong widget test là do `flutter test` chặn mạng nên không tải được tile; không làm test fail.

---

## 7. Lỗi đã biết và rủi ro khi test

| # | Hiện tượng | Ảnh hưởng tới test | Ghi chú |
|---|---|---|---|
| 1 | `claim-loop` ghi đè `arena_id = NULL` cho ô được chiếm nếu body **không** có `arenaId` | Sau TC-UI-05 mà quên `arenaId`, TC-API-02 và TC-ARN-02 sẽ đếm thiếu ô | Lỗi trong `TurfService.claimLoop` (Module 5). Nên mở ticket |
| 2 | `H3Service` đảo lat/lng khi tính ô bên trong vòng | `claimedCount` có thể khác 3; có thể sinh ô lạ | Đã ghi trên bản đồ wayfinder, thuộc DEV 1 |
| 3 | `hex_claimed` vẫn gửi `claimedBy` (email/tên) | Thấy trong frame WS ở TC-UI-05 | Hợp đồng #3 đã quyết bỏ, chưa sửa backend |
| 4 | `claim-loop` chưa đòi `sessionId` | TC-UI-05 gọi thẳng được | Theo hợp đồng #3 sẽ thêm sau |
| 5 | App không tự tải lại ô khi backend sống lại | TC-UI-08 phải tải lại tay | Ngoài phạm vi hiện tại |
| 6 | Tile OSM tạm thời (Carto cần API key) | Nền sáng, màu ô trung lập đậm hơn dự kiến | Chờ ticket #16 |

---

## 8. Biên bản kết quả

| Mã | Kết quả (Pass/Fail) | Ghi chú / ảnh chụp |
|---|---|---|
| TC-AUTO-01 | | |
| TC-AUTO-02 | | |
| TC-API-01 | | |
| TC-API-02 | | |
| TC-API-03 | | |
| TC-API-04 | | |
| TC-API-05 | | |
| TC-API-06 | | |
| TC-API-07 | | |
| TC-API-08 | | |
| TC-API-09 | | |
| TC-ARN-01 | | |
| TC-ARN-02 | | |
| TC-ARN-03 | | |
| TC-ARN-04 | | |
| TC-ARN-05 | | |
| TC-SWG-01 | | |
| TC-UI-01 | | |
| TC-UI-02 | | |
| TC-UI-03 | | |
| TC-UI-04 | | |
| TC-UI-05 | | |
| TC-UI-06 | | |
| TC-UI-07 | | |
| TC-UI-08 | | |
| TC-UI-09 | | |

Người test: ............ · Ngày: ............ · Commit/nhánh: ............
