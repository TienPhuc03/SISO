# Hướng dẫn test Module 2 bằng Swagger

Bản này dùng Swagger UI thay cho cURL/Postman. Danh sách test case, SQL mẫu và cách verify DB vẫn lấy từ [test_plan_module2_map.md](test_plan_module2_map.md); ở đây chỉ hướng dẫn **thao tác trên Swagger** cho từng test case.

## 0. Tình trạng Swagger trong dự án (đã kiểm ngày 5/11/2026)

- Đã có sẵn: thư viện `@nestjs/swagger`, cấu hình trong `backend/src/main.ts` (`SwaggerModule.setup('docs', ...)`, có `addBearerAuth()`).
- Giao diện: `http://localhost:3000/docs`. Bản JSON OpenAPI: `http://localhost:3000/docs-json`.
- Các endpoint đang có: `auth/edu-login`, `auth/verify-otp`, `telemetry/verify`, **`turf/arenas`**, **`turf/hexagons`**, `turf/claim-loop`, `leaderboard/scores`, `leaderboard/hall-of-fame`.
- Schema đang có: `HexagonListResponseDto`, `HexagonResponseDto`, `ArenaListResponseDto`, `ArenaResponseDto`, `GeoJsonPolygonDto`, `ClaimLoopDto`, ...

Kết quả gọi thử trên Supabase thật lúc kiểm:

| Gọi | Kết quả |
|---|---|
| `GET /turf/arenas` | 200, **6** Đấu trường, `boundary` là GeoJSON `Polygon`, `hexCount = 0` |
| `GET /turf/hexagons` | 200, `data: []` (DB chưa có ô nào) |
| `GET /turf/hexagons?arenaId=abc` | 400, `HTTP_400`, `Validation failed (uuid is expected)` |
| `GET /turf/hexagons?arenaId=00000000-0000-4000-8000-000000000000` | 404, `ERR_303` |

> DB hiện có **6** Đấu trường chứ không phải 4: ngoài 4 bản seed còn 2 bản ghi cũ là "Khu Vực Bình Thạnh & Landmark 81" và "Khu Đô Thị Vạn Phúc". Ở TC-ARN-01 coi **6** là đúng.

## 1. Mở Swagger

1. Chạy backend:

   ```bash
   cd backend && npm run start:dev
   ```

2. Chờ terminal in `SISO API Server is running on: http://localhost:3000`.
3. Mở trình duyệt tới `http://localhost:3000/docs`.
4. Bấm mở nhóm **Turf**. Bạn sẽ thấy 3 dòng: `GET /api/v1/turf/arenas`, `GET /api/v1/turf/hexagons`, `POST /api/v1/turf/claim-loop`.

### Cách đọc kết quả trên Swagger

Sau khi bấm **Execute**, Swagger hiện 3 phần, theo thứ tự từ trên xuống:

- **Curl:** lệnh tương đương. Có thể copy để chạy lại, hoặc dán vào biên bản test.
- **Request URL:** địa chỉ thật đã gọi. Kiểm tham số `arenaId` đúng chưa.
- **Server response:**
  - **Code:** mã HTTP (200, 400, 404, ...).
  - **Response body:** JSON trả về.
  - **Response headers.**

Bên dưới là mục **Responses** (tài liệu, không phải kết quả thật): mô tả các mã có thể trả về và schema mẫu. Đừng nhầm phần này với kết quả.

## 2. Lấy token (chỉ cần cho phần chiếm ô)

Hai API `GET` là công khai, **không cần** token. Chỉ `POST /turf/claim-loop` cần token (TC-UI-05, TC-UI-07).

1. Nhóm **Auth**, mở `POST /api/v1/auth/edu-login`, bấm **Try it out**.
2. Sửa body thành:

   ```json
   { "email": "tester01@uef.edu.vn" }
   ```

3. Bấm **Execute**. Mong đợi Code `200` và message có `Demo OTP: 123456`.
4. Mở `POST /api/v1/auth/verify-otp`, chọn **Try it out**, body:

   ```json
   { "email": "tester01@uef.edu.vn", "otp": "123456" }
   ```

