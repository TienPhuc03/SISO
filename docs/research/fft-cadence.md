# Nghiên cứu: FFT và cách tính cadence/biên độ cho `AntiGigoService` (ticket #7)

Ngày: 2026-11-04. Phạm vi: chỉ nghiên cứu, không sửa code, không cài package.

## Kết luận ngắn

1. **Dùng `fft-js` (đã có sẵn trong `backend/package.json`, `^0.0.4`, đã cài trong `node_modules`) là đủ cho MVP.** Đo thực tế trên máy dev: một FFT 256 điểm mất khoảng 0,08 ms. Không cần thư viện nhanh hơn. Nếu sau này cần đổi, `fft.js` (indutny, MIT, có `realTransform`) là ứng viên thay thế.
2. **Phải zero-pad 250 mẫu lên 256.** `fft-js` chỉ chấp nhận độ dài lũy thừa của 2; với 250 mẫu nó ném `TypeError` (đã chạy thử).
3. **Cẩn thận `util.fftFreq` của `fft-js`**: nó tính bước tần số bằng `sampleRate / (bins.length * 2)`, tức giả định chỉ truyền nửa phổ. Nếu truyền phổ đầy đủ N bin thì bước tần số sai một nửa (đã chạy thử: bước in ra là 0,0977 Hz thay vì 0,195 Hz). Nên tự tính `f = k * fs / N`.
4. Độ phân giải tần số: **0,2 Hz = 12 SPM mỗi bin**. Cần nội suy parabol quanh đỉnh để giảm sai số cadence.
5. Payload: khoảng 19 KB JSON (định dạng DTO hiện tại) hoặc 3 KB nếu gửi nhị phân float32; độ trễ chủ yếu do chính cửa sổ 5 s, phần tính toán và mạng không đáng kể.

## 1. Chọn thư viện FFT

| Ứng viên | Ghi chú | Nguồn |
|---|---|---|
| `fft-js` 0.0.4 (đang dùng trong repo) | Cooley-Tukey đệ quy, thuần JS, MIT. Mã nguồn tự ghi "không tối ưu, mục đích giáo dục". Đầu vào phải có độ dài lũy thừa của 2. Trả về mảng `[re, im]`. Bản mới nhất trên npm là 0.0.12; `^0.0.4` với 0.0.x chỉ khớp đúng 0.0.4. | `backend/node_modules/fft-js/src/fft.js`, `fftutil.js`; npm registry `registry.npmjs.org/fft-js` |
| `fft.js` (indutny) 4.0.4 | Radix-4/Radix-2, MIT, `new FFT(size)`, `realTransform(out, in)` cho FFT thực (nhanh hơn), size phải là lũy thừa của 2 và > 1. Benchmark do tác giả tự chạy. | https://github.com/indutny/fft.js ; npm registry `registry.npmjs.org/fft.js` |

Quyết định: giữ `fft-js`. Lý do: đã khai báo dependency, tải tính toán rất nhỏ (cửa sổ 256 điểm, vài giây một lần cho mỗi người chạy). Rủi ro của `fft-js` là bảo trì thấp và API `fftFreq` dễ gây hiểu nhầm; để cô lập rủi ro, bọc trong một hàm `dominantFrequency(samples, fs)` để có thể đổi sang `fft.js` mà không động tới `AntiGigoService`.

Lưu ý: ticket nói "hiện chưa có thư viện FFT", nhưng thực tế `fft-js` đã nằm trong `backend/package.json`; `anti-gigo.service.ts` chưa import nó (đang dùng đếm zero-crossing thay vì FFT).

## 2. Từ gia tốc 50 Hz ra SPM

Các bước (cửa sổ 250 mẫu, `fs = 50 Hz`, 5 s):

