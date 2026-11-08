# Walkthrough: Module 4, Cổng Sinh trắc (DSP & FFT chống xe máy)

Ngày: 5/11/2026 · Người làm: DEV 2 (có Claude hỗ trợ) · Trạng thái: chưa commit

Thuật ngữ theo [GLOSSARY.md](../GLOSSARY.md). Bản nháp báo cáo (UC, công thức, Class/Sequence Diagram): [docs/report/module4_biometric_gate.md](report/module4_biometric_gate.md).

## 1. Đã làm gì

**Backend**
- `analyzeGait` (hàm thuần): tính tần số lấy mẫu thật từ `timestamp`, quy đổi m/s² sang G, trừ trung bình, nhân cửa sổ Hann, FFT 256 điểm (`fft-js`), tìm đỉnh trong dải 1,5–4 Hz, nội suy parabol, tính biên độ dáng chạy và độ rõ đỉnh.
- `AntiGigoService.validateBiometrics`: luật một cửa sổ (chỉ xét khi tốc độ ≥ 2,5 m/s): Nhịp bước < 120 SPM, biên độ < 0,2 G, hoặc độ rõ đỉnh < 0,3 thì không qua. Ngưỡng nằm trong hằng số `BIOMETRIC_THRESHOLDS`.
- `TelemetryService.verifyWindow`: cửa sổ đầu tạo Phiên chạy `ACTIVE`; Cổng Động học không qua thì loại ngay; Cổng Sinh trắc không qua 2 cửa sổ liên tiếp thì loại; mỗi lần loại ghi `gigo_audit_logs`; server tự cộng quãng đường và thời gian.
- `POST /api/v1/telemetry/verify`: nhận `sessionId` (không bắt buộc), đúng 256 mẫu (m/s²); phản hồi bọc `BaseResponseDto`.
- Schema `running_sessions`: thêm `status`, `consecutive_biometric_failures`, `updated_at`; bỏ ràng buộc `duration_seconds > 0`.

**Client (Flutter)**
- `TelemetryWindowSource` (giao diện nguồn dữ liệu) và `SimulatedTelemetrySource` (giả lập Chạy bộ / Đi bộ / Xe máy, chạy theo thời gian thực).
- `TelemetryRepository` gọi `verify`, đọc `BaseResponseDto` và body lỗi.
- `TrackingSessionNotifier`: gửi tuần tự từng cửa sổ, nhớ `sessionId`, cập nhật HUD, cảnh báo, trạng thái bị loại.
- `SpeedCadenceHud`, `ActiveRunScreen` (dải vàng, màn hình đỏ + rung, bảng điều khiển giả lập), nút **Chạy** trên `MapScreen`.

### Lệch so với lúc thống nhất (cần bạn biết)

1. **Biên độ tính trong dải bước chân**, không phải RMS toàn phần. Khi viết test tôi phát hiện: điện thoại gắn trên xe máy rung mạnh 10 Hz (0,5 G) có RMS toàn phần vượt 0,2 G, và phần rò phổ làm thuật toán đọc ra ~240 SPM, nên **lọt qua cả ba luật**. Bản cuối chỉ giữ năng lượng trong dải 1,5–4 Hz; chạy bộ thật gần như không đổi, rung động cơ gần như về 0. Có test riêng cho ca này.
2. **Ngưỡng độ rõ đỉnh 0,3 chưa đáng tin**: với nhiễu thuần, giá trị này dao động khoảng 0,3–0,4. Hiện luật biên độ mới là luật thực sự loại xe máy. Cần chọn lại sau khi có dữ liệu thật.
3. **Ghi nhật ký cả lỗi Cổng Động học** (`ERR_201`, `ERR_203`), không chỉ `ERR_202`, vì mọi Phiên bị loại đều cần bằng chứng.
4. **Mã lỗi mới `ERR_204`** (`SESSION_NOT_FOUND`) cho `sessionId` không tồn tại, của người khác, hoặc phiên đã kết thúc. Đã thêm vào bảng mã phía client.

## 2. Các file thay đổi

