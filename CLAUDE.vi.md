# CLAUDE.md

Tệp này cung cấp hướng dẫn cho Claude Code (claude.ai/code) khi làm việc với mã nguồn trong repository này.

## Tổng quan

SISO (Step In Step Out) là ứng dụng chạy bộ chiếm lãnh thổ (gamified) dành cho sinh viên các trường đại học TP.HCM, xếp hạng theo 4 Cụm (Thủ Đức, Trung tâm, Bình Thạnh - Phú Nhuận - Gò Vấp, Khu Nam). Đây là monorepo gồm hai ứng dụng: **client Flutter** (thư mục gốc: `lib/`, `test/`, `pubspec.yaml`) và **backend NestJS** (`backend/`). Tài liệu (tiếng Việt) nằm ở `README.md`, `docs/DEVELOPER_HANDBOOK.md` và `docs/SISO_Timeline_v2.md` (kế hoạch công việc theo ngày).

## Lệnh thường dùng

Backend (chạy trong `backend/`):
- `npm install`, `npm run start:dev` (chế độ watch; Swagger tại `/docs`, Socket.io tại `/turf-ws`), `npm run build`
- `npm test`; chạy một file: `npx jest anti-gigo.service.spec`; chạy một test: `npx jest -t "<tên test>"` (`rootDir` của jest là `src`, khớp với `*.spec.ts`)
- `docker-compose up -d` chạy Postgres/PostGIS + Redis + API ở local (nạp `src/database/init_schema.sql` khi khởi tạo)
- `npm run seed:hexagons` in số ô H3 res 10 của từng Đấu trường từ `src/database/arenas.geojson` (dry-run); thêm `-- --apply` để upsert Đấu trường và nạp `h3_hexagons` vào DB trong `backend/.env` (chạy lại an toàn, giữ chủ ô/HP); `properties.cluster` của mỗi feature đặt Cụm cho Đấu trường (mặc định `NORTH`), ranh giới lấy từ OpenStreetMap
- `src/database/season_automation.sql` chứa các job `pg_cron` (đóng Mùa giải, Hao mòn 24h/48h) trong schema `private` không lộ ra ngoài; chạy riêng trong Supabase SQL Editor (chạy lại an toàn), không chạy qua `init_schema.sql`

Client (thư mục gốc repo):
- `flutter pub get`, `flutter run -d chrome` (hoặc chạy trên thiết bị), `flutter test`, `flutter test test/gigo_filter_test.dart`, `flutter analyze`
- Biến môi trường lấy từ `.env` ở thư mục gốc (sao chép từ `.env.example`): `API_BASE_URL`, `SOCKET_URL` (máy ảo Android cần `http://10.0.2.2:3000`, thiết bị thật cần IP LAN).

Biến môi trường của backend lấy từ `backend/.env` (sao chép từ `backend/.env.example`): `DATABASE_URL` hoặc nhóm `DB_*`, `DB_SSL`, `REDIS_*`, `JWT_SECRET`, tuỳ chọn `GOOGLE_APPLICATION_CREDENTIALS` (file service account Firebase, bật thông báo đẩy FCM), `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY` (đăng ảnh diễn đàn; thiếu thì chỉ đăng chữ, ERR_114) và `TELEMETRY_ALLOW_FAST_REPLAY` (chỉ máy dev: nhận cửa sổ telemetry nhanh hơn thời gian thật, nếu không sẽ bị bỏ với ERR_207).

## Kiến trúc

**Server là nguồn chân lý duy nhất.** Client chỉ gửi dữ liệu telemetry thô (GPS + mẫu IMU 50 Hz) và các chỉ mục H3 của đường biên. Việc một phiên chạy có hợp lệ hay không (anti-GIGO) và đất có được chiếm hay không (flood fill) chỉ do backend quyết định. Client không bao giờ truy cập trực tiếp CSDL; chỉ dùng REST (`ApiClient`, Dio) và WebSocket (`SocketManager`).

Backend (`backend/src/`): các module nghiệp vụ trong `modules/` — `auth` (email bất kỳ + OTP, hoặc Google qua Firebase ID token → JWT, `JwtAuthGuard`), `telemetry` (`AntiGigoService`: kiểm tra động học, sau đó kiểm tra nhịp bước/FFT từ IMU để loại xe máy và GPS giả), `turf` (`H3Service` loang vòng khép kín thành các ô lục giác bên trong; `TurfService` thực hiện chiếm đất), `realtime` (`TurfGateway` phát sự kiện đổi chủ ô), `leaderboard` (hai bộ đếm song song: % đất và % km, theo Cụm qua `v_campus_live_scores.cluster_code`), `forum` (bài đăng tối đa 4 ảnh lưu ở bucket Supabase Storage public `forum` qua `ForumImageStore`, đính kèm Phiên chạy hợp lệ, tym, bình luận một tầng, báo cáo; đọc cần JWT, viết cần `NotBannedGuard`; admin kiểm duyệt ở `admin/forum-moderation.service.ts`), `universities` (`GET /universities` danh mục, `PUT /universities/mine` chọn / thêm Trường theo luật khoá Mùa trong `university-lock.ts`), `notifications` (thông báo đẩy FCM: mỗi giờ nhắc Tuần tra vào topic `university_<id>` của từng trường; tắt nếu thiếu `GOOGLE_APPLICATION_CREDENTIALS`; phía app là `lib/src/core/push/push_notifier.dart`). Các TypeORM entity nằm trong `entities/` và phải được khai báo thủ công trong `app.module.ts`. `synchronize` là **false**: schema nằm trong `src/database/init_schema.sql` (PostGIS, `pg_cron`; chạy thủ công trên Supabase hoặc qua docker init), nên thay đổi entity cần sửa SQL tương ứng.

