# KẾ HOẠCH TRIỂN KHAI DỰ ÁN SISO TRONG 30 NGÀY
## PHÂN CHIA CÔNG VIỆC FULL-STACK THEO TỪNG CHỨC NĂNG (FEATURE-DRIVEN PAIRING)
**Dự án:** SISO (Step In Step Out) — Đại Chiến Đại Học Bình Thạnh  
**Học phần:** Đồ án Thực tế Công nghệ Phần mềm  
**Quy mô:** 2 Kỹ sư Full-stack (Dev 1 & Dev 2 cùng tham gia viết BE & FE theo từng lát cắt chức năng - Vertical Slices)  
**Thời lượng:** Đúng 30 Ngày (6 Sprint 5 ngày)  
**Mục tiêu:** Bàn giao sản phẩm hoàn chỉnh, không conflict mã nguồn, vượt qua tất cả tiêu chí đánh giá của Hội đồng.  

---

## 1. NGUYÊN TẮC PHÂN CHIA CÔNG VIỆC (FULL-STACK FEATURE-FIRST)

> [!IMPORTANT]
> **Nguyên tắc cốt lõi:**  
> Không phân chia máy móc "Dev 1 làm FE, Dev 2 làm BE". Thay vào đó, **hệ thống được chia thành các Tính năng Độc lập (Feature Modules)**:
> * Khi một kỹ sư nhận một tính năng, người đó sẽ phụ trách **từ đầu đến cuối (Vertical Slice)**: Thiết kế CSDL $\rightarrow$ Viết API/WebSocket trong NestJS $\rightarrow$ Viết Service/State/UI trong Flutter $\rightarrow$ Viết Unit test.
> * Kỹ sư còn lại đóng vai trò Review PR, kiểm thử chéo và tích hợp với tính năng song song của mình.
> * Nhờ vậy, cả 2 thành viên đều thành thạo toàn bộ công nghệ của dự án và tự tin trả lời bất kỳ câu hỏi nào của giảng viên phản biện.

```
┌────────────────────────────────────────────────────────────────────────┐
│                   MA TRẬN PHÂN CHIA CHỨC NĂNG FULL-STACK               │
├────────────────────────────────────────┬───────────────────────────────┤
│ DEV 1 (Kỹ sư Full-stack A)             │ DEV 2 (Kỹ sư Full-stack B)    │
├────────────────────────────────────────┼───────────────────────────────┤
│ • Module 1: Định danh Sinh viên (BE+FE)│ • Module 2: Bản đồ H3 (BE+FE) │
│ • Module 3: Lọc Kinematic Kalman(BE+FE)│ • Module 4: Anti-GIGO FFT(BE+FE)│
│ • Module 5: Khép vòng chiếm đất (BE+FE)│ • Module 6: Realtime WS (BE+FE)│
│ • Module 7: Bộ đếm Song song & Km(BE+FE│ • Module 8: Leaderboard (BE+FE)│
└────────────────────────────────────────┴───────────────────────────────┘
```

---

## 2. BẢNG TIMELINE CHI TIẾT 30 NGÀY (DAY-BY-DAY SCHEDULE)

### GIAI ĐOẠN 1: KHỞI TẠO NỀN TẢNG, ĐỊNH DANH & BẢN ĐỒ KHÔNG GIAN (NGÀY 1 – NGÀY 7)

