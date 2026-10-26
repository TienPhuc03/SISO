# KẾ HOẠCH TRIỂN KHAI DỰ ÁN SISO TRONG 30 NGÀY (PHIÊN BẢN CHUẨN V2)
## PHÂN CHIA NHIỆM VỤ FULL-STACK & LỘ TRÌNH SOẠN THẢO BÁO CÁO ĐỒ ÁN
**Dự án:** SISO (Step In Step Out) — Đại Chiến Đại Học Bình Thạnh  
**Học phần:** Đồ án Thực tế Công nghệ Phần mềm (ĐACNPM)  
**Tiêu chuẩn Kiến trúc & Báo cáo:** Chuẩn Kỹ sư Phần mềm (Zero-Jank Flutter, Fail-Safe NestJS, ISO/IEC/IEEE 29148)  
**Quy mô nhân sự:** 2 Kỹ sư Full-stack (Dev 1 & Dev 2 cùng tham gia viết Backend, Frontend và viết Tài liệu Báo cáo)  
**Thời lượng:** 30 Ngày (6 Sprint × 5 Ngày)  
**Mục tiêu kép:** (1) Bàn giao ứng dụng chạy mượt mà, không lỗi; (2) Hoàn thành cuốn Báo cáo Đồ án chuẩn mực (đầy đủ Kiến trúc, Use Case, Class Diagram, Sequence Diagram, ERD).

---

## 1. NGUYÊN TẮC PHÂN CHIA CÔNG VIỆC & QUY CHUẨN BÁO CÁO

### 1.1. Nguyên tắc Lát cắt Chức năng (Vertical Slice Pairing)
* **Không chia tách máy móc BE/FE:** Cả 2 kỹ sư đều làm Full-stack. Khi nhận một module, lập trình viên sẽ làm trọn gói từ CSDL $\rightarrow$ NestJS API/WebSocket $\rightarrow$ Flutter UI/State $\rightarrow$ Unit test.
* **Tích hợp song song viết Docs mỗi ngày:** Tuyệt đối không để dồn việc viết báo cáo đến tuần cuối. Mỗi ngày, sau khi code xong tính năng nào, lập trình viên phải viết ngay nội dung thuyết minh và vẽ diagram tương ứng vào tập hồ sơ đồ án.

### 1.2. Các phần BẮT BUỘC KHÔNG ĐƯỢC LƯỢC BỎ trong Báo cáo Đồ án (Theo bài mẫu)
1. **Kiến trúc Hệ thống (System Architecture):** Mô hình 3 tầng (3-Tier: Flutter Client $\leftrightarrow$ NestJS Gateway $\leftrightarrow$ Supabase PostGIS + Redis) và Sơ đồ Package (Package Diagram).
2. **Lược đồ Use Case (Use Case Diagram & Descriptions):** Sơ đồ Use Case tổng thể và bảng đặc tả chi tiết 8 Use Case nghiệp vụ chính (Actor, Preconditions, Main Flow, Alternative Flow).
3. **Lược đồ Lớp (Class Diagram):** Bắt buộc phải có Class Diagram chi tiết cho 4 phân hệ lõi:
   * *(1) Phân hệ Xác thực & Định danh Sinh viên (Authentication)*
   * *(2) Phân hệ Thu thập Telemetry & Anti-GIGO (Kalman + FFT)*
   * *(3) Phân hệ Chiếm đất Khép vòng H3 & Realtime WebSocket (Turf War)*
   * *(4) Phân hệ Bộ đếm Song song & Tự động hóa Mùa giải (Leaderboard & Cron)*
4. **Lược đồ Tuần tự (Sequence Diagram):** Mỗi phân hệ có ít nhất 1 Sequence Diagram thể hiện tương tác thời gian thực giữa Client, Server và Database.
5. **Thiết kế CSDL (Database Design):** Sơ đồ ERD và Từ điển dữ liệu chi tiết (Data Dictionary).
6. **Tài liệu Kiểm thử & Báo cáo Thực nghiệm:** Bảng Test Cases (TC-01 đến TC-15) và Báo cáo kiểm thử thực địa chống xe máy (Field Test Report có hình ảnh/video).

---

## 2. MA TRẬN PHÂN CHIA TRÁCH NHIỆM (FULL-STACK & DOCS MATRIX)

