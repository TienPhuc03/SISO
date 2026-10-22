# SISO (STEP IN STEP OUT) — ĐẠI CHIẾN ĐẠI HỌC BÌNH THẠNH
> **Ứng dụng Gamified Running & Chiếm Lãnh Thổ Liên Trường (Location-Based Turf War)**  
> **Đồ án Thực tế Công nghệ Phần mềm — Nhóm 2 Kỹ sư Full-stack**

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)](https://flutter.dev)
[![NestJS](https://img.shields.io/badge/NestJS-10.x-E0234E?logo=nestjs)](https://nestjs.com)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-15%20PostGIS-336791?logo=postgresql)](https://www.postgresql.org)
[![Supabase](https://img.shields.io/badge/Supabase-Cloud-3ECF8E?logo=supabase)](https://supabase.com)
[![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker)](https://www.docker.com)
[![Uber H3](https://img.shields.io/badge/Uber%20H3-Res%2010-000000)](https://h3geo.org)

---

## 1. GIỚI THIỆU DỰ ÁN
**SISO (Step In Step Out)** là nền tảng thể thao điện tử đô thị (Location-Based Turf War) dành cho sinh viên 5 trường đại học tại Quận Bình Thạnh (HUTECH, UEF, UTH, FTU2, HIU). 
* **Lưới lục giác Uber H3:** Bản đồ thành phố được chia thành hàng triệu ô lục giác chuẩn Resolution 10 (~65m).
* **Chiếm đất khép vòng:** Sinh viên chạy khép kín các cung đường tại các Đấu trường mở (Sala, Vạn Phúc, Landmark 81, Bờ kè Thanh Đa) để nhuộm màu lãnh thổ cho trường mình.
* **Động cơ Anti-GIGO:** Tích hợp bộ lọc 4 tầng (Kalman + Phân tích phổ FFT nhịp bước chân từ cảm biến gia tốc $50\text{Hz}$) để ngăn chặn triệt để hành vi đi xe máy rà chậm 12km/h hoặc Fake GPS.
* **Bộ đếm Song song & Quỹ Km:** Sinh viên về quê vẫn có thể chạy đánh lẻ để kéo điểm % Km Thể Thao của trường lên bảng xếp hạng.

---

## 2. KIẾN TRÚC HỆ THỐNG
Dự án được xây dựng theo mô hình **3-Tier Architecture độc lập chuẩn Enterprise**:
1. **Frontend (Mobile Client):** Viết bằng **Flutter (Dart 3.x)**, sử dụng `flutter_map`, `h3_flutter`, `sensors_plus`, `Riverpod`, giao tiếp qua `Dio` và `Socket.io client`.
2. **Backend (Application Server):** Viết bằng **NestJS (TypeScript)** theo chuẩn Clean Architecture, tích hợp Swagger OpenAPI 3.0, WebSocket Gateway và thuật toán FFT Anti-GIGO.
3. **Database (Data Tier):** Lưu trữ trên **Supabase Cloud (PostgreSQL 15 + PostGIS)** và cache Redis 7.

---

## 3. YÊU CẦU MÔI TRƯỜNG (PREREQUISITES)
Trước khi bắt đầu, hãy đảm bảo máy tính của bạn đã cài đặt:
* **Node.js:** Phiên bản `>= 20.x` (khuyên dùng v24 LTS) và `npm >= 10.x`.
* **Flutter SDK:** Phiên bản `>= 3.2.0` (Dart SDK `>= 3.2.0 < 4.0.0`).
* **Docker Desktop:** (Tùy chọn nếu muốn chạy cụm Postgres & Redis local).
* **Git:** Quản lý mã nguồn.

---

## 4. HƯỚNG DẪN CÀI ĐẶT & KHỞI CHẠY HỆ THỐNG

### Bước 1: Khởi tạo Cơ sở Dữ liệu (Supabase Cloud)
1. Đăng nhập vào [Supabase Cloud](https://supabase.com) và tạo một Project mới (tên: `siso-binhthanh-prod`).
2. Vào **Database -> Extensions**: Bật 2 extension bắt buộc là **`postgis`** và **`pg_cron`**.
3. Vào **SQL Editor**: Sao chép toàn bộ nội dung file [`backend/src/database/init_schema.sql`](file:///d:/Workspace/ĐACNPM/siso_project/backend/src/database/init_schema.sql) dán vào và bấm **Run**. Script sẽ tự động tạo bảng và nạp sẵn 5 trường đại học cùng các đấu trường lớn.
4. Lấy thông tin kết nối tại **Project Settings -> Database**:
   * Host (ví dụ: `db.xxxxxxxxxxxx.supabase.co`)
   * Port: `5432`
   * User: `postgres`
   * Password: Mật khẩu bạn đã đặt khi tạo project.

---

### Bước 2: Cài đặt & Khởi chạy Backend (NestJS)
1. Mở terminal và chuyển vào thư mục `backend`:
   ```bash
   cd backend
   ```
2. Cấu hình biến môi trường:
   Sao chép `.env.example` thành `.env` và điền thông tin Supabase:
   ```bash
   cp .env.example .env
   ```
   *Kiểm tra file `.env` đã có:*
   ```env
   PORT=3000
   DB_HOST=db.xxxxxxxxxxxx.supabase.co
   DB_PORT=5432
   DB_USER=postgres
   DB_PASSWORD=your_supabase_password
   DB_NAME=postgres
   DB_SSL=true
   REDIS_HOST=localhost
   REDIS_PORT=6379
   JWT_SECRET=siso_super_secret_jwt_key_2026
   ```
3. Cài đặt các gói thư viện:
   ```bash
   npm install
   ```
4. Khởi chạy máy chủ ở chế độ phát triển:
   ```bash
   npm run start:dev
   ```
   * **Swagger API Documentation:** Mở trình duyệt tại [http://localhost:3000/docs](http://localhost:3000/docs)
   * **WebSocket TurfGateway:** Kết nối tại `ws://localhost:3000/turf-ws`

*(Hoặc nếu chạy hoàn toàn bằng Docker Compose local: `docker-compose up -d`)*.

---

### Bước 3: Cài đặt & Khởi chạy Mobile App (Flutter)
1. Mở terminal mới tại thư mục gốc của dự án:
   ```bash
   cd d:\Workspace\ĐACNPM\siso_project
   ```
2. Cấu hình biến môi trường cho Mobile:
   Kiểm tra file `.env` tại thư mục gốc:
   ```env
   # Nếu chạy máy ảo Android: http://10.0.2.2:3000
   # Nếu chạy Chrome hoặc iOS Simulator: http://localhost:3000
   # Nếu chạy trên điện thoại thật kết nối cùng WiFi: http://<IP_MÁY_TÍNH>:3000
   API_BASE_URL=http://localhost:3000
   SOCKET_URL=http://localhost:3000/turf-ws
   H3_RESOLUTION=10
   CAMPUS_BOUNDARY=BINH_THANH
   ```
3. Tải các dependencies của Flutter:
   ```bash
   flutter pub get
   ```
4. Khởi chạy ứng dụng:
   ```bash
   # Chạy trên trình duyệt Chrome (khuyên dùng để code nhanh UI)
   flutter run -d chrome

   # Hoặc chạy trên thiết bị di động
   flutter run
   ```

---

## 5. HƯỚNG DẪN TEST & KỊCH BẢN DEMO BẢO VỆ

### 5.1. Chạy Tự Động Toàn Bộ Unit Test
```bash
# Test logic Backend (FFT Anti-GIGO & H3 Flood Fill)
cd backend && npm test

# Test logic Client (Bộ lọc Kalman)
cd .. && flutter test
```

### 5.2. Tài Khoản & Kịch Bản Demo Trực Tiếp Trước Hội Đồng

#### 1. Đăng nhập Email Sinh viên (Tầng 0 - Identity Gate)
* Nhập email: `nguyenvana@hutech.edu.vn` (hoặc đuôi `@uef.edu.vn`, `@ut.edu.vn`, `@ftu.edu.vn`, `@hiu.vn`).
* Nhập mã OTP demo: `123456`.
* Giao diện app ngay lập tức chuyển sang theme màu cờ sắc áo của trường (HUTECH: Vàng - Xanh).

#### 2. Test Chống Đi Xe Máy (Tầng 2 - Biometric FFT Gate)
* **Trường hợp 1 (Chạy bộ thật):** Tốc độ 10–12 km/h, nhịp chân 150–160 bước/phút $\rightarrow$ Hệ thống ghi nhận phiên chạy sạch.
* **Trường hợp 2 (Kẹp điện thoại lên xe máy đi rà 12km/h):** Vận tốc GPS di chuyển nhưng biên độ dao động đứng nhỏ, tần số rung $> 8\text{Hz}$ $\rightarrow$ Hệ thống lập tức dừng phiên chạy, báo lỗi đỏ: `ERR_202 (VEHICLE_SPEED_MISMATCH)`.

#### 3. Test Chiếm Đất Khép Vòng Realtime
* Chạy khép 1 vòng lặp quanh Đấu trường $\rightarrow$ Toàn bộ các ô lục giác H3 bên trong đổi sang màu trường.
* Đồng thời kiểm tra trên chiếc điện thoại thứ 2 (của đối thủ): Bản đồ đổi màu trong vòng $< 300\text{ms}$ qua WebSocket.

#### 4. Chế độ Giả lập (Demo Simulator khi mất sóng GPS trong nhà)
* Nếu phòng bảo vệ đồ án bị che khuất vệ tinh, mở menu ẩn và chọn **"Phát lại Log Chạy Landmark 81"** để diễn tập mượt mà toàn bộ quy trình!

---

## 6. TÀI LIỆU CHI TIẾT
* 📘 [Đặc tả Yêu cầu Nghiệp vụ & Kiến trúc (SRS ISO 29148)](docs/SRS_SISO_DA_CHIEN_BINH_THANH.md)
* 📕 [Sổ tay Kỹ thuật & Hướng dẫn Lập trình (Developer Handbook)](docs/DEVELOPER_HANDBOOK.md)
* 📅 [Kế hoạch Phát triển 30 Ngày cho 2 Thành viên Full-stack](docs/TIMELINE_30_DAYS.md)