Dùng chung toàn hệ thống: `ValidationPipe` toàn cục (whitelist + forbidNonWhitelisted, nên mọi trường của request đều cần decorator trong DTO) và `AllExceptionsFilter` (`common/filters`). Lỗi được ném dưới dạng `BadRequestException({ code: 'ERR_xxx', message })` theo bảng mã lỗi chung (ERR_201 GPS giả, ERR_202 vận tốc không khớp nhịp bước, ERR_301 vòng lặp vượt quá 150 ô, ERR_106 tài khoản bị khoá, ERR_109 chưa chọn Trường, ERR_110/111 chưa bật đăng nhập Google/token Google sai, ERR_112 đang khoá Trường theo Mùa, ERR_113 quận không hợp lệ, ERR_114 chưa bật lưu ảnh diễn đàn, ERR_115 bài rỗng / quá nhiều ảnh, ERR_116 Phiên chạy đính kèm không hợp lệ, ERR_117 không phải tác giả, ERR_306 Đấu trường thuộc Cụm khác; chỉ dùng cho admin: ERR_107 không phải admin, ERR_108 thao tác admin xung đột; bản tương ứng phía client ở `lib/src/core/errors/siso_exceptions.dart`).

Quy tắc bất biến: độ phân giải H3 là 10 ở mọi nơi (client và server); một vòng chiếm đất không được vượt quá 150 ô.

Client (`lib/src/`): tổ chức theo tính năng (feature-first) tại `features/{auth,map,tracking,leaderboard}`, mỗi tính năng chia thành `data/` (repository), `domain/` (Dart thuần như `KalmanFilter`, `AccelBuffer`), `presentation/`, `providers/` (Riverpod notifier). Mã dùng chung nằm trong `core/`.

Web admin (`admin/`, Vite + React + TS, shadcn/ui, TanStack Query/Table, Recharts, MapLibre + h3-js): `npm install`, `npm run dev` (cổng 5173, `VITE_API_BASE_URL` trong `admin/.env`, mặc định `http://localhost:3000`), `npm run build`, `npm test` (tự kiểm tra logic bản đồ). Phía backend là `modules/admin` (`api/v1/admin/*`, mọi route qua `JwtAuthGuard` + `AdminGuard` nhờ decorator `@AdminController()`). JWT không chứa role: `AdminGuard` và `NotBannedGuard` (`common/guards/account.guards.ts`) đọc `users.role` / `users.banned_until` từ DB mỗi request. Sinh viên bị khoá nhận ERR_106 (chưa chọn Trường nhận ERR_109) ở `telemetry/verify`, `telemetry/finish` và `turf/claim-loop`; khi khoá, các Phiên ACTIVE của họ bị loại luôn (nếu không `finish_stale_sessions` sẽ cộng km). Mọi thao tác thay đổi dữ liệu của admin ghi `admin_actions` trong cùng transaction. Cấp admin bằng SQL (xem `admin/README.md`); admin không thuộc Trường nào. Đăng nhập bằng email bất kỳ (`auth/email-login` + `verify-otp`) hoặc Google (`auth/google`: app đăng nhập Firebase Auth rồi gửi Firebase ID token; `GoogleIdTokenVerifier` kiểm tra bằng cùng service account với FCM, nên thiếu `GOOGLE_APPLICATION_CREDENTIALS` thì tắt đăng nhập Google). Cùng email (đã chuẩn hoá) là cùng tài khoản. Tài khoản mới chưa có Trường (`AuthGate` hiện `UniversityPickerScreen`, admin bỏ qua); trigger `assign_university_id` theo đuôi email đã bị bỏ. Mỗi dòng `universities` là một cơ sở; bảng `districts` ánh xạ quận -> `clusters` (sửa ánh xạ ở `init_schema.sql` mục 6C). Trường Sinh viên tự thêm có `is_verified = false` (admin duyệt / gộp / xoá). Xem `docs/adr/0002-xep-hang-theo-cum-va-co-so.md`.

CI: `.github/workflows/build_ios.yml` build IPA iOS chưa ký (cho Sideloadly) trên macOS khi push lên `develop`/`main`.

## Ghi chú

- `.claude/skills/` và `.agents/skills/` chứa các skill Supabase được đưa vào sẵn (theo dõi qua `skills-lock.json`); không phải mã nguồn dự án.
- Đăng nhập demo: email bất kỳ cùng mã OTP `123456` (khi bật `OTP_DEV_MODE`).


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