```
┌──────────────────────────────────────────────┬──────────────────────────────────────────────┐
│ DEV 1 (Kỹ sư Full-stack 1)                   │ DEV 2 (Kỹ sư Full-stack 2)                   │
├──────────────────────────────────────────────┼──────────────────────────────────────────────┤
│ [CODE FULL-STACK]:                           │ [CODE FULL-STACK]:                           │
│ • Module 1: Định danh Edu & Auth JWT         │ • Module 2: Bản đồ H3 Res 10 & Sân đấu       │
│ • Module 3: Tầng 1 Kinematic Kalman Filter   │ • Module 4: Tầng 2 Biometric IMU 50Hz FFT    │
│ • Module 5: Tầng 3 Loop Capture & Flood Fill │ • Module 6: Realtime WebSocket Gateway       │
│ • Module 7: Dual-Metric Live HUD & Quỹ Km    │ • Module 8: Leaderboard, pg_cron & Decay     │
├──────────────────────────────────────────────┼──────────────────────────────────────────────┤
│ [VIẾT DOCS BÁO CÁO]:                         │ [VIẾT DOCS BÁO CÁO]:                         │
│ • Chương I: Tổng quan đề tài & Đối thủ       │ • Chương II: Quản lý dự án (WBS, Rủi ro)     │
│ • Chương III: Context Diagram, Use Case 1,3,5│ • Chương III: Use Case Diagram, Use Case 2,4 │
│ • Chương IV: Class & Sequence Diag Phân hệ 1,3│ • Chương IV: Kiến trúc 3-Tier, Package Diag   │
│ • Chương V: Báo cáo thực địa GIGO & Pin/FPS  │ • Chương IV: Class & Sequence Diag Phân hệ 2,4│
│ • Chương V: Bảng Test Cases TC-01 đến TC-08  │ • Chương IV: ERD & Data Dictionary chi tiết  │
│ • Tổng hợp bản thảo Báo cáo PDF hoàn chỉnh   │ • Thiết kế Slide thuyết trình & Video demo   │
└──────────────────────────────────────────────┴──────────────────────────────────────────────┘
```

---

## 3. BẢNG TIẾN ĐỘ CHI TIẾT 30 NGÀY (DAY-BY-DAY FULL-STACK & DOCS)

### SPRINT 1: NỀN TẢNG, ĐỊNH DANH & BẢN ĐỒ H3 (NGÀY 1 – NGÀY 7)

#### Ngày 1: Họp Kick-off, Khởi tạo Monorepo & Schema Chuẩn
* **Dev 1:**
  * `[Code]`: Khởi tạo Git repository, cấu trúc Monorepo (`backend/`, `lib/`), setup `.gitignore`, `.env.example`. Setup Flutter skeleton (Riverpod, Dio, Socket.io client).
  * `[Docs]`: Soạn thảo **Chương I: 1.1 Thông tin đề tài SISO & 1.2 Nhóm sinh viên thực hiện**.
  * `[Output]`: Khung dự án Flutter chạy được màn hình Splash đầu tiên. Mục I.1 hoàn thiện trên file Word.
* **Dev 2:**
  * `[Code]`: Tạo Project Supabase Cloud, bật extension `postgis`, `pg_cron`, `pgcrypto`. Chạy script DDL `init_schema.sql` tạo bảng `universities`, `arenas`, `users`. Đánh B-Tree index cho `h3_index`.
  * `[Docs]`: Soạn thảo **Chương I: 1.3 Bối cảnh thực tế tại Bình Thạnh & Ý nghĩa tên gọi SISO (Single Input Single Output vs GIGO)**.
  * `[Output]`: CSDL Supabase online 24/7 có sẵn 5 trường. Bản thảo mục I.3.

#### Ngày 2: Setup CI/CD iOS & Kiến Trúc Tổng Thể
* **Dev 1:**
  * `[Code]`: Viết workflow `.github/workflows/build_ios.yml` tự động build `Runner.ipa`. Cài thử app lên 2 iPhone bằng Sideloadly.
  * `[Docs]`: Soạn thảo **Chương I: 1.4 Phân tích đối thủ cạnh tranh (Ma trận so sánh Strava, UpRace, Pokemon GO và SISO)**.
  * `[Output]`: File `.ipa` cài đặt thành công trên iPhone thật. Bảng so sánh đối thủ hoàn thiện.
* **Dev 2:**
  * `[Code]`: Setup Swagger OpenAPI 3.0 trong NestJS (`/docs`), cấu hình TypeORM kết nối Supabase SSL Pooler qua IPv4 (`DATABASE_URL`). Tạo base response/error filter.
  * `[Docs]`: Soạn thảo **Chương IV: 4.1 Kiến trúc Hệ thống tổng thể (Vẽ System Architecture Diagram 3-Tier: Flutter $\leftrightarrow$ NestJS $\leftrightarrow$ Supabase PostGIS + Redis)**.
  * `[Output]`: Server NestJS chạy tại port 3000, Swagger hiển thị tại `/docs`. Sơ đồ kiến trúc 3 tầng vẽ xong trên Draw.io.