5. Bấm **Execute**. Mong đợi `200`; copy chuỗi `accessToken` trong Response body (không lấy dấu ngoặc kép).
6. Kéo lên đầu trang, bấm nút **Authorize** (biểu tượng ổ khoá). Dán token vào ô **Value**, bấm **Authorize**, rồi **Close**. Các endpoint có ổ khoá giờ sẽ tự gửi token.

Lưu ý:
- OTP hết hạn sau 5 phút và chỉ dùng một lần. Gọi `verify-otp` lần hai sẽ báo `ERR_AUTH_OTP_INVALID`; khi đó gọi lại `edu-login`.
- Lần đầu `verify-otp` tạo một dòng trong `users`. SQL xoá có ở mục 1.4 của test plan.
- Token được Swagger giữ đến khi bạn tải lại trang. Tải lại thì phải Authorize lại.

## 3. Chuẩn bị dữ liệu

Chạy SQL **mục 1.3** của [test_plan_module2_map.md](test_plan_module2_map.md) trong Supabase SQL Editor, để nạp 7 ô thử. Sau đó lấy `id` của Landmark 81 bằng Swagger:

1. `GET /api/v1/turf/arenas`, chọn **Try it out**, rồi **Execute**.
2. Trong Response body, tìm `"name": "Công Viên Landmark 81"` và copy `id` của nó. Gọi giá trị này là `<LANDMARK_ID>`.

> Có 2 Đấu trường cùng ranh giới Landmark 81 ("Công Viên Landmark 81" và "Khu Vực Bình Thạnh & Landmark 81"). SQL mẫu gán ô cho **"Công Viên Landmark 81"**, nên lấy đúng `id` của bản ghi này.

## 4. Test API `GET /api/v1/turf/hexagons`

Mở `GET /api/v1/turf/hexagons`, chọn **Try it out**. Swagger hiện ô nhập `arenaId` (không bắt buộc).

| Mã | Nhập vào ô `arenaId` | Mong đợi (Code + Response body) | Verify thêm |
|---|---|---|---|
| TC-API-04 | *(để trống, khi DB chưa có ô)* | `200`, `"success": true`, `"data": []` | Request URL **không** có `?arenaId` |
| TC-API-01 | *(để trống, đã nạp dữ liệu mẫu)* | `200`, `data` có **7** phần tử; ô `8a65b56718b7fff` có `"universityCode": "HUTECH"`, `"hexColor": "#FFCC00"`; 4 ô có `"ownerUniversityId": null`, `"hexColor": "#44FFFFFF"` | SQL `SELECT ... FROM h3_hexagons`: `updated_at` không đổi |
| TC-API-02 | `<LANDMARK_ID>` | `200`, `data` có **đúng 3** phần tử, mọi phần tử có `"arenaId"` = `<LANDMARK_ID>` | SQL đếm `arena_id = '<LANDMARK_ID>'` ra 3 |
| TC-API-05 | `abc` | `400`, `"code": "HTTP_400"`, `"message": "Validation failed (uuid is expected)"` | Terminal backend **không** có dòng `ERROR` |
| TC-API-07 | `00000000-0000-4000-8000-000000000000` | `404`, `"code": "ERR_303"`, `"message": "ARENA_NOT_FOUND: Không tìm thấy Đấu trường."` | |
| TC-API-08 | id của "Khu Đô Thị Sala" sau khi tắt bằng SQL `is_active = FALSE` | `200`, `"data": []` | Bật lại `is_active = TRUE` sau khi test |

Kiểm tra schema (cho TC-API-01): mỗi phần tử trong `data` phải có **đúng 7 trường**: `h3Index`, `arenaId`, `ownerUniversityId`, `universityCode`, `hexColor`, `shieldHp`, `lastPatrolledAt`. So với mục **Responses → 200 → Schema** ngay dưới nút Execute.

### Các case Swagger không làm được, dùng cURL

