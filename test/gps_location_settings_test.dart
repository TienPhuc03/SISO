import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:siso_project/src/features/tracking/data/raw_sensor_streams.dart';

void main() {
  test('Android: GPS chạy qua foreground service, thông báo không vuốt mất, icon trỏ đúng drawable', () {
    final s = gpsLocationSettings(TargetPlatform.android);

    expect(s, isA<AndroidSettings>());
    final fg = (s as AndroidSettings).foregroundNotificationConfig!;
    expect(fg.setOngoing, isTrue);
    expect(fg.enableWakeLock, isTrue);
    expect(fg.notificationIcon.name, 'ic_launcher');
    expect(fg.notificationIcon.defType, 'drawable');
    expect(s.intervalDuration, const Duration(seconds: 1));
    expect(s.distanceFilter, 0);
  });

  test('iOS: giữ cấu hình cũ (fitness, không tự ngừng cập nhật)', () {
    final s = gpsLocationSettings(TargetPlatform.iOS);

    expect(s, isA<AppleSettings>());
    expect((s as AppleSettings).pauseLocationUpdatesAutomatically, isFalse);
    expect(s.activityType, ActivityType.fitness);
  });
}