#### Ngày 3 – Ngày 4: [Module 1 - Dev 1] Phân Hệ Xác Thực Email Sinh Viên (@*.edu.vn)
* **Dev 1 (Phụ trách Module 1):**
  * `[Code]`: 
    * Backend: Viết `AuthModule`, `AuthService`, DTO kiểm tra đuôi domain 5 trường (`hutech.edu.vn`, `uef.edu.vn`, `ut.edu.vn`, `ftu.edu.vn`, `hiu.vn`), cấp mã OTP và JWT token hạn 7 ngày.
    * Frontend: Thiết kế `LoginScreen` và `VerifyScreen`, kết nối `AuthRepository` qua `ApiClient`, lưu JWT vào `flutter_secure_storage`.
  * `[Docs]`: 
    * Soạn **Chương III: 3.1 Sơ đồ Ngữ cảnh (Context Diagram) & 3.3.1 Đặc tả Use Case UC-01 (Đăng nhập Email Sinh viên)**.
    * Vẽ **Chương IV: 4.4.1 Phân hệ Xác thực: Lược đồ Lớp (Class Diagram) & Lược đồ Tuần tự (Sequence Diagram)**.
  * `[Output]`: Đăng nhập sinh viên chạy hoàn chỉnh end-to-end. Class Diagram và Sequence Diagram Module 1 xuất file PNG.
* **Dev 2 (Hỗ trợ & Soạn Docs):**
  * `[Code]`: Kiểm thử API Auth trên Swagger UI, viết Jest unit test cho hàm validate domain trường.
  * `[Docs]`: Soạn thảo **Chương II: 2.1 Bảng phân rã công việc (WBS) & 2.2 Ước lượng công sức (Man-hours)**.
  * `[Output]`: File test `auth.service.spec.ts` pass 100%. Bảng WBS hoàn thiện trong báo cáo.

#### Ngày 5 – Ngày 6: [Module 2 - Dev 2] Bản Đồ Lục Giác Uber H3 & Sân Đấu Bình Thạnh
* **Dev 2 (Phụ trách Module 2):**
  * `[Code]`: 
    * Backend: Viết `TurfController` và API `GET /api/v1/turf/hexagons?arenaId=...` truy vấn các ô đất từ bảng `h3_hexagons`. Nạp ranh giới các Đấu trường (Sala, Landmark 81, Bờ kè Thanh Đa).
    * Frontend: Tích hợp `flutter_map` CartoDB, thư viện `h3_flutter`. Viết widget `HexagonLayer`. Đưa tác vụ chuyển đổi tọa độ GPS sang H3 Res 10 vào **Dart Isolate** để giữ 60 FPS không đơ UI.
  * `[Docs]`: 
    * Soạn **Chương III: 3.2 Sơ đồ Use Case tổng thể (Use Case Diagram) & 3.3.2 Đặc tả Use Case UC-02 (Xem Bản đồ Lãnh thổ H3)**.
    * Vẽ **Chương IV: 4.4.2 Phân hệ Bản đồ: Lược đồ Lớp (Class Diagram) & Lược đồ Tuần tự (Sequence Diagram)**.
  * `[Output]`: Bản đồ hiển thị lưới lục giác H3 mượt mà. Lược đồ Use Case tổng thể và Class Diagram Module 2 hoàn tất.
* **Dev 1 (Hỗ trợ & Soạn Docs):**
  * `[Code]`: Viết hàm tự động căn giữa camera bản đồ theo vị trí GPS của người dùng.
  * `[Docs]`: Soạn thảo **Chương II: 2.3 Quản lý rủi ro kỹ thuật (GPS dội sóng nhà cao tầng, pin, nhiệt độ thiết bị)**.
  * `[Output]`: Bảng quản lý rủi ro và phương án giảm thiểu trong Chương II.

#### Ngày 7: [Milestone 1 - Nghiệm thu Sơ bộ & Review Docs Tuần 1]
* **Cả 2 Dev:**
  * `[Code]`: Ghép nối toàn bộ: Mở app $\rightarrow$ Đăng nhập email trường $\rightarrow$ Mở bản đồ hiển thị lưới ô đất của trường. Đo kiểm bằng Flutter DevTools đảm bảo đạt 55-60 FPS khi render 500 ô lục giác.
  * `[Docs]`: Review chéo toàn bộ nội dung đã viết trong tuần. Hợp nhất thành bản thảo **Chương I và Chương II** hoàn chỉnh.
  * `[Deliverable]`: File báo cáo sơ bộ 15 trang đầu tiên + Mã nguồn nhánh `develop` sạch sẽ.

