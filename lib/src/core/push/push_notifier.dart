import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/providers/auth_provider.dart';
import '../storage/token_storage.dart';

/// Topic FCM của một trường; backend gửi nhắc Tuần tra vào đây. GIỮ KHỚP `universityTopic` ở backend.
String universityTopic(String universityId) => 'university_$universityId';

/// Các thao tác FCM app cần, tách ra để test thay bằng bản giả.
abstract class PushMessaging {
  Future<void> subscribe(String topic);
  Future<void> unsubscribe(String topic);
}

/// Không có cấu hình Firebase (test, web, máy dev chưa điền .env): bỏ qua thông báo đẩy.
class NoPushMessaging implements PushMessaging {
  const NoPushMessaging();
  @override
  Future<void> subscribe(String topic) async {}
  @override
  Future<void> unsubscribe(String topic) async {}
}

class FirebasePushMessaging implements PushMessaging {
  FirebasePushMessaging() {
    // App đang mở thì hệ điều hành không tự hiện thông báo: iOS bật bằng cờ, Android tự hiện qua local notification.
    _fcm.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);
    if (defaultTargetPlatform == TargetPlatform.android) {
      FirebaseMessaging.onMessage.listen(_showOnAndroid);
    }
  }

  final _fcm = FirebaseMessaging.instance;
  final _local = FlutterLocalNotificationsPlugin();

  @override
  Future<void> subscribe(String topic) async {
    // iOS chỉ đăng ký topic được khi đã có APNs token, mà token đến bất đồng bộ sau lúc mở app.
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      for (var i = 0; i < 10 && await _fcm.getAPNSToken() == null; i++) {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
    await _fcm.subscribeToTopic(topic);
  }
  @override
  Future<void> unsubscribe(String topic) => _fcm.unsubscribeFromTopic(topic);

  Future<void> _showOnAndroid(RemoteMessage message) async {
    final n = message.notification;
    if (n == null) return;
    await _local.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('ic_launcher')),
    );
    await _local.show(
      id: message.messageId.hashCode,
      title: n.title,
      body: n.body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails('patrol_reminder', 'Nhắc Tuần tra',
            importance: Importance.high, priority: Priority.high),
      ),
    );
  }
}

/// Khởi tạo Firebase: đủ 4 giá trị trong `.env` thì dùng chúng, không thì dùng cấu hình native
/// (android/app/google-services.json, ios/Runner/GoogleService-Info.plist).
/// Không có cả hai hoặc lỗi thì trả false: app vẫn chạy, chỉ không có thông báo đẩy.
Future<bool> initFirebase() async {
  if (kIsWeb) return false;
  final ios = defaultTargetPlatform == TargetPlatform.iOS;
  final apiKey = dotenv.env[ios ? 'FIREBASE_IOS_API_KEY' : 'FIREBASE_ANDROID_API_KEY'];
  final appId = dotenv.env[ios ? 'FIREBASE_IOS_APP_ID' : 'FIREBASE_ANDROID_APP_ID'];
  final senderId = dotenv.env['FIREBASE_MESSAGING_SENDER_ID'];
  final projectId = dotenv.env['FIREBASE_PROJECT_ID'];
  final fromEnv = [apiKey, appId, senderId, projectId].every((v) => v != null && v.isNotEmpty);
  try {
    await Firebase.initializeApp(
      options: fromEnv
          ? FirebaseOptions(apiKey: apiKey!, appId: appId!, messagingSenderId: senderId!, projectId: projectId!)
          : null,
    );
    return true;
  } catch (e) {
    debugPrint('Không khởi tạo được Firebase, tắt thông báo đẩy: $e');
    return false;
  }
}

/// main.dart ghi đè bằng [FirebasePushMessaging] khi Firebase đã khởi tạo.
final pushMessagingProvider = Provider<PushMessaging>((ref) => const NoPushMessaging());

/// State = topic máy đang nhận (topic trường của Sinh viên đăng nhập); null = không nhận thông báo đẩy.
/// - Đăng nhập (hoặc mở app còn phiên): đăng ký topic trường, đổi tài khoản khác trường thì bỏ topic cũ.
/// - Đăng xuất: bỏ topic, để người dùng sau trên cùng máy không nhận thông báo của trường cũ.
/// Topic đã đăng ký được lưu lại, nên đăng xuất lúc mất mạng thì vẫn bỏ được topic về sau:
/// thử lại theo nhịp giãn dần (30 s, 1 phút, ... tối đa 10 phút) và ở lần mở app sau.
class PushNotifier extends StateNotifier<String?> {
  PushNotifier(this._messaging, {TokenStorage? storage, this.firstRetry = const Duration(seconds: 30)})
      : _storage = storage ?? SecureTokenStorage(),
        super(null) {
    _queue = _restore();
  }

  static const topicKey = 'siso_push_topic';
  static const maxRetry = Duration(minutes: 10);

  final PushMessaging _messaging;
  final TokenStorage _storage;
  final Duration firstRetry;
  late Future<void> _queue;
  AuthSession? _latest;
  Timer? _retryTimer;
  Duration? _nextRetry;

  /// Xếp hàng để đăng nhập/đăng xuất dồn dập vẫn áp dụng đúng thứ tự.
  Future<void> onAuthChanged(AuthSession session) {
    _latest = session;
    _retryTimer?.cancel();
    return _queue = _queue.then((_) => _apply(session));
  }

  Future<void> _restore() async {
    try {
      final saved = await _storage.read(topicKey);
      if (mounted) state = saved;
    } catch (_) {}
  }

  Future<void> _apply(AuthSession session) async {
    if (session is AuthChecking || !identical(session, _latest)) return;
    final uniId = session is AuthSignedIn ? session.user.university?.id : null;
    final topic = uniId == null ? null : universityTopic(uniId);
    try {
      final current = state;
      if (current != null && current != topic) {
        await _messaging.unsubscribe(current);
        await _save(null);
      }
      // Đăng ký lại cả khi topic đã lưu trùng: lệnh này idempotent, và token FCM có thể đã đổi
      // (cài lại app trên iOS: Keychain còn topic cũ nhưng máy chưa đăng ký với token mới).
      if (topic != null) {
        await _messaging.subscribe(topic);
        await _save(topic);
      }
      _nextRetry = null;
    } catch (e) {
      debugPrint('Đồng bộ topic thông báo đẩy lỗi, sẽ thử lại: $e');
      _scheduleRetry(session);
    }
  }

  Future<void> _save(String? topic) async {
    if (!mounted) return;
    state = topic;
    try {
      topic == null ? await _storage.delete(topicKey) : await _storage.write(topicKey, topic);
    } catch (_) {}
  }

  void _scheduleRetry(AuthSession session) {
    if (!mounted) return;
    final delay = _nextRetry ?? firstRetry;
    _nextRetry = delay * 2 > maxRetry ? maxRetry : delay * 2;
    _retryTimer = Timer(delay, () {
      if (mounted && identical(session, _latest)) _queue = _queue.then((_) => _apply(session));
    });
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }
}

final pushNotifierProvider = StateNotifierProvider<PushNotifier, String?>((ref) {
  final notifier = PushNotifier(ref.watch(pushMessagingProvider));
  ref.listen<AuthSession>(authSessionProvider, (_, next) => notifier.onAuthChanged(next),
      fireImmediately: true);
  return notifier;
});
