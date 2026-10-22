import 'package:flutter_test/flutter_test.dart';
import 'package:siso_project/src/features/tracking/domain/kalman_filter.dart';

void main() {
  group('Anti-GIGO Kinematic Gate Tests', () {
    final filter = KalmanFilter();

    test('Chấp nhận vận tốc chạy bộ bình thường (~3.5 m/s = 12.6 km/h)', () {
      expect(filter.isValidVelocity(3.5, 1.0), isTrue);
    });

    test('Bác bỏ điểm nhảy vọt GPS bất thường (200m trong 1 giây)', () {
      expect(filter.isValidVelocity(200.0, 1.0), isFalse);
    });
  });
}