---

### SPRINT 2: THU THẬP TELEMETRY & ĐỘNG CƠ CHỐNG GIAN LẬN ANTI-GIGO (NGÀY 8 – NGÀY 14)

#### Ngày 8 – Ngày 9: [Module 3 - Dev 1] Tầng 1 Kinematic Gate (Bộ Lọc Kalman 2D)
* **Dev 1 (Phụ trách Module 3):**
  * `[Code]`: 
    * Frontend: Cấu hình `CoreLocation` & `CoreMotion` trên iOS. Xây dựng `LocationService` đọc GPS 1s/lần, `SensorDataSource` đọc IMU $50\text{Hz}$. Viết **Isolate Kalman Filter** khử nhiễu dội sóng và chặn tức thời vận tốc $v > 9.0\text{ m/s}$ ($>32\text{ km/h}$).
    * Backend: Viết endpoint `POST /api/v1/telemetry/verify`, hàm `validateKinematics` kiểm tra cờ Mock GPS (`ERR_201`) và sai số vệ tinh $> 20\text{m}$ (`ERR_203`).
  * `[Docs]`: 
    * Soạn **Chương III: 3.3.3 Đặc tả Use Case UC-03 (Giám sát phiên chạy & Lọc Kinematic)**.
    * Vẽ **Chương IV: 4.4.3 Phân hệ Thu thập Telemetry: Lược đồ Lớp (Class Diagram) & Lược đồ Tuần tự (Sequence Diagram)**.
  * `[Output]`: Luồng GPS sạch được lọc mượt mà trên client. Diagram Class/Sequence phân hệ Telemetry.
* **Dev 2 (Hỗ trợ & Soạn Docs):**
  * `[Code]`: Thiết kế DTO `TelemetryPayloadDto` xác thực mảng mẫu gia tốc kèm chữ ký HMAC-SHA256.
  * `[Docs]`: Soạn **Chương IV: 4.3 Thiết kế CSDL chi tiết (Bảng Data Dictionary cho `universities`, `arenas`, `users`)**.
  * `[Output]`: Từ điển dữ liệu 3 bảng đầu tiên theo đúng format mẫu.

#### Ngày 10 – Ngày 12: [Module 4 - Dev 2] Tầng 2 Biometric Gate (DSP & FFT Chống Xe Máy)
* **Dev 2 (Phụ trách Module 4):**
  * `[Code]`: 
    * Frontend: Đọc gia tốc $50\text{Hz}$ đóng gói vào Sliding Window 250 mẫu (`Float32List`). Viết màn hình `ActiveRunScreen` và widget `SpeedCadenceHud` hiển thị tốc độ km/h và nhịp bước chân SPM thời gian thực.
    * Backend: Xây dựng `AntiGigoService` thực hiện biến đổi Fourier (FFT) trên mảng gia tốc, tìm Peak Frequency. Thuật toán từ chối xe máy: Vận tốc $\ge 2.5\text{ m/s}$ nhưng nhịp bước $< 120\text{ SPM}$ hoặc biên độ đứng $< 0.2G \rightarrow$ Ném mã lỗi `ERR_202`.
  * `[Docs]`: 
    * Soạn **Chương III: 3.3.4 Đặc tả Use Case UC-04 (Kiểm định Anti-GIGO FFT chống xe máy)**.
    * Soạn **Chương IV: 4.4.4 Thuật toán Biometric FFT: Công thức toán học $A_{\text{mag}}$, Zero-Crossing Rate và Lược đồ Lớp (Class Diagram)**.
  * `[Output]`: Backend phân tích FFT chuẩn xác, giao diện HUD hiển thị cadence trực quan. Mục thuyết minh thuật toán FFT chi tiết.
* **Dev 1 (Hỗ trợ & Soạn Docs):**
  * `[Code]`: Thu thập mẫu gia tốc chạy bộ thật và mẫu đi xe máy để viết bộ test Jest (`anti-gigo.service.spec.ts`).
  * `[Docs]`: Soạn **Chương III: 3.5 Bảng chức năng ngầm phi giao diện (Non-screen Functions: Sensor Fusion, Kalman Isolate, FFT Engine)**.
  * `[Output]`: Bảng chức năng ngầm chuẩn mực theo mẫu mục 3.1.4 của bài báo cáo mẫu.