- **TC-API-06 (`?arenaId=` rỗng):** Swagger tự bỏ tham số khi ô trống, nên không gửi được chuỗi rỗng. Copy lệnh trong ô **Curl**, thêm `?arenaId=` vào cuối URL và chạy trong terminal. Mong đợi `400`.
- **TC-API-03 (token rác vẫn 200):** endpoint này không có ổ khoá nên Swagger không gửi token. Muốn thử token rác thì dùng lệnh cURL ở test plan. Hoặc **Authorize** bằng một chuỗi bất kỳ rồi gọi lại: vẫn `200`, vì endpoint không kiểm token.
- **TC-API-09 (mất DB):** đổi `backend/.env` như test plan, rồi gọi lại trên Swagger. Mong đợi `500` với `"message": "Đã xảy ra lỗi hệ thống nội bộ. Vui lòng thử lại sau."`, terminal backend có dòng `ERROR [AllExceptionsFilter]`.

## 5. Test API `GET /api/v1/turf/arenas`

Mở `GET /api/v1/turf/arenas`, chọn **Try it out**, rồi **Execute** (không có tham số).

| Mã | Chuẩn bị | Mong đợi | Verify thêm |
|---|---|---|---|
| TC-ARN-01 | Không | `200`, `data` có **6** Đấu trường, xếp tên A→Z (bắt đầu bằng "Công Viên Landmark 81", kết thúc bằng "Khu Vực Bờ Kè Thanh Đa"). Mỗi `boundary` có dạng `{"type": "Polygon", "coordinates": [[[106.7…, 10.7…], …]]}` | **Fail** nếu `boundary` là chuỗi `0103000020E6…`. Số đầu mỗi cặp toạ độ là kinh độ (~106.7) |
| TC-ARN-02 | Đã nạp dữ liệu mẫu 1.3 | "Công Viên Landmark 81" có `"hexCount": 3`, các Đấu trường khác `0` | Không được thấy 180/250/120/160 (số bịa trong `total_hexes`) |
| TC-ARN-04 | SQL: `UPDATE arenas SET is_active = FALSE WHERE name = 'Khu Đô Thị Sala';` | `200`, chỉ còn **5** Đấu trường, không có "Khu Đô Thị Sala" | Bật lại rồi Execute lần nữa, lại thấy 6 |
| TC-ARN-03 | Bấm **Authorize** với chuỗi bất kỳ | Vẫn `200` | |

TC-ARN-05 (`POST /arenas` → 404): Swagger chỉ liệt kê method đã khai báo, nên không gọi `POST /arenas` được. Dùng cURL trong test plan, hoặc bỏ qua vì đây là hành vi mặc định của NestJS.

## 6. Test `POST /api/v1/turf/claim-loop` (realtime, kết hợp app Flutter)

Phần này kiểm `HexagonLayer` đổi màu ngay khi có ô bị chiếm. Swagger dùng để **bắn sự kiện**, còn kết quả thì xem trên app.

**Chuẩn bị:**
1. Đã **Authorize** (mục 2).
2. Đã nạp dữ liệu mẫu và có `<LANDMARK_ID>`.
3. Chạy app (`flutter run -d chrome --web-port 5000`), mở thêm một tab `http://localhost:5000`. Cả hai tab hiện 7 ô.

**TC-UI-05: chiếm ô thành công**

1. Mở `POST /api/v1/turf/claim-loop`, chọn **Try it out**.
2. Body (thay `<LANDMARK_ID>`):

   ```json
   {
     "boundaryH3Indexes": ["8a65b56718a7fff", "8a65b567199ffff", "8a65b5671887fff"],
     "distanceMeters": 500,
     "durationSeconds": 180,
     "arenaId": "<LANDMARK_ID>"
   }
   ```

3. Bấm **Execute**.
4. **Mong đợi trên Swagger:** Code `201`, body có `"success": true`, `"claimedCount"` ≥ 3, `"addedKm": 0.5`.
5. **Mong đợi trên app:** ở cả hai tab, 3 ô đó chuyển sang **đỏ UEF** trong khoảng 1 giây mà không cần tải lại.
6. **Mong đợi ở terminal backend:** dòng `[Broadcast] Trường UEF đã chiếm N ô lục giác!`.
7. **Kiểm chéo bằng Swagger:** gọi lại `GET /turf/hexagons`, 3 ô đó giờ có `"universityCode": "UEF"`, `"shieldHp": 100`, `"arenaId": "<LANDMARK_ID>"`. Gọi lại `GET /turf/arenas`, Landmark 81 có `hexCount` = 6 (3 cũ + 3 mới), hoặc lớn hơn nếu `claimedCount` > 3.