| File | Thay đổi |
|---|---|
| `backend/src/modules/telemetry/gait-analyzer.ts` | **Mới.** Thuật toán FFT |
| `backend/src/types/fft-js.d.ts` | **Mới.** Khai báo kiểu cho `fft-js` |
| `backend/src/modules/telemetry/anti-gigo.service.ts` | Viết lại `validateBiometrics`; thêm `BIOMETRIC_THRESHOLDS`, `BiometricCheckResult` |
| `backend/src/modules/telemetry/telemetry.service.ts` | Viết lại: `verifyWindow`, Phiên chạy, luật 2 cửa sổ, nhật ký |
| `backend/src/modules/telemetry/telemetry.controller.ts` | Truyền `userId`, bọc `BaseResponseDto`, mô tả Swagger |
| `backend/src/modules/telemetry/telemetry.module.ts` | Đăng ký repository `RunningSession`, `GigoAuditLog` |
| `backend/src/modules/telemetry/dto/telemetry-payload.dto.ts` | `sessionId`, đúng 256 mẫu, đơn vị m/s², `@Min(0)` |
| `backend/src/modules/telemetry/dto/verify-window-response.dto.ts` | **Mới.** Schema phản hồi cho Swagger |
| `backend/src/entities/running-session.entity.ts` | Thêm `status`, `consecutive_biometric_failures`, `updated_at` |
| `backend/src/database/init_schema.sql` | Cột mới + đoạn nâng cấp bảng cũ (idempotent) |
| `backend/src/modules/telemetry/synthetic-imu.fixture.ts` | **Mới.** Mẫu tổng hợp dùng chung cho test |
| `backend/src/modules/telemetry/gait-analyzer.spec.ts` | **Mới.** 11 test |
| `backend/src/modules/telemetry/anti-gigo.service.spec.ts` | Viết lại phần Cổng Sinh trắc (6 test) |
| `backend/src/modules/telemetry/telemetry.service.spec.ts` | **Mới.** 10 test |
| `lib/src/features/tracking/domain/telemetry_window.dart` | **Mới.** `TelemetryWindow`, `TelemetryWindowSource`, `VerifyWindowResult` |
| `lib/src/features/tracking/data/simulated_telemetry_source.dart` | **Mới.** Nguồn giả lập |
| `lib/src/features/tracking/data/telemetry_repository.dart` | **Mới.** Gọi `verify`, đọc phản hồi và lỗi |
| `lib/src/features/tracking/providers/tracking_session_notifier.dart` | Viết lại: `RunState`, `TrackingSessionNotifier`, các provider |
| `lib/src/features/tracking/presentation/speed_cadence_hud.dart` | Viết lại |
| `lib/src/features/tracking/presentation/active_run_screen.dart` | Viết lại |
| `lib/src/features/map/presentation/map_screen.dart` | Thêm nút **Chạy** |
| `lib/src/core/network/api_client.dart` | Thêm `hasAccessToken` |
| `lib/src/core/errors/siso_exceptions.dart` | Thêm `ERR_204` |
| `test/tracking_session_notifier_test.dart` | **Mới.** 10 test |
| `test/telemetry_repository_test.dart` | **Mới.** 9 test |
| `docs/report/module4_biometric_gate.md` | **Mới.** Bản nháp báo cáo |

## 3. Bước bắt buộc trước khi chạy thật: nâng cấp database

Supabase MCP đang ở chế độ chỉ đọc nên tôi **chưa** chạy được. Chưa chạy bước này thì `verify` sẽ lỗi 500, vì bảng chưa có cột `status`.

Mở **Supabase → SQL Editor**, dán và chạy (an toàn khi chạy lại nhiều lần):