#### Ngày 13 – Ngày 14: [Milestone 2 - Test GIGO Thực Địa & Viết Báo Cáo Thực Nghiệm]
* **Cả 2 Dev ra hiện trường (Đường D2 & Bờ kè Thanh Đa):**
  * `[Thực địa]`: Dev 1 chạy bộ thật 1km quanh sân trường (hệ thống duyệt thành công, nhịp chân 155 SPM). Dev 2 kẹp điện thoại lên xe máy chạy rà rà 12km/h (hệ thống báo còi đỏ `ERR_202`, hủy phiên chạy).
  * `[Quay phim/Chụp ảnh]`: Ghi lại màn hình app hiển thị còi đỏ vi phạm và đồ thị phổ dao động làm bằng chứng.
  * `[Docs]`: Cùng soạn **Chương V: 5.3 Báo cáo Kết quả Kiểm thử Thực địa Chống Xe máy (Bảng số liệu đối soát GPS vs SPM, biểu đồ phổ tần số và hình ảnh thực nghiệm)**.
  * `[Deliverable]`: Video bằng chứng GIGO + Chương V phần thực nghiệm hoàn thành.

---

### SPRINT 3: TẦNG 3 TOPOLOGY & REALTIME WEBSOCKET (NGÀY 15 – NGÀY 21)

#### Ngày 15 – Ngày 17: [Module 5 - Dev 1] Thuật Toán Bounded Flood Fill H3 Chiếm Đất
* **Dev 1 (Phụ trách Module 5):**
  * `[Code]`: 
    * Frontend: Cài đặt giải thuật phát hiện chu trình kín (Loop Detection) trên client khi tọa độ cắt ngang vệt chạy cũ trong bán kính 20m. Trích xuất mảng mã H3 đường biên.
    * Backend: Viết `H3Service` áp dụng thuật toán Loang có biên (Bounded Flood Fill `polygonToCells`) tính toán các ô H3 lõi bên trong. Đặt trần an toàn giới hạn tối đa 150 ô (`ERR_301`). Thực hiện `UPSERT` vào bảng `h3_hexagons`.
  * `[Docs]`: 
    * Soạn **Chương III: 3.3.5 Đặc tả Use Case UC-05 (Bao vây và Chiếm đất Khép vòng H3)**.
    * Vẽ **Chương IV: 4.4.5 Phân hệ Chiếm đất: Lược đồ Lớp (Class Diagram) & Lược đồ Tuần tự (Sequence Diagram)**.
    * Soạn phần giải thuật toán Loang đa giác H3 với độ phức tạp $O(N)$.
  * `[Output]`: Tính năng khép vòng chiếm đất hoạt động chính xác. Diagram Class/Sequence phân hệ chiếm đất.
* **Dev 2 (Hỗ trợ & Soạn Docs):**
  * `[Code]`: Viết unit test cho `H3Service` kiểm tra các trường hợp biên (vòng lặp quá 150 ô, đa giác tự cắt).
  * `[Docs]`: Soạn **Chương IV: 4.3 Data Dictionary cho bảng `h3_hexagons` và `running_sessions`**.
  * `[Output]`: Test case unit test pass. Từ điển dữ liệu bảng ô lục giác và phiên chạy.

#### Ngày 18 – Ngày 20: [Module 6 - Dev 2] Đồng Bộ Realtime Đổi Màu Bản Đồ (WebSocket)
* **Dev 2 (Phụ trách Module 6):**
  * `[Code]`: 
    * Backend: Viết `TurfGateway` sử dụng WebSocket (Socket.io `/turf-ws`). Khi chiếm đất thành công, phát broadcast sự kiện `hex_claimed` gửi mã trường và mảng ô đất tới toàn bộ client.
    * Frontend: Viết `SocketManager` trên Flutter lắng nghe `hex_claimed`, kích hoạt Pulse Animation đổi màu các ô lục giác trên bản đồ đối thủ trong $< 300\text{ms}$.
  * `[Docs]`: 
    * Soạn **Chương IV: 4.2 Sơ đồ Package (Package Diagram cho Backend NestJS và Frontend Flutter)** theo mẫu mục IV.1.2.
    * Vẽ **Chương IV: 4.4.6 Phân hệ Realtime: Lược đồ Lớp (Class Diagram) & Lược đồ Tuần tự (Sequence Diagram cho luồng Broadcast sự kiện)**.
  * `[Output]`: Đồng bộ đổi màu bản đồ theo thời gian thực cực nhanh. Sơ đồ Package và Class Diagram Realtime.
