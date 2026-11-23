import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Nhắc Sinh viên khi Tạm dừng lâu: Phiên chạy sắp tự kết thúc.
abstract class PauseReminder {
  Future<void> show();

  /// Gỡ thông báo khi Sinh viên chạy tiếp hoặc Phiên đã kết thúc, để không còn lời nhắc cũ.
  Future<void> cancel();
}

/// Thông báo cục bộ của máy (không qua server). Chưa cấp quyền thông báo thì hệ điều hành tự bỏ qua.
class LocalPauseReminder implements PauseReminder {
  LocalPauseReminder([FlutterLocalNotificationsPlugin? plugin]) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const _id = 2501;
  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;

  Future<void> _init() async {
    if (_ready) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_launcher'),
        // Không tự xin quyền ở đây: quyền thông báo được xin ở màn Xếp hạng.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _ready = true;
  }

  @override
  Future<void> show() async {
    if (kIsWeb) return;
    await _init();
    await _plugin.show(
      id: _id,
      title: 'Phiên chạy sắp tự kết thúc',
      body: 'Bạn đã tạm dừng 25 phút. Chạy tiếp trong 5 phút nữa, nếu không Phiên chạy sẽ tự kết thúc '
          'và lưu quãng đường đã chạy.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails('run_pause', 'Nhắc Phiên chạy',
            importance: Importance.high, priority: Priority.high),
        // Hiện cả khi app đang mở.
        iOS: DarwinNotificationDetails(presentAlert: true, presentBanner: true, presentSound: true),
      ),
    );
  }

  @override
  Future<void> cancel() async {
    if (kIsWeb || !_ready) return;
    await _plugin.cancel(id: _id);
  }
}

final pauseReminderProvider = Provider<PauseReminder>((ref) => LocalPauseReminder());