#### Ngày 1: Họp Kick-off, Khởi tạo Monorepo & CSDL Supabase
* **Dev 1 (BE + FE):** Khởi tạo Git repository, cấu hình Monorepo (`backend/`, `lib/`), setup `.gitignore`, `.env.example`. Cài đặt khung dự án NestJS và Flutter.
* **Dev 2 (BE + FE):** Đăng ký dự án Supabase Cloud `siso-binhthanh-prod`, kích hoạt extension `postgis` và `pg_cron`. Viết script DDL [`init_schema.sql`](file:///d:/Workspace/ĐACNPM/siso_project/backend/src/database/init_schema.sql) tạo bảng và nạp 5 trường Bình Thạnh.
* **Kết quả ngày 1:** CSDL Supabase đã online, NestJS kết nối DB thành công qua SSL TypeORM, Flutter chạy màn hình trắng đầu tiên.

#### Ngày 2: Setup CI/CD iOS & Thư viện Cốt lõi
* **Dev 1 (BE + FE):** Tạo workflow GitHub Actions [`.github/workflows/build_ios.yml`](file:///d:/Workspace/ĐACNPM/siso_project/.github/workflows/build_ios.yml) tự động xuất file `.ipa`. Test cài đặt app lên 2 iPhone bằng Sideloadly thành công.
* **Dev 2 (BE + FE):** Cấu hình Swagger OpenAPI 3.0 trong NestJS (`/docs`). Xây dựng thư mục `core/` trong Flutter: bảng màu 5 trường [`colors.dart`](file:///d:/Workspace/ĐACNPM/siso_project/lib/src/core/constants/colors.dart) và các tiện ích địa lý.
* **Kết quả ngày 2:** App "Hello SISO" đã nằm trên màn hình 2 chiếc iPhone thật.

#### Ngày 3 – Ngày 4: [Module 1 - Dev 1] Xác Thực Email Sinh Viên (@*.edu.vn)
* **Dev 1 phụ trách Full-stack:**
  * *Phía Backend:* Viết `AuthModule` trong NestJS: DTO kiểm tra định danh email 5 trường Bình Thạnh (`@hutech.edu.vn`, `@uef.edu.vn`, `@ut.edu.vn`, `@ftu.edu.vn`, `@hiu.vn`), dịch vụ phát sinh OTP và cấp phát JWT token có hạn 7 ngày.
  * *Phía Frontend:* Thiết kế `LoginScreen` và `VerifyScreen`, cấu hình `AuthRepository` và `AuthNotifier` (Riverpod) gọi `POST /api/v1/auth/edu-login` và `verify-otp`.
* **Dev 2 hỗ trợ:** Kiểm thử API Auth qua Swagger UI, viết unit test mock domain email.
* **Kết quả ngày 4:** Sinh viên nhập email trường $\rightarrow$ Nhập OTP $\rightarrow$ Nhận JWT và lưu vào bộ nhớ app.

#### Ngày 5 – Ngày 6: [Module 2 - Dev 2] Bản Đồ Lục Giác Uber H3 & Sân Đấu Bình Thạnh
* **Dev 2 phụ trách Full-stack:**
  * *Phía Backend:* Viết `TurfController` và endpoint `GET /api/v1/turf/hexagons`, cấu hình bảng `arenas` (KĐT Sala, Vạn Phúc City, Landmark 81, Bờ kè Thanh Đa).
  * *Phía Frontend:* Tích hợp `flutter_map` với tile server CartoDB, tích hợp thư viện `h3_flutter`, viết widget `HexagonLayer` render 100 ô lục giác H3 Resolution 10 mẫu lên bản đồ.
* **Dev 1 hỗ trợ:** Tối ưu hóa render FPS bản đồ trên Flutter, viết hàm bao quanh camera theo vị trí hiện tại.
* **Kết quả ngày 6:** Bản đồ Bình Thạnh hiển thị mượt mà với lưới lục giác phủ lên các khuôn viên trường.

#### Ngày 7: [Milestone 1 - Nghiệm thu Tuần 1]
* **Cả 2 Dev:** Ghép nối hoàn chỉnh: Mở app $\rightarrow$ Đăng nhập email sinh viên trường nào thì bản đồ hiển thị màu sắc nhận diện của trường đó! Format code bằng `dart format` và `npm run format`.

---

### GIAI ĐOẠN 2: THU THẬP TELEMETRY & ĐỘNG CƠ CHỐNG GIAN LẬN ANTI-GIGO (NGÀY 8 – NGÀY 14)

#### Ngày 8 – Ngày 9: [Module 3 - Dev 1] Thu Thập Cảm Biến & Lọc Kinematic Kalman
* **Dev 1 phụ trách Full-stack:**
  * *Phía Frontend:* Cấu hình quyền `CoreLocation` & `CoreMotion` trên iOS (`Info.plist`). Xây dựng `LocationService` (lấy GPS 1s/lần) và `SensorDataSource` (đọc gia tốc 3 trục $50\text{Hz}$ từ `sensors_plus`). Cài đặt bộ lọc Kalman trên Dart (`kalman_filter.dart`) để chặn nhảy vọt tọa độ do dội sóng cao tầng.
  * *Phía Backend:* Viết endpoint `POST /api/v1/telemetry/verify`, cài đặt hàm `validateKinematics`: Kiểm tra cờ Fake GPS (`ERR_201`), kiểm tra sai số vệ tinh $> 20\text{m}$ (`ERR_203`) và vận tốc con người $> 9\text{ m/s}$ (`ERR_202`).
* **Dev 2 hỗ trợ:** Thiết kế DTO `TelemetryPayloadDto` có xác thực mảng mẫu gia tốc.
* **Kết quả ngày 9:** App thu thập được luồng tọa độ sạch và buffer gia tốc liên tục khi đang chạy.

#### Ngày 10 – Ngày 12: [Module 4 - Dev 2] Động Cơ Biometric FFT Chống Xe Máy
* **Dev 2 phụ trách Full-stack:**
  * *Phía Backend:* Xây dựng `AntiGigoService`: Thuật toán tính gia tốc tổng hợp $A_{\text{mag}}(t) = \sqrt{a_x^2 + a_y^2 + a_z^2} - 1.0G$, áp dụng Zero-Crossing Rate trên buffer 256 mẫu ($5.12\text{s}$) để ước tính tần số bước chân con người ($120 - 220\text{ SPM}$). Thiết lập ma trận chặn xe máy (Vận tốc $> 9\text{ km/h}$ nhưng nhịp chân $< 120\text{ SPM}$ hoặc biên độ dao động đứng $< 0.2G \rightarrow$ Ném mã lỗi `ERR_202`).
  * *Phía Frontend:* Xây dựng màn hình `ActiveRunScreen` và widget `SpeedCadenceHud` hiển thị tốc độ km/h và nhịp bước chân SPM theo thời gian thực.
* **Dev 1 hỗ trợ:** Thu thập dữ liệu mẫu (mẫu người chạy bộ thật vs mẫu người ngồi xe máy) để nạp vào bộ unit test Jest.
* **Kết quả ngày 12:** Backend phân tích và phân biệt chính xác $100\%$ giữa chạy bộ thật và đi xe máy trên dữ liệu test.

#### Ngày 13 – Ngày 14: [Milestone 2 - Test GIGO Thực Địa]
* **Cả 2 Dev ra hiện trường (Đường D2 & Bờ kè Thanh Đa):**
  * Dev 1 xỏ giày chạy bộ thật 1km: Hệ thống ghi nhận nhịp bước $155\text{ SPM}$, phiên chạy sạch được phê duyệt.
  * Dev 2 kẹp điện thoại lên xe máy chạy rà rà 12km/h: Hệ thống lập tức báo còi đỏ vi phạm `ERR_202 (VEHICLE_SPEED_MISMATCH)` và hủy phiên chạy!
* **Kết quả ngày 14:** Chụp màn hình và quay video làm bằng chứng khoa học cho bài báo cáo đồ án.

---

### GIAI ĐOẠN 3: CHIẾM ĐẤT KHÉP VÒNG & ĐỒNG BỘ REALTIME WEBSOCKET (NGÀY 15 – NGÀY 21)

#### Ngày 15 – Ngày 17: [Module 5 - Dev 1] Thuật Toán Khép Vòng (Loop Capture) & Flood Fill H3
* **Dev 1 phụ trách Full-stack:**
  * *Phía Frontend:* Xây dựng thuật toán nhận diện khép vòng trên Dart: Khi tọa độ hiện tại cắt ngang vệt chạy cũ trong bán kính 20m $\rightarrow$ Kích hoạt sự kiện khép vòng (`Loop Detected`), trích xuất danh sách mã H3 đường biên.
  * *Phía Backend:* Xây dựng `H3Service`: Sử dụng thư viện `h3-js`, viết hàm `calculateEnclosedHexes` biến đổi chu trình kín thành tập hợp các ô lục giác lõi bên trong (`polygonToCells`). Cài đặt trần an toàn chống lạm dụng tối đa 150 ô (`ERR_301`).
* **Dev 2 hỗ trợ:** Viết câu lệnh SQL `UPSERT` hàng loạt vào bảng `h3_hexagons`.
* **Kết quả ngày 17:** Khép 1 vòng kín trên bản đồ $\rightarrow$ Server tính toán chính xác toàn bộ các ô lục giác nằm lọt bên trong.

#### Ngày 18 – Ngày 20: [Module 6 - Dev 2] Đồng Bộ Realtime Đổi Màu Bản Đồ (WebSocket)
* **Dev 2 phụ trách Full-stack:**
  * *Phía Backend:* Xây dựng `TurfGateway` sử dụng WebSocket (Socket.io namespace `/turf-ws`). Khi hàm `claimLoop` trong `TurfService` hoàn tất, kích hoạt broadcast sự kiện `hex_claimed` gửi mã trường và danh sách ô đất mới chiếm tới toàn bộ client.
  * *Phía Frontend:* Xây dựng `SocketManager` trên Flutter (`socket_io_client`), lắng nghe sự kiện `hex_claimed`. Tạo hiệu ứng Pulse Animation đổi màu các ô lục giác trên bản đồ ngay lập tức khi đối thủ vừa chiếm đất.
* **Dev 1 hỗ trợ:** Tối ưu hóa bộ nhớ RAM trên điện thoại, đảm bảo repaint các ô lục giác đạt 60 FPS không giật lag.
* **Kết quả ngày 20:** Chiếc iPhone A chạy chiếm đất $\rightarrow$ Bản đồ trên chiếc iPhone B của đối thủ lập tức đổi màu trong $< 300\text{ms}$!

#### Ngày 21: [Milestone 3 - Nghiệm thu Turf War Trực Tiếp]
* **Cả 2 Dev:** Chạy khép 1 vòng thật quanh dãy nhà trường HUTECH/UEF $\rightarrow$ Đất bên trong đổi màu đồng loạt trên máy cả hai bạn.

---

### GIAI ĐOẠN 4: BỘ ĐẾM SONG SONG, QUỸ KM VỀ QUÊ & RESET MÙA GIẢI (NGÀY 22 – NGÀY 26)

#### Ngày 22 – Ngày 23: [Module 7 - Dev 1] Bộ Đếm % Song Song & Quỹ Km Đánh Lẻ Khi Về Quê
* **Dev 1 phụ trách Full-stack:**
  * *Phía Backend:* Viết SQL View `v_campus_live_scores` tự động tính 3 thước đo: (1) % Lãnh thổ chiếm đóng, (2) % Km cống hiến toàn cầu, (3) % Sức mạnh tổng hợp ($50\% \text{ Đất} + 50\% \text{ Km}$). Viết API `POST /api/v1/turf/free-run` ghi nhận km cống hiến từ xa cho sinh viên về quê.
  * *Phía Frontend:* Thiết kế widget **Dual-Metric Live HUD** gắn ở đỉnh màn hình bản đồ. Hiển thị thông báo khi sinh viên chạy lẻ ở quê: *"Bạn vừa cống hiến +X.X km cho trường [Tên Trường]!"*.
* **Dev 2 hỗ trợ:** Kiểm tra tính chính xác của công thức chia tỷ lệ phần trăm khi tổng km bằng 0 (chống lỗi `Division by Zero`).
* **Kết quả ngày 23:** Cả sinh viên ở thành phố chiếm đất và sinh viên về quê chạy lẻ đều thấy đóng góp trực tiếp của mình vào bảng xếp hạng.

#### Ngày 24 – Ngày 25: [Module 8 - Dev 2] Bảng Xếp Hạng Mùa Giải & Hao Mòn Đất 48h (Decay Engine)
* **Dev 2 phụ trách Full-stack:**
  * *Phía Backend:* Viết `LeaderboardModule` cung cấp `GET /api/v1/leaderboard/scores` và `/hall-of-fame`. Cài đặt lệnh `pg_cron` trong PostgreSQL: Đúng 00:00:00 ngày đầu tháng reset đất về trung lập, lưu Quán quân vào `hall_of_fame`, đặt lại quỹ km về 0. Viết hàm tự động giảm 50% HP ô đất sau 24h không tuần tra.
  * *Phía Frontend:* Thiết kế `LeaderboardScreen` hiển thị top các trường dẫn đầu và `HallOfFameCard` vinh danh cúp vô địch các mùa giải trước. Thể hiện độ mờ (opacity) của ô lục giác theo chỉ số `shield_hp`.
* **Dev 1 hỗ trợ:** Làm bộ lọc xem bảng xếp hạng theo từng trường và cá nhân đóng góp nhiều km nhất.
* **Kết quả ngày 25:** Hệ thống vận hành trọn vẹn chu kỳ 30 ngày tự động hóa $100\%$ không cần người vận hành can thiệp.

#### Ngày 26: [Milestone 4 - Nghiệm thu Toàn diện Tính năng]
* **Cả 2 Dev:** Kiểm thử toàn bộ 8 use cases, thử nghiệm chạy lệnh cron reset tháng và kiểm tra tính toàn vẹn dữ liệu.

---

### GIAI ĐOẠN 5: ALPHA TEST THỰC ĐỊA, ĐO ĐẠC TELEMETRY & BẢO VỆ ĐỒ ÁN (NGÀY 27 – NGÀY 30)

#### Ngày 27: Đóng Gói Bản Cài Đặt & Phát Hành Thử Nghiệm Nội Bộ
* Xuất bản file `Runner.ipa` (cho iOS) và file `app-release.apk` (cho Android).
* Gửi link cài đặt cho 20–30 sinh viên bạn bè ở các trường HUTECH, UEF, GTVT chạy thử nghiệm tại Công viên Landmark 81 và khu D2.

#### Ngày 28: Thu Thập Telemetry & Tối Ưu Hóa NFR
* Theo dõi server NestJS và Supabase: Kiểm tra tỷ lệ bắt xe máy thành công, độ trễ WebSocket.
* Đo đạc thực tế chỉ số NFR: Xác nhận pin tiêu thụ $\le 7\%$ cho 30 phút chạy; màn hình bản đồ đạt ổn định $\ge 58\text{ FPS}$.

#### Ngày 29: Chuẩn Bị Video Bằng Chứng GIGO & Chế Độ Giả Lập Hội Trường
* Cắt ghép 2 đoạn video thực tế: (1) Chạy bộ thật đổi màu đất mượt mà; (2) Kẹp xe máy bị còi đỏ báo vi phạm GIGO để chèn trực tiếp vào slide thuyết trình.
* Kiểm tra nút ẩn **"Demo Simulator"** trong app để phát lại file log GPS chạy thật phòng trường hợp phòng bảo vệ bị mất sóng vệ tinh.

#### Ngày 30: Tổng Duyệt & Sẵn Sàng Bảo Vệ Xuất Sắc (Final Release 1.0)
* Tổng duyệt thuyết trình slide 15 phút.
* 2 bạn tự tin phối hợp demo trực tiếp trên 2 chiếc điện thoại trước Hội đồng chấm thi!

---

## 3. ĐỊNH NGHĨA HOÀN THÀNH (DEFINITION OF DONE - DoD)

Một chức năng chỉ được xác nhận là "Hoàn thành" (Done) khi thỏa mãn 5 điều kiện:
1. **Full-stack hoàn chỉnh:** Đã có đầy đủ API Backend (có Swagger Docs), CSDL PostGIS và Giao diện/State Frontend tương ứng.
2. **Không lỗi linter:** Chạy `npm run build` không lỗi và `flutter analyze` không còn cảnh báo vàng.
3. **Unit test đầy đủ:** Có unit test kiểm thử các trường hợp thành công và trường hợp biên (Biometric vi phạm, H3 vượt ngưỡng).
4. **Test trên thiết bị thật:** Đã chạy thử nghiệm thực tế trên iPhone/Android thật và không gây giật lag bản đồ ($> 55\text{ FPS}$).
5. **Git sạch sẽ:** Code đã được rebase và merge vào nhánh `main` qua Pull Request có review của thành viên còn lại.