> **Bắt buộc có `arenaId` trong body.** Nếu thiếu, code hiện tại ghi đè `arena_id = NULL` cho các ô được chiếm, khiến TC-API-02 và TC-ARN-02 đếm thiếu. Đây là lỗi đã biết số 1 trong test plan.

**TC-UI-07: chiếm ô khi chưa đăng nhập**

1. Bấm **Authorize**, rồi **Logout** để xoá token.
2. Gọi lại `claim-loop` với body bất kỳ hợp lệ.
3. **Mong đợi:** Code `401`, `"code": "HTTP_401"`. App không đổi màu ô nào.

**Thêm: body sai (kiểm `ValidationPipe`)**

| Body | Mong đợi |
|---|---|
| Thiếu `distanceMeters` | `400`, `HTTP_400`, message liệt kê lỗi `distanceMeters must be a number ...` |
| Thêm trường lạ, ví dụ `"hack": true` | `400`, message `property hack should not exist` (do `forbidNonWhitelisted`) |
| `boundaryH3Indexes` có 151 phần tử | `400`, `ERR_301` |

## 7. Kiểm schema tổng thể trên Swagger (TC-SWG-01)

1. Cuộn xuống cuối trang, mở mục **Schemas**.
2. Kiểm có `HexagonListResponseDto` (`success`, `message`, `timestamp`, `data` là mảng `HexagonResponseDto`) và `ArenaListResponseDto` (`data` là mảng `ArenaResponseDto`, có `boundary` kiểu `GeoJsonPolygonDto`).
3. Ở `GET /turf/hexagons`, mục **Responses** phải liệt kê `200`, `400` (`arenaId không phải UUID`) và `404` (`ERR_303`).

## 8. Mẹo khi test bằng Swagger

- Sau mỗi lần Execute, copy ô **Curl** dán vào cột "Ghi chú" của biên bản test để người khác chạy lại được.
- Swagger không tự xoá dữ liệu. Nhớ chạy SQL dọn dẹp ở mục 1.4 của test plan sau khi test xong.
- Ô `arenaId` có khoảng trắng thừa ở đầu hoặc cuối sẽ bị coi là sai UUID (400). Khi dán id nhớ kiểm lại.
- Mã `HTTP_xxx` nghĩa là lỗi chung của NestJS; mã `ERR_xxx` là lỗi nghiệp vụ SISO.

## 9. Khắc phục: `listen EADDRINUSE: address already in use :::3000`

**Nguyên nhân:** đã có một backend khác chạy trên cổng 3000, thường là một terminal cũ chưa tắt hoặc tiến trình chạy nền. Code không có lỗi gì. Khi gặp lỗi này, `nest start --watch` vẫn đứng chờ nhưng backend **không** phục vụ request.

**Cách xử lý (PowerShell):**

1. Xem tiến trình nào đang giữ cổng:

   ```powershell
   Get-NetTCPConnection -LocalPort 3000 -State Listen | ForEach-Object { Get-CimInstance Win32_Process -Filter "ProcessId=$($_.OwningProcess)" | Select-Object ProcessId, ParentProcessId, CommandLine }
   ```

2. Nếu `CommandLine` là `node ... siso\backend\dist\main`, đó là backend SISO cũ. Tắt nó cùng các tiến trình con (thay `<PID>` bằng `ProcessId` vừa thấy):

   ```powershell
   taskkill /PID <PID> /T /F
   ```

   Nếu đó là một ứng dụng khác thì **đừng tắt**. Thay vào đó đổi `PORT` trong `backend/.env` (ví dụ `PORT=3001`) và sửa `API_BASE_URL`, `SOCKET_URL` trong `.env` gốc theo cổng mới.

3. Ở terminal báo lỗi, bấm `Ctrl+C` rồi chạy lại `npm run start:dev`. Chờ dòng `SISO API Server is running on: http://localhost:3000`.

**Cách tránh:** chỉ chạy **một** terminal backend. Trước khi chạy, kiểm tra nhanh cổng còn trống không:

```powershell
Get-NetTCPConnection -LocalPort 3000 -State Listen -ErrorAction SilentlyContinue
```

Không in ra gì nghĩa là cổng đang trống.
