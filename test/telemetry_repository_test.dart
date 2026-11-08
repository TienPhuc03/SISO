import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:siso_project/src/features/tracking/data/simulated_telemetry_source.dart';
import 'package:siso_project/src/features/tracking/data/telemetry_repository.dart';
import 'package:siso_project/src/features/tracking/domain/telemetry_window.dart';

void main() {
  group('parseVerifyResult (đọc BaseResponseDto của verify)', () {
    test('đọc đủ các trường trong data', () {
      final r = parseVerifyResult({
        'success': true,
        'message': 'Đã kiểm định cửa sổ cảm biến.',
        'data': {
          'sessionId': 'sess-1',
          'windowPassed': false,
          'consecutiveFailures': 1,
          'biometricApplied': true,
          'cadenceSpm': 98,
          'dominantFrequencyHz': 1.63,
          'amplitudeG': 0.03,
          'peakProminence': 0.35,
          'message': 'nghi đi xe máy',
        },
        'timestamp': '2026-11-05T10:00:00.000Z',
      });

      expect(r.sessionId, 'sess-1');
      expect(r.windowPassed, isFalse);
      expect(r.consecutiveFailures, 1);
      expect(r.cadenceSpm, 98);
    });

    test('sai định dạng thì ném FormatException', () {
      expect(() => parseVerifyResult({'success': false}), throwsFormatException);
      expect(() => parseVerifyResult(null), throwsFormatException);
    });
  });

  group('parseErrorBody (đọc lỗi của AllExceptionsFilter)', () {
    test('đọc code và message', () {
      final e = parseErrorBody({'success': false, 'code': 'ERR_202', 'message': 'xe máy', 'path': '/x'});

      expect(e!.code, 'ERR_202');
      expect(e.message, 'xe máy');
    });

    test('message dạng mảng (lỗi ValidationPipe) được nối lại', () {
      final e = parseErrorBody({'success': false, 'code': 'HTTP_400', 'message': ['a sai', 'b sai']});

      expect(e!.message, 'a sai; b sai');
    });

    test('không phải body lỗi chuẩn thì trả null', () {
      expect(parseErrorBody('Bad Gateway'), isNull);
      expect(parseErrorBody({'success': true}), isNull);
    });
  });

  group('SimulatedTelemetrySource.buildWindow', () {
    test('đúng 256 mẫu, đơn vị m/s² (trục đứng quanh 9,8), timestamp tăng đều 20 ms', () {
      final source = SimulatedTelemetrySource(random: Random(1));
      final w = source.buildWindow();

      expect(w.samples, hasLength(TelemetryWindow.size));
      final meanAz = w.samples.map((s) => s.az).reduce((a, b) => a + b) / w.samples.length;
      expect(meanAz, closeTo(9.8, 0.5));
      expect(w.samples[1].timestampMs - w.samples[0].timestampMs, 20);
    });

    test('cửa sổ sau nối tiếp thời gian cửa sổ trước (không chồng nhau)', () {
      final source = SimulatedTelemetrySource(random: Random(1));
      final first = source.buildWindow();
      final second = source.buildWindow();

      expect(second.samples.first.timestampMs - first.samples.first.timestampMs, 5120);
    });

    test('xe máy có tốc độ chạy (3,4 m/s) để Cổng Sinh trắc phải xét', () {
      final source = SimulatedTelemetrySource(gait: SimulatedGait.motorbike, random: Random(1));

      expect(source.buildWindow().averageSpeedMps, greaterThanOrEqualTo(2.5));
    });

    test('toJson chỉ gửi sessionId khi đã có', () {
      final w = SimulatedTelemetrySource(random: Random(1)).buildWindow();

      expect(w.toJson().containsKey('sessionId'), isFalse);
      expect(w.toJson(sessionId: 'sess-1')['sessionId'], 'sess-1');
      expect((w.toJson()['imuSamples'] as List).first, containsPair('timestamp', isA<int>()));
    });
  });
}
