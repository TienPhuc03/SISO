# SISO (STEP IN STEP OUT) — ĐẠI CHIẾN ĐẠI HỌC TP. HỒ CHÍ MINH
> **Ứng dụng Gamified Running & Chiếm Lãnh Thổ Liên Trường (Location-Based Turf War)**  
> **Đồ án Thực tế Công nghệ Phần mềm — Nhóm 2 Kỹ sư Full-stack**

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)](https://flutter.dev)
[![NestJS](https://img.shields.io/badge/NestJS-10.x-E0234E?logo=nestjs)](https://nestjs.com)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-15%20PostGIS-336791?logo=postgresql)](https://www.postgresql.org)
[![Supabase](https://img.shields.io/badge/Supabase-Cloud-3ECF8E?logo=supabase)](https://supabase.com)
[![Firebase](https://img.shields.io/badge/Firebase-Auth%20%2B%20FCM-FFCA28?logo=firebase)](https://firebase.google.com)
[![Uber H3](https://img.shields.io/badge/Uber%20H3-Res%2010-000000)](https://h3geo.org)

---

## 1. GIỚI THIỆU DỰ ÁN
**SISO (Step In Step Out)** là trò chơi chạy bộ chiếm lãnh thổ cho Sinh viên các trường đại học / cao đẳng ở TP.HCM. Thuật ngữ dùng thống nhất theo [`GLOSSARY.md`](GLOSSARY.md).
* **4 Cụm thi đấu:** các Trường xếp hạng riêng trong Cụm của mình: Thủ Đức (KĐT ĐHQG), Trung tâm, Bình Thạnh - Phú Nhuận - Gò Vấp, Khu Nam. Mỗi Trường là **một cơ sở**; danh mục gốc 51 cơ sở, Sinh viên tự thêm Trường chưa có (chờ admin duyệt).
* **Lưới lục giác Uber H3:** bản đồ chia thành Ô đất H3 Resolution 10 (~65 m).
* **13 Đấu trường:** vùng mở có ranh giới từ OpenStreetMap (KĐT Sala, Landmark 81, Bờ kè Thanh Đa, Vạn Phúc, Thủ Thiêm, Nguyễn Huệ, Phú Mỹ Hưng…), mỗi Đấu trường thuộc một Cụm. Chạy khép vòng trong Đấu trường cùng Cụm để Chiếm, Tuần tra hoặc Công phá Ô đất.
* **Anti-GIGO:** 4 Cổng kiểm định phía server (Danh tính, Động học, Sinh trắc FFT nhịp bước từ gia tốc kế 50 Hz, Hình học) chặn đi xe máy rà chậm và Fake GPS.
* **Bộ đếm song song:** Sức mạnh Tổng hợp = 50% % Lãnh thổ + 50% % Km trong Cụm; Chạy tự do ở bất kỳ đâu vẫn cộng Quỹ Km cho Trường.
* **Mùa giải:** kết thúc theo `end_date`, mỗi Cụm có một Quán quân vào Đại sảnh Danh vọng. Trường đã chọn khoá đến hết Mùa.
* **Diễn đàn:** Bài đăng có chữ, tối đa 4 ảnh, đính kèm Phiên chạy hợp lệ; Tym, bình luận, báo cáo.

---

## 2. KIẾN TRÚC HỆ THỐNG
**3 tầng độc lập**, server là nguồn sự thật duy nhất (client chỉ gửi telemetry thô, không chạm DB):
1. **Mobile Client:** **Flutter (Dart 3.x)** — `flutter_map`, `h3_flutter`, `sensors_plus`, `geolocator`, Riverpod, Dio, `socket_io_client`, Firebase Auth (đăng nhập Google) + FCM (nhắc Tuần tra). Thanh điều hướng: Bản đồ · Diễn đàn · **Chạy** · Xếp hạng · Hồ sơ.
2. **Backend:** **NestJS (TypeScript)** — module `auth`, `universities`, `telemetry`, `turf`, `realtime`, `leaderboard`, `forum`, `profile`, `notifications`, `admin`; Swagger OpenAPI, Socket.io Gateway `/turf-ws`.
3. **Database:** **Supabase (PostgreSQL 15 + PostGIS + pg_cron)**, Supabase Storage (ảnh Diễn đàn), Redis 7.
4. **Web admin** (`admin/`): Vite + React + TS — chống gian lận, bản đồ Lãnh thổ, thống kê, Mùa giải / Trường / Đấu trường / Sinh viên, báo cáo Diễn đàn. Xem [`admin/README.md`](admin/README.md).

---

## 3. YÊU CẦU MÔI TRƯỜNG (PREREQUISITES)
* **Node.js** `>= 20.x` và `npm >= 10.x`.
* **Flutter SDK** `>= 3.2.0` (Dart SDK `>= 3.2.0 < 4.0.0`).
* **Docker Desktop** (tuỳ chọn, chạy Postgres/PostGIS + Redis local).
* **Firebase project** (tuỳ chọn): bật đăng nhập Google và thông báo đẩy.

---

## 4. HƯỚNG DẪN CÀI ĐẶT & KHỞI CHẠY

### Bước 1: Cơ sở dữ liệu (Supabase)
1. Tạo Project trên [Supabase](https://supabase.com); vào **Database → Extensions** bật **`postgis`** và **`pg_cron`**.
2. **SQL Editor**: chạy toàn bộ [`backend/src/database/init_schema.sql`](backend/src/database/init_schema.sql) (tạo bảng, 4 Cụm, quận, 51 cơ sở, view xếp hạng, bảng Diễn đàn và bucket Storage `forum`).
3. Chạy riêng [`backend/src/database/season_automation.sql`](backend/src/database/season_automation.sql) (job `pg_cron`: đóng Mùa giải, Hao mòn 24h/48h, kết thúc Phiên bỏ dở; chạy lại được nhiều lần).
4. Nạp 13 Đấu trường và Ô đất H3 (sau khi cấu hình `backend/.env` ở Bước 2):
   ```bash
   cd backend
   npm run seed:hexagons              # xem trước
   npm run seed:hexagons -- --apply   # ghi vào DB, giữ chủ sở hữu / Độ bền hiện có
   ```

### Bước 2: Backend (NestJS)
```bash
cd backend
cp .env.example .env
npm install
npm run start:dev
```
Các biến trong `backend/.env` (xem chú thích trong `.env.example`):

| Biến | Ý nghĩa |
| :--- | :--- |
| `DATABASE_URL` hoặc `DB_HOST/PORT/USER/PASSWORD/NAME`, `DB_SSL` | Kết nối Postgres (Supabase cần `DB_SSL=true`) |
| `REDIS_HOST`, `REDIS_PORT` | Redis |
| `JWT_SECRET`, `JWT_EXPIRES_IN` | Ký JWT (mặc định 7 ngày) |
| `OTP_DEV_MODE`, `SMTP_*`, `MAIL_FROM` | `OTP_DEV_MODE=true`: OTP cố định `123456`, không gửi mail; `false`: gửi OTP qua SMTP |
| `GOOGLE_APPLICATION_CREDENTIALS` | File service account Firebase; bật đăng nhập Google và FCM. Để trống thì tắt cả hai (`ERR_110`) |
| `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` | Tải ảnh Diễn đàn; để trống thì chỉ đăng bài chữ (`ERR_114`) |
| `TELEMETRY_ALLOW_FAST_REPLAY` | Chỉ dùng khi dev: nhận Cửa sổ gửi nhanh hơn thời gian thật (mặc định chặn, `ERR_207`) |

* **Swagger:** [http://localhost:3000/docs](http://localhost:3000/docs)
* **WebSocket:** `ws://localhost:3000/turf-ws`
* Hoặc chạy local bằng Docker: `cd backend && docker-compose up -d` (Postgres/PostGIS + Redis + API, tự nạp `init_schema.sql`).

### Bước 3: Mobile App (Flutter)
Ở thư mục gốc repo:
```bash
cp .env.example .env
flutter pub get
flutter run -d chrome   # hoặc: flutter run (thiết bị / máy ảo)
```
`.env` của app:
```env
# Máy ảo Android: http://10.0.2.2:3000 | Chrome / iOS Simulator: http://localhost:3000
# Điện thoại thật cùng WiFi: http://<IP_MÁY_TÍNH>:3000
API_BASE_URL=http://localhost:3000
SOCKET_URL=http://localhost:3000/turf-ws
H3_RESOLUTION=10
CAMPUS_BOUNDARY=BINH_THANH
```
Đăng nhập Google và thông báo đẩy cần `android/app/google-services.json` / `ios/Runner/GoogleService-Info.plist` (hoặc các biến `FIREBASE_*` trong `.env.example`); thiếu thì app vẫn chạy bằng email + OTP.

### Bước 4 (tuỳ chọn): Web admin
```bash
cd admin
cp .env.example .env   # VITE_API_BASE_URL, mặc định http://localhost:3000
npm install
npm run dev            # http://localhost:5173
```
Cấp quyền admin bằng SQL theo [`admin/README.md`](admin/README.md).

---

## 5. HƯỚNG DẪN TEST & KỊCH BẢN DEMO

### 5.1. Unit test
```bash
cd backend && npm test   # Anti-GIGO, H3 Flood Fill, auth, Trường, Diễn đàn, admin...
cd .. && flutter test    # Kalman, Tạm dừng, chọn Trường, Bảng xếp hạng, Diễn đàn...
cd admin && npm test     # tự kiểm bản đồ Lãnh thổ
```

### 5.2. Kịch bản demo

#### 1. Đăng nhập & chọn Trường (Cổng Danh tính)
* Nhập **email bất kỳ** (vd. `@gmail.com`), OTP demo `123456` (khi `OTP_DEV_MODE=true`); hoặc bấm **"Tiếp tục với Google"**.
* Lần đầu đăng nhập: màn **chọn Trường**, tìm không dấu (vd. "kinh te", "hutech"); không thấy thì **Thêm Trường mới** (tên, tên viết tắt, quận → Cụm).
* Trường đã chọn khoá đến hết Mùa giải; sang Mùa mới được đổi cho tới Phiên chạy hợp lệ đầu tiên (nút "Đổi Trường" ở tab **Hồ sơ**).

#### 2. Chống đi xe máy (Cổng Sinh trắc FFT)
* **Chạy bộ thật:** 10–12 km/h, nhịp chân 150–160 bước/phút → Phiên chạy hợp lệ.
* **Kẹp điện thoại lên xe máy rà 12 km/h:** tốc độ GPS cao nhưng không có Nhịp bước chạy → Phiên bị loại `ERR_202 (VEHICLE_SPEED_MISMATCH)`.

#### 3. Tạm dừng & Chạy tự do
* Bấm Tạm dừng / Tiếp tục; đứng yên thì app Tự tạm dừng. Tạm dừng 25 phút app nhắc, 30 phút tự kết thúc.
* Kết thúc Phiên chạy → km hợp lệ cộng vào Quỹ Km; Bảng xếp hạng Cụm hiện Mùa, thời gian còn lại.

#### 4. Chiếm đất & Realtime
* Chạy khép vòng ở Đấu trường cùng Cụm → Ô đất bên trong đổi màu Trường; máy thứ hai thấy đổi màu qua WebSocket (< 300 ms). Đấu trường Cụm khác trả `ERR_306`.
* Lưu ý: app Flutter hiện chưa gọi `claim-loop` (mọi Phiên chạy kết thúc như Chạy tự do); thử bằng Swagger theo [`docs/test_swagger_module2.md`](docs/test_swagger_module2.md).

#### 5. Diễn đàn
* Tab **Diễn đàn**: đăng bài kèm ảnh và Phiên chạy, Tym, bình luận, báo cáo; admin xử lý báo cáo trên web admin.

#### 6. Phát lại log (khi mất GPS trong phòng bảo vệ)
* Màn Chạy → **"Nguồn dữ liệu" → "Phát lại log"**, chọn file `.jsonl` trong [`assets/telemetry_logs/`](assets/telemetry_logs/README.md). Nhấn giữ nút **"Chạy"** để mở màn Ghi log cảm biến.

---

## 6. TÀI LIỆU CHI TIẾT
* 📘 [Đặc tả Yêu cầu (SRS 4.0, ISO 29148)](docs/SRS_SISO_DA_CHIEN_BINH_THANH.md)
* 📗 [Thuật ngữ (GLOSSARY)](GLOSSARY.md) và [quyết định kiến trúc (ADR)](docs/adr/)
* 📕 [Sổ tay Kỹ thuật (Developer Handbook)](docs/DEVELOPER_HANDBOOK.md)
* 📅 [Kế hoạch phát triển (Timeline v3)](docs/SISO_Timeline_v3.md)
* 🛠️ [Web admin](admin/README.md)