* **Dev 1 (Hỗ trợ & Soạn Docs):**
  * `[Code]`: Tối ưu `RepaintBoundary` trên Flutter chỉ vẽ lại layer lục giác, không re-render bản đồ nền.
  * `[Docs]`: Soạn thảo **Chương III: 3.4 Sơ đồ Luồng Màn hình (Screen Flow Diagram) & Bảng phân quyền màn hình (Screen Authorization)**.
  * `[Output]`: Sơ đồ luồng màn hình ứng dụng di động hoàn chỉnh theo mẫu mục III.3.1.1.

#### Ngày 21: [Milestone 3 - Nghiệm thu Turf War & Review Docs Tuần 3]
* **Cả 2 Dev:**
  * `[Code]`: Test thực tế chạy khép vòng thật quanh trường HUTECH/UEF $\rightarrow$ Máy đối thủ đổi màu tức thì.
  * `[Docs]`: Rà soát và ráp nối toàn bộ **Chương III (SRS) và phần lớn Chương IV (SDD)**. Đảm bảo toàn bộ Use Case, Class Diagram và Sequence Diagram đã được đưa vào tài liệu.
  * `[Deliverable]`: Ứng dụng chạy mượt tính năng Turf War + Bản thảo báo cáo đạt 60% tiến độ (khoảng 40 trang).

---

### SPRINT 4: BỘ ĐẾM SONG SONG, KM ĐÁNH LẺ & RESET THÁNG (NGÀY 22 – NGÀY 26)

#### Ngày 22 – Ngày 23: [Module 7 - Dev 1] Bộ Đếm % Song Song & Quỹ Km Về Quê
* **Dev 1 (Phụ trách Module 7):**
  * `[Code]`: 
    * Backend & DB: Viết SQL View `v_campus_live_scores` tự động tính 3 thước đo (% Đất, % Km toàn cầu, % Sức mạnh tổng hợp $50\% - 50\%$). Viết API `POST /api/v1/turf/free-run` ghi nhận km chạy ở quê.
    * Frontend: Thiết kế widget **Dual-Metric Live HUD** gắn trên đỉnh bản đồ. Hiển thị thông báo cống hiến km khi chạy ngoài đấu trường.
  * `[Docs]`: 
    * Soạn **Chương III: 3.3.6 Đặc tả Use Case UC-06 (Chạy tự do đóng góp Km khi về quê) & UC-07 (Xem Live HUD % song song)**.
    * Vẽ **Chương IV: 4.4.7 Phân hệ Leaderboard & Quỹ Km: Lược đồ Lớp (Class Diagram) & Lược đồ Tuần tự (Sequence Diagram)**.
  * `[Output]`: Bộ đếm % hoạt động chính xác. Lược đồ Class và Sequence phân hệ điểm số.
* **Dev 2 (Hỗ trợ & Soạn Docs):**
  * `[Code]`: Kiểm tra và chống lỗi chia cho 0 (`NULLIF(total_km, 0)`) trong câu lệnh SQL View.
  * `[Docs]`: Soạn **Chương III: 3.6 Các Yêu cầu Phi Chức năng (NFR: NFR-01 Pin, NFR-02 FPS, NFR-03 Chịu lỗi mất sóng, NFR-04 Độ trễ)**.
  * `[Output]`: Bảng đặc tả 5 NFR định lượng rõ ràng.

#### Ngày 24 – Ngày 25: [Module 8 - Dev 2] Bảng Xếp Hạng Mùa Giải & Tự Động Hóa `pg_cron`
* **Dev 2 (Phụ trách Module 8):**
  * `[Code]`: 
    * Backend & DB: Viết `LeaderboardModule` (`GET /api/v1/leaderboard/scores` và `/hall-of-fame`). Cài đặt `pg_cron` trong PostgreSQL: Đúng 00:00:00 ngày đầu tháng reset đất về `NULL`, reset km về 0, lưu Quán quân vào `hall_of_fame`. Viết job decay giảm 50% HP đất sau 24h.
    * Frontend: Thiết kế `LeaderboardScreen` và `HallOfFameCard`. Đổi độ mờ (opacity) của ô đất theo độ bền `shield_hp`.
  * `[Docs]`: 
    * Soạn **Chương III: 3.3.8 Đặc tả Use Case UC-08 (Tự động Reset mùa giải 30 ngày & Hao mòn đất 48h)**.
    * Vẽ **Chương IV: 4.4.8 Phân hệ Mùa giải: Lược đồ Lớp (Class Diagram) & Lược đồ Tuần tự (Sequence Diagram)**.
    * Soạn Data Dictionary cho bảng `seasons` và `hall_of_fame`.
  * `[Output]`: Hệ thống mùa giải tự động hóa 100%. Đầy đủ Class/Sequence Diagram của tất cả các phân hệ.
