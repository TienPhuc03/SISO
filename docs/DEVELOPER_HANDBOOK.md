# SỔ TAY HƯỚNG DẪN PHÁT TRIỂN HỆ THỐNG SISO (DEVELOPER HANDBOOK)
## HƯỚNG DẪN KỸ THUẬT, QUY CHUẨN CODE & PHỐI HỢP PHÁT TRIỂN (PAIR FULL-STACK)
**Dự án:** SISO (Step In Step Out) — Đại Chiến Đại Học Bình Thạnh  
**Đối tượng sử dụng:** Nhóm 2 Kỹ sư Full-stack (Dev 1 & Dev 2 cùng làm BE & FE theo module chức năng)  
**Môi trường:** Máy tính Windows + Thiết bị di động thật (iOS qua Sideloadly / Android APK)  
**Phiên bản:** 2.0  

---

## 1. BẢN ĐỒ KIẾN TRÚC MONOREPO (TOPOLOGY)

Dự án được tổ chức theo mô hình **Monorepo tinh gọn**, phân tách rõ ràng giữa máy chủ nghiệp vụ độc lập, ứng dụng di động và hạ tầng CSDL đám mây:

```
siso_project/
├── backend/                            # [MÁY CHỦ NESTJS API & WEBSOCKET - Port 3000]
│   ├── src/
│   │   ├── main.ts                     # Khởi chạy HTTP Server, CORS, Swagger UI (/docs)
│   │   ├── app.module.ts               # Root module kết nối Supabase Postgres & Redis
│   │   ├── entities/                   # TypeORM Entities (User, University, H3Hexagon...)
│   │   ├── database/                   # Script DDL khởi tạo schema PostGIS & seed data
│   │   │   └── init_schema.sql
│   │   └── modules/                    # Các Module nghiệp vụ độc lập
│   │       ├── auth/                   # Xác thực Edu Email (@*.edu.vn), JWT Token
│   │       ├── telemetry/              # Động cơ Anti-GIGO (Kinematic & FFT nhịp bước chân)
│   │       ├── turf/                   # Thuật toán Uber H3, Flood Fill khép vòng chiếm đất
│   │       ├── realtime/               # WebSocket Gateway (Socket.io) broadcast đổi màu
│   │       └── leaderboard/            # Bộ đếm song song: % Đất & % Km Mùa giải
│   ├── docker-compose.yml              # PostgreSQL 15 (PostGIS) + Redis 7 + API Server
│   ├── Dockerfile
│   ├── package.json
│   └── .env & .env.example
│
├── lib/                                # [ỨNG DỤNG FLUTTER MOBILE CLIENT (Dart 3.x)]
│   ├── main.dart                       # Khởi chạy Flutter, load .env, init ApiClient & Socket
│   └── src/
│       ├── core/                       # Thành phần dùng chung (Shared Kernel)
│       │   ├── constants/              # Bảng màu 5 trường Bình Thạnh, API Base URLs
│       │   ├── network/                # ApiClient (Dio REST) & SocketManager (WebSocket)
│       │   ├── errors/                 # Mã lỗi hệ thống chuẩn ERR_101 -> ERR_302
│       │   └── utils/                  # Hàm toán học khoảng cách Haversine
│       └── features/                   # Các tính năng độc lập (Clean Architecture Feature-first)
│           ├── auth/                   # LoginScreen, VerifyScreen, AuthRepository
│           ├── map/                    # MapScreen, HexagonLayer, PercentDominanceBar
│           ├── tracking/               # ActiveRunScreen, SpeedCadenceHud, KalmanFilter, IMU
│           └── leaderboard/            # LeaderboardScreen, HallOfFameCard
│
├── test/                               # Bộ kiểm thử Unit test của Client
│   └── gigo_filter_test.dart
├── docs/                               # Toàn bộ tài liệu đặc tả & hướng dẫn
│   ├── SRS_SISO_DA_CHIEN_BINH_THANH.md # Đặc tả phần mềm chuẩn ISO 29148
│   ├── DEVELOPER_HANDBOOK.md           # Sổ tay hướng dẫn phát triển này
│   └── TIMELINE_30_DAYS.md             # Kế hoạch phát triển 30 ngày cho 2 thành viên
├── .github/workflows/
│   └── build_ios.yml                   # CI/CD tự động build Runner.ipa cho iPhone (0 đồng)
├── pubspec.yaml                        # Quản lý dependencies của Flutter
├── .env & .env.example                 # Cấu hình môi trường cho Mobile Client
└── README.md                           # Hướng dẫn setup nhanh và chạy hệ thống
```

---

## 2. QUY TẮC BẤT BIẾN TRONG KIẾN TRÚC (CORE INVARIANTS)

1. **Tuyệt đối không gọi thẳng CSDL từ Mobile Client:**
   * Flutter Client chỉ được phép giao tiếp với hệ thống qua **REST API** (`ApiClient` dùng `dio`) và **WebSocket** (`SocketManager` dùng `socket_io_client`). Mọi thông số kết nối Database (`DB_PASSWORD`, Supabase credentials) chỉ được lưu tại file `backend/.env`.