```sql
ALTER TABLE public.running_sessions ADD COLUMN IF NOT EXISTS status VARCHAR(20) NOT NULL DEFAULT 'COMPLETED';
ALTER TABLE public.running_sessions ADD COLUMN IF NOT EXISTS consecutive_biometric_failures INT NOT NULL DEFAULT 0;
ALTER TABLE public.running_sessions ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();
ALTER TABLE public.running_sessions ALTER COLUMN distance_meters SET DEFAULT 0;
ALTER TABLE public.running_sessions ALTER COLUMN duration_seconds SET DEFAULT 0;

DO $$
DECLARE
    old_check TEXT;
BEGIN
    FOR old_check IN
        SELECT conname FROM pg_constraint
        WHERE conrelid = 'public.running_sessions'::regclass
          AND contype = 'c'
          AND pg_get_constraintdef(oid) ILIKE '%duration_seconds > 0%'
    LOOP
        EXECUTE format('ALTER TABLE public.running_sessions DROP CONSTRAINT %I', old_check);
    END LOOP;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conrelid = 'public.running_sessions'::regclass
                     AND conname = 'running_sessions_duration_nonnegative') THEN
        ALTER TABLE public.running_sessions
            ADD CONSTRAINT running_sessions_duration_nonnegative CHECK (duration_seconds >= 0);
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conrelid = 'public.running_sessions'::regclass
                     AND conname = 'running_sessions_status_check') THEN
        ALTER TABLE public.running_sessions
            ADD CONSTRAINT running_sessions_status_check CHECK (status IN ('ACTIVE', 'REJECTED', 'COMPLETED'));
    END IF;
END $$;
```

Kiểm tra lại:

```sql
SELECT column_name, data_type, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'running_sessions'
ORDER BY ordinal_position;
```

Mong đợi: có `status` (mặc định `'COMPLETED'`), `consecutive_biometric_failures` (mặc định `0`), `updated_at`.

## 4. Kiểm tra

### 4.1. Test tự động

```bash
cd backend && npm test
```

Kết quả lúc tôi chạy: **43/43 pass** (27 test mới hoặc viết lại cho Module 4).

```bash
flutter test
```

Kết quả lúc tôi chạy: **37/37 pass** (19 test mới). `flutter analyze`: không có lỗi mới, vẫn 4 mục `info` cũ.

### 4.2. Qua Swagger

1. Chạy backend (`cd backend && npm run start:dev`), lấy token và bấm **Authorize** như [test_swagger_module2.md](test_swagger_module2.md), mục 2.
2. Tạo payload 256 mẫu tổng hợp. Chạy trong thư mục `backend/`, đổi `running` thành `walking`, `motorbike` hoặc `still` tuỳ tình huống:

   ```bash
   npx ts-node -T -e "const {SCENARIOS}=require('./src/modules/telemetry/synthetic-imu.fixture'); console.log(JSON.stringify({averageSpeedMps:3.2,horizontalAccuracy:6,isMocked:false,imuSamples:SCENARIOS.running()}))" > ../payload.json
   ```

   Mở `payload.json` ở thư mục gốc repo, copy toàn bộ nội dung. File khoảng 26 KB; nhớ xoá sau khi test, đừng commit.
3. `POST /api/v1/telemetry/verify`, **Try it out**, dán payload, **Execute**.

| Bước | Payload | Mong đợi |
|---|---|---|
| a | `running`, không `sessionId` | `200`; `data.sessionId` có giá trị; `windowPassed: true`; `cadenceSpm` khoảng 159–165 |
| b | `motorbike` (đổi `averageSpeedMps` thành 3.3), thêm `"sessionId": "<id ở bước a>"` | `200`; `windowPassed: false`; `consecutiveFailures: 1` |
| c | Lặp lại bước b | `400`; `code: "ERR_202"`; message có "biên độ" |
| d | Lặp lại bước b lần nữa | `400`; message "SESSION_REJECTED: Phiên chạy đã bị loại" |
| e | `running` với `sessionId` = `00000000-0000-4000-8000-000000000000` | `404`; `code: "ERR_204"` |
| f | `running`, không `sessionId`, `isMocked: true` | `400`; `code: "ERR_201"` (loại ngay ở cửa sổ đầu) |
| g | `walking` với `averageSpeedMps: 1.6`, không `sessionId` | `200`; `windowPassed: true`; `biometricApplied: false` |
| h | Xoá bớt một mẫu trong `imuSamples` (còn 255) | `400`; `HTTP_400`; message "imuSamples must contain at least 256 elements" |

Kiểm tra database sau bước c:

```sql
SELECT id, status, is_valid, rejection_reason, consecutive_biometric_failures, distance_meters, duration_seconds
FROM public.running_sessions ORDER BY created_at DESC LIMIT 3;

SELECT rejection_type, raw_gps_speed_mps, imu_cadence_spm, vertical_energy_g, gps_accuracy_m, created_at
FROM public.gigo_audit_logs ORDER BY created_at DESC LIMIT 3;
```

Mong đợi: phiên ở bước a có `status = REJECTED`, `rejection_reason = ERR_202`, `distance_meters` khoảng 33,3 (cửa sổ a: 3,2 × 5,12; cửa sổ b chỉ bị cảnh báo nên vẫn được cộng: 3,3 × 5,12; cửa sổ c bị loại nên không cộng); `gigo_audit_logs` có một dòng `ERR_202` với `vertical_energy_g` < 0,2.

### 4.3. Qua app (nguồn giả lập)

1. Đã chạy SQL ở mục 3, backend đang chạy.
2. Chạy app:

   ```bash
   flutter run -d chrome
   ```

3. Trên bản đồ, bấm nút **Chạy** (góc dưới phải).
4. Ở bảng "Nguồn giả lập", dán `accessToken` (lấy từ Swagger) vào ô **accessToken**, bấm **Dùng**. Dòng chữ chuyển thành "Đã có JWT.".
5. Chọn **Chạy bộ**, bấm **Bắt đầu chạy**:
   - Tốc độ cập nhật mỗi giây (khoảng 11–12 km/h).
   - Khoảng 5 giây sau, Nhịp bước hiện khoảng **162 SPM**, và mã Phiên chạy hiện dưới nút.
6. Chuyển sang **Xe máy** (không dừng chạy):
   - Cửa sổ kế tiếp: **dải vàng** "Nhịp bước không khớp tốc độ...".
   - Cửa sổ sau đó: **màn hình đỏ "PHIÊN CHẠY BỊ LOẠI" / ERR_202**. Trên điện thoại thật sẽ rung; Chrome không rung.
7. Bấm **Về bản đồ**, rồi vào lại **Chạy**: Phiên chạy mới, trạng thái sạch.
8. Thử luật "đếm lại": chạy **Chạy bộ**, chuyển **Xe máy** đúng một cửa sổ (thấy dải vàng) rồi chuyển lại **Chạy bộ**. Dải vàng tắt và không bị loại.
9. Thử **Đi bộ**: tốc độ 1,6 m/s, dưới ngưỡng 2,5, nên không bị cảnh báo.
10. Thử không có token (tải lại trang, không dán token): bấm **Bắt đầu chạy** thì sau khoảng 5 giây hiện dải đỏ nhạt `[HTTP_401] ...` và dừng chạy. Đây **không** phải màn hình bị loại.

## 5. Checklist để bạn duyệt

- [ ] Đã chạy SQL nâng cấp ở mục 3 trên Supabase.
- [ ] `npm test` 43/43 và `flutter test` 37/37.
- [ ] Swagger: đủ các bước a–h đúng mong đợi; database có phiên `REJECTED` và một dòng nhật ký.
- [ ] App: thấy HUD, dải vàng, màn hình đỏ; luật "đếm lại" đúng; đi bộ không bị cảnh báo.
- [ ] Đồng ý với 4 điểm lệch ở mục 1.
- [ ] Gửi ticket bổ sung hợp đồng cho DEV 1.

## 6. Chưa làm (theo phạm vi đã thống nhất)

- Đọc cảm biến thật và GPS (DEV 1, Module 3). Khi xong, DEV 1 viết một lớp cài đặt `TelemetryWindowSource` rồi đổi `telemetryWindowSourceProvider`.
- Chỉnh ngưỡng bằng dữ liệu thật (ticket #9, buổi test Ngày 13–14).
- Kết thúc Phiên chạy (`ACTIVE` sang `COMPLETED`) và cộng km vào Quỹ Km. Hiện chưa có endpoint kết thúc phiên; việc này thuộc luồng `claim-loop` / kết thúc chạy.
- HMAC chống giả mạo payload (ticket #10).
- `duration_seconds` làm tròn mỗi cửa sổ (5,12 s thành 5 s), nên thời gian có thể thiếu khoảng 2%. Chấp nhận được ở MVP.