* **Dev 1 (Hỗ trợ & Soạn Docs):**
  * `[Code]`: Thêm bộ lọc xem bảng xếp hạng theo từng trường và cá nhân đóng góp nhiều km nhất.
  * `[Docs]`: Soạn **Chương V: 5.1 Chiến lược kiểm thử & 5.2 Xây dựng Bảng Test Cases chi tiết (TC-01 đến TC-15)** theo đúng bảng mẫu mục V.4 của bài mẫu.
  * `[Output]`: Bảng 15 test cases chi tiết bao phủ toàn bộ use case.

#### Ngày 26: [Milestone 4 - Nghiệm thu Toàn diện & Load Test]
* **Cả 2 Dev:**
  * `[Code]`: Test ép xung tải nhẹ (500 CCU bằng k6/artillery). Chạy thử nghiệm kích hoạt trigger `pg_cron` reset tháng thành công.
  * `[Docs]`: Tổng hợp và rà soát kỹ thuật toàn bộ **Chương IV (Thiết kế phần mềm) và Chương V (Kiểm thử)**.
  * `[Deliverable]`: Ứng dụng hoàn thiện 100% tính năng + Bản thảo báo cáo đạt 85% tiến độ (khoảng 60 trang).

---

### SPRINT 5: ALPHA TEST, TỔNG DUYỆT & ĐÓNG GÓI BÁO CÁO (NGÀY 27 – NGÀY 30)

#### Ngày 27: Phát Hành Bản Cài Đặt & Khởi Động Alpha Test
* **Cả 2 Dev:**
  * `[Code]`: Xuất bản file `Runner.ipa` (cho iOS) và file `app-release.apk` (cho Android). Gửi link cài đặt cho 20–30 bạn bè sinh viên chạy thử nghiệm tại Landmark 81 và khu D2.
  * `[Docs]`: 
    * Dev 1: Biên soạn **Chương VI: 6.1 Yêu cầu cấu hình hệ thống & 6.2 Hướng dẫn cài đặt Backend NestJS, CSDL Supabase, Mobile Flutter**.
    * Dev 2: Biên soạn **Chương VI: 6.3 Hướng dẫn nạp file `.ipa` lên iPhone bằng Sideloadly (0 đồng) & Kịch bản chạy Demo Simulator**.
  * `[Output]`: 30 tester bắt đầu chạy thực tế. Chương VI hoàn thành 100%.

#### Ngày 28: Thu Thập Telemetry & Hoàn Thiện Báo Cáo Đo Đạc NFR
* **Dev 1:**
  * `[Test]`: Dùng Xcode Instruments / Android Profiler đo mức tiêu hao pin thực tế (xác nhận $\le 7\%$ cho 30 phút chạy) và Frame rate (đạt ổn định $\ge 58\text{ FPS}$).
  * `[Docs]`: Đưa biểu đồ đo pin, CPU, RAM và FPS thực tế vào **Chương V: 5.4 Báo cáo đo đạc chỉ số phi chức năng NFR**. Định dạng chuẩn phông chữ, canh lề, mục lục tự động cho file Báo cáo đồ án.
* **Dev 2:**
  * `[Test]`: Kiểm tra telemetry trên Supabase: số km sinh viên đã chạy, số ô H3 đã chiếm, kiểm tra log phát hiện xe máy.
  * `[Docs]`: Thiết kế bộ slide thuyết trình bảo vệ đồ án (20–25 slide tóm tắt cô đọng: Problem $\rightarrow$ Solution $\rightarrow$ 3-Tier Architecture $\rightarrow$ Anti-GIGO Engine $\rightarrow$ Demo Video).
* **Output Ngày 28:** Bản thảo báo cáo đồ án hoàn chỉnh $100\%$ nội dung (khoảng 70–80 trang chuẩn ISO 29148).

#### Ngày 29: Video Bằng Chứng GIGO & Chế Độ Giả Lập Hội Trường (Demo Simulator)
* **Cả 2 Dev:**
  * `[Code]`: Hoàn thiện nút ẩn **"Demo Simulator"** trong app: Cho phép phát lại file log GPS/IMU chạy thật tại Landmark 81 phòng trường hợp hội trường bảo vệ bị mất sóng vệ tinh.
  * `[Video]`: Cắt ghép 2 clip ngắn: (1) Chạy bộ thật chiếm đất đổi màu realtime; (2) Kẹp xe máy bị còi đỏ báo vi phạm GIGO để chèn trực tiếp vào slide thuyết trình.
  * `[Docs]`: Xuất file Báo cáo chính thức ra định dạng PDF. Kiểm tra đối chiếu danh mục tài liệu tham khảo và phụ lục.