2. **Server là Nguồn Chân Lý Duy Nhất (Single Source of Truth):**
   * Client chỉ gửi dữ liệu cảm biến thô (Raw Telemetry) và danh sách mã H3 đường biên. Việc quyết định phiên chạy có hợp lệ hay không (Anti-GIGO) và đất có được chiếm hay không (Flood Fill) **hoàn toàn do NestJS tính toán**.
3. **Quy chuẩn Chỉ mục Không gian:**
   * Toàn bộ hệ thống thống nhất sử dụng **Uber H3 Resolution 10** (độ phân giải 10: bán kính $\approx 65\text{m}$, diện tích $\approx 15,000\text{ m}^2$).
4. **Giới hạn An toàn Chống Lạm dụng (Anti-Abuse Cap):**
   * Mỗi vòng khép chiếm đất không được vượt quá **150 ô lục giác H3** (`ERR_301`) để triệt tiêu hành vi gian lận vẽ vòng bao quanh cả quận.
5. **Cơ chế Phân chia Công việc Full-stack:**
   * Cả 2 kỹ sư đều viết mã trên cả Backend (`backend/`) và Frontend (`lib/`) tương ứng với từng chức năng mình phụ trách, đảm bảo hiểu thấu suốt luồng dữ liệu từ Giao diện đến CSDL.

---

## 3. QUY CHUẨN CODE & TIÊU CHUẨN THIẾT KẾ

### 3.1. Phía Backend (NestJS / TypeScript)
* **DTO & Validation:** 100% dữ liệu đầu vào phải được định nghĩa bằng class DTO và kiểm tra bằng `class-validator` kết hợp `@nestjs/swagger` decorators:
  ```typescript
  export class ClaimLoopDto {
    @ApiProperty({ example: ['8a31e8464627fff'], description: 'Chu trình khép kín H3' })
    @IsArray()
    @IsNotEmpty()
    boundaryH3Indexes: string[];

    @ApiProperty({ example: 1250.5 })
    @IsNumber()
    distanceMeters: number;
  }
  ```
* **Bảo mật JWT:** Các endpoint yêu cầu định danh người dùng phải đính kèm `@UseGuards(JwtAuthGuard)` và `@ApiBearerAuth()`.
* **Xử lý Ngoại lệ Đồng nhất:** Ném lỗi bằng `BadRequestException` đính kèm mã lỗi chuẩn trong bảng `SisoErrorCodes`:
  ```typescript
  throw new BadRequestException({
    code: 'ERR_202',
    message: 'VEHICLE_SPEED_MISMATCH: Phát hiện vận tốc không khớp với nhịp bước chân.',
  });
  ```

### 3.2. Phía Mobile Client (Flutter / Dart)
* **Quản lý Trạng thái:** Sử dụng **Riverpod 2.x** (`StateNotifierProvider`, `FutureProvider`).
* **Clean Architecture Feature-first:** Mỗi module chức năng trong `lib/src/features/` chia thành 4 thư mục chuẩn:
  * `data/`: Các lớp Repository gọi HTTP hoặc đọc Local Cache.
  * `domain/`: Các mô hình dữ liệu (Models) và thuật toán thuần Dart (như `KalmanFilter`, `AccelBuffer`).
  * `presentation/`: Các màn hình UI (Widgets, Screens) và HUD.
  * `providers/`: Các Notifier quản lý state cho màn hình.

---

## 4. BỘ THUẬT TOÁN CỐT LÕI & MÃ NGUỒN MẪU

### 4.1. Bộ lọc Kalman vận tốc trên Client (`kalman_filter.dart`)
```dart
class KalmanFilter {
  static const double maxHumanSpeedMps = 9.0; // 32.4 km/h

  bool isValidVelocity(double deltaDistanceMeters, double deltaTimeSeconds) {
    if (deltaTimeSeconds <= 0) return false;
    final velocity = deltaDistanceMeters / deltaTimeSeconds;
    return velocity <= maxHumanSpeedMps;
  }
}
```

### 4.2. Thuật toán FFT phân tích nhịp bước chân chống xe máy (`anti-gigo.service.ts`)
```typescript
@Injectable()
export class AntiGigoService {
  validateBiometrics(speedMps: number, imuSamples: ImuSampleDto[]): GigoCheckResult {
    if (speedMps < 1.0 || imuSamples.length < 64) {
      return { isValid: true, errorCode: null, message: 'Chạy chậm/chờ thêm mẫu' };
    }

    // 1. Tính gia tốc tổng hợp Amag = sqrt(ax^2 + ay^2 + az^2) - 1.0G
    const magnitudes = imuSamples.map(s => Math.abs(Math.sqrt(s.ax * s.ax + s.ay * s.ay + s.az * s.az) - 1.0));
    const avg = magnitudes.reduce((a, b) => a + b, 0) / magnitudes.length;
    const variance = magnitudes.reduce((acc, val) => acc + Math.pow(val - avg, 2), 0) / magnitudes.length;
    const amplitude = Math.sqrt(variance);

    // 2. Tính tần số bước chân bằng Zero-Crossing Rate
    let zeroCrossings = 0;
    for (let i = 1; i < magnitudes.length; i++) {
      if ((magnitudes[i] - avg) * (magnitudes[i - 1] - avg) < 0) zeroCrossings++;
    }
    const durationSeconds = imuSamples.length / 50.0;
    const estimatedFreqHz = (zeroCrossings / 2) / durationSeconds;
    const estimatedCadenceSpm = Math.round(estimatedFreqHz * 60);

    // 3. Quy tắc từ chối xe máy: Vận tốc cao (>= 2.5 m/s) nhưng nhịp bước < 120 SPM hoặc dao động đứng < 0.2G
    if (speedMps >= 2.5 && (amplitude < 0.2 || estimatedCadenceSpm < 120)) {
      return {
        isValid: false,
        errorCode: 'ERR_202',
        message: `VEHICLE_SPEED_MISMATCH: Vận tốc ${(speedMps * 3.6).toFixed(1)} km/h nhưng cadence chỉ ${estimatedCadenceSpm} SPM.`,
      };
    }
    return { isValid: true, errorCode: null, message: 'Nhịp bước hợp lệ' };
  }
}
```

