# CLAUDE.md

Tệp này cung cấp hướng dẫn cho Claude Code (claude.ai/code) khi làm việc với mã nguồn trong repository này.

## Tổng quan

SISO (Step In Step Out) là ứng dụng chạy bộ chiếm lãnh thổ (gamified) dành cho sinh viên 5 trường đại học tại Quận Bình Thạnh, TP.HCM. Đây là monorepo gồm hai ứng dụng: **client Flutter** (thư mục gốc: `lib/`, `test/`, `pubspec.yaml`) và **backend NestJS** (`backend/`). Tài liệu (tiếng Việt) nằm ở `README.md`, `docs/DEVELOPER_HANDBOOK.md` và `docs/SISO_Timeline_v2.md` (kế hoạch công việc theo ngày).

## Lệnh thường dùng

Backend (chạy trong `backend/`):
- `npm install`, `npm run start:dev` (chế độ watch; Swagger tại `/docs`, Socket.io tại `/turf-ws`), `npm run build`
- `npm test`; chạy một file: `npx jest anti-gigo.service.spec`; chạy một test: `npx jest -t "<tên test>"` (`rootDir` của jest là `src`, khớp với `*.spec.ts`)
- `docker-compose up -d` chạy Postgres/PostGIS + Redis + API ở local (nạp `src/database/init_schema.sql` khi khởi tạo)

Client (thư mục gốc repo):
- `flutter pub get`, `flutter run -d chrome` (hoặc chạy trên thiết bị), `flutter test`, `flutter test test/gigo_filter_test.dart`, `flutter analyze`
- Biến môi trường lấy từ `.env` ở thư mục gốc (sao chép từ `.env.example`): `API_BASE_URL`, `SOCKET_URL` (máy ảo Android cần `http://10.0.2.2:3000`, thiết bị thật cần IP LAN).

Biến môi trường của backend lấy từ `backend/.env` (sao chép từ `backend/.env.example`): `DATABASE_URL` hoặc nhóm `DB_*`, `DB_SSL`, `REDIS_*`, `JWT_SECRET`.

## Kiến trúc

**Server là nguồn chân lý duy nhất.** Client chỉ gửi dữ liệu telemetry thô (GPS + mẫu IMU 50 Hz) và các chỉ mục H3 của đường biên. Việc một phiên chạy có hợp lệ hay không (anti-GIGO) và đất có được chiếm hay không (flood fill) chỉ do backend quyết định. Client không bao giờ truy cập trực tiếp CSDL; chỉ dùng REST (`ApiClient`, Dio) và WebSocket (`SocketManager`).

Backend (`backend/src/`): các module nghiệp vụ trong `modules/` — `auth` (email edu + OTP → JWT, `JwtAuthGuard`), `telemetry` (`AntiGigoService`: kiểm tra động học, sau đó kiểm tra nhịp bước/FFT từ IMU để loại xe máy và GPS giả), `turf` (`H3Service` loang vòng khép kín thành các ô lục giác bên trong; `TurfService` thực hiện chiếm đất), `realtime` (`TurfGateway` phát sự kiện đổi chủ ô), `leaderboard` (hai bộ đếm song song: % đất và % km). Các TypeORM entity nằm trong `entities/` và phải được khai báo thủ công trong `app.module.ts`. `synchronize` là **false**: schema nằm trong `src/database/init_schema.sql` (PostGIS, `pg_cron`; chạy thủ công trên Supabase hoặc qua docker init), nên thay đổi entity cần sửa SQL tương ứng.

Dùng chung toàn hệ thống: `ValidationPipe` toàn cục (whitelist + forbidNonWhitelisted, nên mọi trường của request đều cần decorator trong DTO) và `AllExceptionsFilter` (`common/filters`). Lỗi được ném dưới dạng `BadRequestException({ code: 'ERR_xxx', message })` theo bảng mã lỗi chung (ERR_201 GPS giả, ERR_202 vận tốc không khớp nhịp bước, ERR_301 vòng lặp vượt quá 150 ô; bản tương ứng phía client ở `lib/src/core/errors/siso_exceptions.dart`).

Quy tắc bất biến: độ phân giải H3 là 10 ở mọi nơi (client và server); một vòng chiếm đất không được vượt quá 150 ô.

Client (`lib/src/`): tổ chức theo tính năng (feature-first) tại `features/{auth,map,tracking,leaderboard}`, mỗi tính năng chia thành `data/` (repository), `domain/` (Dart thuần như `KalmanFilter`, `AccelBuffer`), `presentation/`, `providers/` (Riverpod notifier). Mã dùng chung nằm trong `core/`.

CI: `.github/workflows/build_ios.yml` build IPA iOS chưa ký (cho Sideloadly) trên macOS khi push lên `develop`/`main`.

## Ghi chú

- `.claude/skills/` và `.agents/skills/` chứa các skill Supabase được đưa vào sẵn (theo dõi qua `skills-lock.json`); không phải mã nguồn dự án.
- Đăng nhập demo: bất kỳ email edu được hỗ trợ cùng mã OTP `123456`.


## Quy tắc Git
- KHÔNG chạy git commit, push, merge, rebase, reset.
- Sửa xong thì liệt kê file đã thay đổi để tôi tự review và commit.

## Agent skills

### Issue tracker

Issue được theo dõi trên GitHub Issues (`TienPhuc03/SISO`) qua `gh` CLI. Xem `docs/agents/issue-tracker.md`.

### Nhãn triage

Bộ nhãn mặc định: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. Xem `docs/agents/triage-labels.md`.

### Tài liệu domain

Single-context: một `GLOSSARY.md` + `docs/adr/` ở thư mục gốc. Xem `docs/agents/domain.md`.