* **Output Ngày 29:** File Báo cáo PDF hoàn chỉnh + File Slide PowerPoint + 2 Video demo thực chứng.

#### Ngày 30: [Final Release & Tổng Duyệt Bảo Vệ Đồ Án]
* **Cả 2 Dev:**
  * `[Diễn tập]`: Thuyết trình thử nghiệm 15 phút, trả lời các câu hỏi phản biện giả định của hội đồng (về thuật toán FFT, về Flood Fill, về cơ chế phân quyền RBAC và kiến trúc 3 tầng).
  * `[Demo Trực Tiếp]`: Phối hợp diễn tập demo trực tiếp trên 2 chiếc điện thoại thật: 1 chiếc chạy chiếm đất, chiếc còn lại đổi màu tức thì.
  * `[Deliverable Cuối Cùng]`:
    1. Cuốn Báo cáo Đồ án bản in / PDF đóng bìa chỉn chu.
    2. Slide thuyết trình chuyên nghiệp.
    3. Mã nguồn GitHub sạch sẽ, đã merge nhánh `main`.
    4. Ứng dụng đã cài sẵn trên 2 điện thoại, sẵn sàng bảo vệ đạt điểm tuyệt đối!

---

## 4. BẢNG CHECKLIST KIỂM TRA ĐẦU MỤC BÁO CÁO (REPORT CHECKLIST)

Trước khi in báo cáo, 2 bạn dùng bảng checklist này để tích chọn (đảm bảo không sót bất kỳ mục nào của thầy cô):

- [ ] **Bìa đồ án, Lời cảm ơn, Mục lục, Bảng từ viết tắt (Acronyms)**
- [ ] **Chương I: Tổng quan đề tài** (Bối cảnh Bình Thạnh, Ma trận đối thủ, Động cơ Anti-GIGO, Giới hạn phạm vi)
- [ ] **Chương II: Kế hoạch quản lý dự án** (Bảng WBS man-hours, Quy trình Agile 30 ngày, Quản lý rủi ro)
- [ ] **Chương III: Đặc tả yêu cầu phần mềm (SRS)**
  - [ ] Sơ đồ Ngữ cảnh (Context Diagram)
  - [ ] **Sơ đồ Use Case tổng thể (Use Case Diagram)**
  - [ ] Bảng đặc tả chi tiết 8 Use Case (UC-01 đến UC-08)
  - [ ] Sơ đồ luồng màn hình (Screen Flow) & Bảng phân quyền màn hình
  - [ ] Bảng chức năng ngầm phi giao diện (Non-screen functions)
  - [ ] Yêu cầu phi chức năng NFR (Hiệu năng 60 FPS, Pin $\le 7\%$, Độ trễ WebSocket)
- [ ] **Chương IV: Thiết kế phần mềm & CSDL (SDD) [TRỌNG TÂM]**
  - [ ] **Sơ đồ Kiến trúc hệ thống tổng thể (System Architecture Diagram 3-Tier)**
  - [ ] Sơ đồ Package (Package Diagram cho Backend và Frontend)
  - [ ] Sơ đồ CSDL quan hệ (**ERD**) & Từ điển dữ liệu chi tiết (Data Dictionary cho 7 bảng và 1 view)
  - [ ] **Lược đồ Lớp (Class Diagram) & Lược đồ Tuần tự (Sequence Diagram)** cho 4 phân hệ:
    - [ ] Phân hệ Xác thực & Định danh Sinh viên
    - [ ] Phân hệ Thu thập Telemetry & Anti-GIGO (Kalman + FFT)
    - [ ] Phân hệ Chiếm đất Khép vòng H3 & Realtime WebSocket
    - [ ] Phân hệ Bộ đếm Song song & Tự động hóa Mùa giải
- [ ] **Chương V: Tài liệu kiểm thử & Báo cáo thực địa**
  - [ ] Chiến lược kiểm thử & Bảng Test Cases chi tiết (TC-01 đến TC-15)
  - [ ] Báo cáo thực nghiệm chống xe máy (Bảng số liệu, biểu đồ phổ và ảnh chụp hiện trường)
  - [ ] Kết quả đo đạc chỉ số phi chức năng NFR (Pin, FPS, Latency)
- [ ] **Chương VI: Hướng dẫn cài đặt & Triển khai hệ thống** (Backend, Supabase, Flutter, Sideloadly)
- [ ] **Kết luận, Định hướng phát triển tương lai & Tài liệu tham khảo**
