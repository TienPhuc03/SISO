import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/token_storage.dart';

/// Xin quyền thông báo đúng lúc cần (khi mở Xếp hạng), và chỉ hỏi một lần trên mỗi máy.
class NotificationPermission {
  NotificationPermission({TokenStorage? storage, FlutterLocalNotificationsPlugin? plugin})
      : _storage = storage ?? SecureTokenStorage(),
        _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const askedKey = 'siso_notification_permission_asked';

  final TokenStorage _storage;
  final FlutterLocalNotificationsPlugin _plugin;

  /// Chưa hỏi lần nào. Lỗi đọc bộ nhớ (vd. trong test) thì coi như đã hỏi, để không làm phiền.
  Future<bool> shouldAsk() async {
    if (kIsWeb) return false;
    try {
      return await _storage.read(askedKey) == null;
    } catch (_) {
      return false;
    }
  }

  /// Đánh dấu đã hỏi (kể cả khi Sinh viên chọn "Để sau": bật lại trong Cài đặt của máy).
  Future<void> markAsked() async {
    try {
      await _storage.write(askedKey, '1');
    } catch (_) {}
  }

  /// Hiện hộp thoại xin quyền của hệ điều hành; trả true nếu được cho phép.
  Future<bool> request() async {
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          // App chỉ có drawable/ic_launcher (không có mipmap).
          android: AndroidInitializationSettings('ic_launcher'),
          // Không xin ngay lúc khởi tạo: chỉ xin ở lời gọi requestPermissions bên dưới.
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) return await android.requestNotificationsPermission() ?? false;
      final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      return await ios?.requestPermissions(alert: true, badge: true, sound: true) ?? false;
    } catch (_) {
      return false;
    }
  }
}

final notificationPermissionProvider = Provider<NotificationPermission>((ref) => NotificationPermission());

/// Bọc màn hình cần thông báo: lần đầu mở thì giải thích lý do rồi mới xin quyền của hệ điều hành.
class NotificationPermissionPrompt extends ConsumerStatefulWidget {
  const NotificationPermissionPrompt({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<NotificationPermissionPrompt> createState() => _NotificationPermissionPromptState();
}

class _NotificationPermissionPromptState extends ConsumerState<NotificationPermissionPrompt> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAsk());
  }

  Future<void> _maybeAsk() async {
    final permission = ref.read(notificationPermissionProvider);
    if (!await permission.shouldAsk() || !mounted) return;
    await permission.markAsked();
    if (!mounted) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.notifications_active_outlined),
        title: const Text('Bật thông báo?'),
        content: const Text(
          'SISO sẽ nhắc bạn khi Ô đất của trường sắp hết Độ bền, để kịp Tuần tra bảo vệ trước khi về Trung lập.',
        ),
        // Nút chính rộng hết khung nên hai nút luôn xếp dọc: nút chính trên, "Để sau" căn giữa bên dưới.
        actionsOverflowAlignment: OverflowBarAlignment.center,
        actionsOverflowDirection: VerticalDirection.up,
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Để sau')),
          FilledButton(
            key: const Key('notification_allow'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Bật thông báo'),
          ),
        ],
      ),
    );
    if (accepted == true) await permission.request();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