### 4.3. Thuật toán Loang đa giác khép kín Uber H3 (`h3.service.ts`)
```typescript
@Injectable()
export class H3Service {
  calculateEnclosedHexes(boundaryIndexes: string[]): string[] {
    if (!boundaryIndexes || boundaryIndexes.length === 0) return [];
    if (boundaryIndexes.length > 150) {
      throw new BadRequestException({ code: 'ERR_301', message: 'Vòng lặp vượt quá 150 ô.' });
    }

    const coordinates: [number, number][] = boundaryIndexes.map(hex => h3.cellToLatLng(hex));
    if (coordinates.length >= 3) {
      coordinates.push([coordinates[0][0], coordinates[0][1]]); // Khép kín đa giác
      const enclosed = h3.polygonToCells(coordinates, 10, true);
      const combined = Array.from(new Set([...boundaryIndexes, ...enclosed]));
      if (combined.length > 150) {
        throw new BadRequestException({ code: 'ERR_301', message: 'Diện tích khép vòng vượt quá 150 ô H3.' });
      }
      return combined;
    }
    return Array.from(new Set(boundaryIndexes));
  }
}
```

---

## 5. HƯỚNG DẪN TEST & MOCK TELEMETRY

### 5.1. Chạy Unit Test Backend
```bash
cd backend
npm test
```
* Bộ kiểm thử [`anti-gigo.service.spec.ts`](file:///d:/Workspace/ĐACNPM/siso_project/backend/src/modules/telemetry/anti-gigo.service.spec.ts): Kiểm tra tự động phát hiện Mock GPS (`ERR_201`) và chặn xe máy 12km/h (`ERR_202`).
* Bộ kiểm thử [`h3.service.spec.ts`](file:///d:/Workspace/ĐACNPM/siso_project/backend/src/modules/turf/h3.service.spec.ts): Kiểm tra tính toán các ô H3 và ném lỗi khi vượt ngưỡng 150 ô (`ERR_301`).

### 5.2. Chạy Unit Test Frontend
```bash
flutter test
```
* Kiểm thử bộ lọc Kalman vận tốc tại [`test/gigo_filter_test.dart`](file:///d:/Workspace/ĐACNPM/siso_project/test/gigo_filter_test.dart).

### 5.3. Sử dụng Demo Simulator khi Thuyết trình Bảo vệ
Để giải quyết rủi ro **mất sóng GPS trong nhà hội trường**, nhóm đã chuẩn bị sẵn file [`lib/test/mock_telemetry_data.dart`](file:///d:/Workspace/ĐACNPM/siso_project/lib/test/mock_telemetry_data.dart):
* Cho phép bấm nút "Phát lại phiên chạy thật" (Replay Log) đã ghi nhận tại Đấu trường Landmark 81 để trình diễn mượt mà màn khép vòng chiếm đất trước mặt Hội đồng!

---

## 6. QUY TRÌNH BUILD & CÀI ĐẶT LÊN IPHONE (0 ĐỒNG TỪ WINDOWS)

Vì cả 2 thành viên đều dùng iPhone nhưng phát triển trên máy tính Windows:
1. **GitHub Actions Tự Động Build:**
   * Mỗi khi push code lên nhánh `develop` hoặc `main`, pipeline [`.github/workflows/build_ios.yml`](file:///d:/Workspace/ĐACNPM/siso_project/.github/workflows/build_ios.yml) trên máy chủ macOS của GitHub sẽ tự động build ra file `Runner.ipa` (unsigned).
2. **Cài vào 2 iPhone qua Sideloadly trên Windows:**
   * Tải công cụ **Sideloadly** trên laptop Windows.
   * Cắm cáp kết nối iPhone vào laptop.
   * Kéo thả file `Runner.ipa` vào Sideloadly, nhập Apple ID cá nhân (miễn phí, không tốn 99$/năm).
   * Bấm **Start** $\rightarrow$ Sau 60 giây app SISO đã nằm trên iPhone của 2 bạn và sẵn sàng ra đường test thực địa!