1. Độ lớn: `a[i] = sqrt(ax² + ay² + az²)`. Dùng độ lớn để không phụ thuộc hướng cầm điện thoại.
2. **Trừ trung bình** của cửa sổ (`a[i] - mean`), không dùng `|a - 1G|`. Việc này loại bỏ thành phần DC (trọng lực) để bin 0 không lấn át.
3. (Tùy chọn) Nhân cửa sổ Hann để giảm rò phổ.
4. Zero-pad từ 250 lên 256, chạy `fft`, tính `|X[k]|` cho `k = 1 .. N/2`.
5. Chỉ tìm đỉnh trong dải sinh học **1,5 - 4,0 Hz** (90 - 240 SPM), tức bin khoảng 8 đến 20 với N = 256.
6. `f_peak = k_peak * fs / N` (tự tính, xem cảnh báo `fftFreq`). Nội suy parabol với 3 bin quanh đỉnh: `delta = 0,5 * (m[k-1] - m[k+1]) / (m[k-1] - 2*m[k] + m[k+1])`, `f = (k + delta) * fs / N`.
7. `SPM = f_peak * 60` nếu đỉnh là tần số bước.

Cảnh báo bước đơn và bước kép: gia tốc đứng có chu kỳ theo từng bước nên đỉnh thường ở tần số bước (cadence). Thành phần ngang/xoay có thể có đỉnh ở một nửa tần số (chu kỳ sải), phụ thuộc vị trí máy (túi, tay, đai). Nếu có đỉnh phụ ở gấp đôi tần số đỉnh chính với biên độ đáng kể, cân nhắc lấy đỉnh gấp đôi. Đây là suy luận cơ học, cần kiểm chứng bằng dữ liệu thật trước khi chốt ngưỡng.

Về code hiện tại: `validateBiometrics` lấy `|mag - 1.0|` rồi đếm zero-crossing quanh trung bình. Phép trị tuyệt đối "gập" tín hiệu (chỉnh lưu) nên tần số biểu kiến có thể gấp đôi thật, và đếm zero-crossing rất nhạy với nhiễu. Đề xuất: dùng FFT để tính cadence chính thức, giữ zero-crossing làm kiểm tra phụ.

## 3. Độ phân giải tần số của cửa sổ này

- Độ phân giải bin: `df = fs / N`. Với 256 điểm: 50/256 = **0,195 Hz** = 11,7 SPM. Với 250 mẫu thực: 50/250 = 0,2 Hz = 12 SPM.
- Zero-padding 250 lên 256 chỉ nội suy phổ, không tăng độ phân giải thật (do độ dài quan sát 5 s quyết định, `1/T = 0,2 Hz`).
- Hệ quả: nếu không nội suy, SPM bị lượng tử hóa theo bước ~12 SPM, sai số tối đa khoảng +/- 6 SPM. Với ngưỡng `MIN_RUNNING_CADENCE_SPM = 120`, người ở 118 và 124 SPM có thể rơi vào cùng bin. Dùng nội suy parabol và đặt ngưỡng có biên an toàn (ví dụ từ chối dưới 100 SPM thay vì 120).
- Nyquist = 25 Hz, dư xa so với cadence chạy (2 - 4 Hz). Vấn đề là độ phân giải, không phải aliasing.
- Tốc độ lấy mẫu thực: tài liệu Android nói `samplingPeriodUs` chỉ là gợi ý, "events may be received faster or slower than the specified rate" (https://developer.android.com/reference/android/hardware/SensorManager). Không nên giả định đúng 50 Hz: tính `fs` thực từ `timestamp` trong DTO (`fs = (n-1) / (t_last - t_first)`) và cân nhắc nội suy về lưới đều trước FFT. Hiện `timestamp` được nhận nhưng chưa dùng.

## 4. Biên độ đứng (G) và zero-crossing rate

- Biên độ: sau khi trừ trung bình, dùng **RMS** `sqrt(mean((a - mean)²))` (code hiện tại tính đúng đại lượng này) hoặc peak-to-peak (`max - min`). Cần xác minh đơn vị trước khi dùng ngưỡng cố định: Android `TYPE_ACCELEROMETER` báo m/s², không phải G; nếu client gửi m/s² thì phép trừ `1.0` và ngưỡng `amplitude < 0.2` trong `anti-gigo.service.ts` sai thang (~9,81 lần). Cần thống nhất đơn vị giữa client Flutter và server và ghi vào DTO. Phía client chưa được kiểm tra trong ticket này.
- Zero-crossing rate: số lần tín hiệu (đã trừ trung bình) đổi dấu trong cửa sổ chia cho thời gian; với sóng gần hình sin, `f ≈ ZCR / 2`. Chỉ nên dùng làm kiểm tra chéo với FFT vì dễ bị nhiễu làm đếm dư; thêm hysteresis (ngưỡng nhỏ quanh 0) để giảm đếm dư.
- Ý nghĩa chống gian lận: đi xe máy cho đỉnh phổ yếu hoặc ngoài 1,5 - 4,0 Hz và biên độ thấp; chạy bộ thật cho đỉnh rõ trong dải này. Có thể dùng tỉ lệ năng lượng đỉnh trên tổng năng lượng làm thước đo "tính tuần hoàn". Ngưỡng cụ thể cần hiệu chỉnh bằng dữ liệu thu thập.

## 5. Kích thước payload và độ trễ

Một mẫu JSON như `{"ax":0.1234,"ay":-0.4567,"az":1.0123,"timestamp":1729600000000}` dài khoảng 75 byte (ước lượng).

| Cách gửi | 250 mẫu | Ghi chú |
|---|---|---|
| JSON đầy đủ 4 trường (DTO hiện tại), 4 chữ số thập phân | khoảng 19 KB | Ước lượng, chưa đo trên payload thật |
| JSON 3 trục (1 timestamp đầu + `fs`) | khoảng 11 KB | Ước lượng |
| Nhị phân float32 x 3 trục | 3.000 byte (250 x 3 x 4) | Tính chính xác |

Độ trễ ước lượng cho một cửa sổ:
- Thu thập: 5 s (250 / 50), gần như toàn bộ độ trễ. Với cửa sổ trượt (bước 1 s) thì cứ 1 s có một kết quả sau lần đầu.
- Tính FFT + metric ở server: dưới 1 ms (đo 0,08 ms cho FFT 256 điểm bằng `fft-js`).
- Truyền mạng ~19 KB: vài chục đến vài trăm ms trên 4G (ước lượng).
- `ValidationPipe` duyệt 250 phần tử lồng nhau: nhỏ so với phần còn lại.

Điểm cần sửa trước khi cài đặt:
- DTO ghi "Buffer 256 mẫu (5.12s)" và service ghi "Cửa sổ: 256 mẫu", trong khi ticket nêu 250 mẫu (5 s). Cần thống nhất; nếu 250 thì zero-pad lên 256, nếu 256 thì không cần pad.
- `imuSamples` chỉ có `@IsArray()`, không giới hạn kích thước. Nên thêm `@ArrayMinSize` / `@ArrayMaxSize` để chặn payload quá lớn.
- Service bỏ qua kiểm tra khi `imuSamples.length < 64`; FFT chỉ đủ độ phân giải khi gần đủ cửa sổ (từ ~200 mẫu).

## Nguồn

- Mã nguồn `fft-js` đã cài: `backend/node_modules/fft-js/src/fft.js`, `src/fftutil.js`.
- npm registry: https://registry.npmjs.org/fft-js , https://registry.npmjs.org/fft.js
- `fft.js` (indutny): https://github.com/indutny/fft.js
- Android SensorManager: https://developer.android.com/reference/android/hardware/SensorManager
- Mã trong repo: `backend/src/modules/telemetry/anti-gigo.service.ts`, `backend/src/modules/telemetry/dto/telemetry-payload.dto.ts`, `backend/package.json`.
- Các số đo (0,08 ms, lỗi với 250 mẫu, sai `fftFreq`) do tự chạy thử bằng Node trên máy dev. Công thức độ phân giải `fs/N` và nội suy parabol là kiến thức DSP chuẩn, không trích từ một nguồn sơ cấp cụ thể trong lần nghiên cứu này.
