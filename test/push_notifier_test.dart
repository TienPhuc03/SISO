import 'package:flutter_test/flutter_test.dart';
import 'package:siso_project/src/core/push/push_notifier.dart';
import 'package:siso_project/src/core/storage/token_storage.dart';
import 'package:siso_project/src/features/auth/domain/auth_user.dart';
import 'package:siso_project/src/features/auth/providers/auth_provider.dart';

class FakePushMessaging implements PushMessaging {
  final calls = <String>[];
  bool offline = false;

  Future<void> _record(String call) async {
    if (offline) throw Exception('offline');
    calls.add(call);
  }

  @override
  Future<void> subscribe(String topic) => _record('sub $topic');
  @override
  Future<void> unsubscribe(String topic) => _record('unsub $topic');
}

AuthSignedIn signedIn(String universityId) => AuthSignedIn(AuthUser(
      id: 'u-$universityId',
      email: 'sv@ut.edu.vn',
      displayName: 'Minh',
      university: CampusInfo(id: universityId, shortCode: 'UTH', name: 'UTH', color: '#0B2545'),
    ));

void main() {
  late FakePushMessaging fcm;
  late InMemoryTokenStorage storage;

  PushNotifier create() =>
      PushNotifier(fcm, storage: storage, firstRetry: const Duration(milliseconds: 10));

  setUp(() {
    fcm = FakePushMessaging();
    storage = InMemoryTokenStorage();
  });

  test('đang kiểm tra phiên thì chưa làm gì', () async {
    final notifier = create();
    await notifier.onAuthChanged(const AuthChecking());
    expect(fcm.calls, isEmpty);
    expect(notifier.state, isNull);
  });

  test('đăng nhập: đăng ký topic trường và lưu lại', () async {
    final notifier = create();
    await notifier.onAuthChanged(signedIn('a'));
    expect(fcm.calls, ['sub university_a']);
    expect(notifier.state, 'university_a');
    expect(storage.values[PushNotifier.topicKey], 'university_a');
  });

  test('mở app còn phiên, topic đã lưu: đăng ký lại (token FCM có thể đã đổi), không bỏ topic', () async {
    storage.values[PushNotifier.topicKey] = 'university_a';
    final notifier = create();
    await notifier.onAuthChanged(signedIn('a'));
    expect(fcm.calls, ['sub university_a']);
    expect(notifier.state, 'university_a');
  });

  test('đổi sang tài khoản trường khác: bỏ topic cũ rồi đăng ký topic mới', () async {
    final notifier = create();
    await notifier.onAuthChanged(signedIn('a'));
    await notifier.onAuthChanged(signedIn('b'));
    expect(fcm.calls, ['sub university_a', 'unsub university_a', 'sub university_b']);
    expect(storage.values[PushNotifier.topicKey], 'university_b');
  });

  test('đăng xuất: bỏ topic và xoá bản lưu; chưa đăng ký gì thì không gọi', () async {
    final notifier = create();
    await notifier.onAuthChanged(const AuthSignedOut());
    expect(fcm.calls, isEmpty);

    await notifier.onAuthChanged(signedIn('a'));
    await notifier.onAuthChanged(const AuthSignedOut());
    expect(fcm.calls, ['sub university_a', 'unsub university_a']);
    expect(notifier.state, isNull);
    expect(storage.values, isEmpty);
  });

  test('đăng nhập rồi đăng xuất liền nhau (không chờ): chỉ áp trạng thái cuối', () async {
    final notifier = create();
    notifier.onAuthChanged(signedIn('a'));
    await notifier.onAuthChanged(const AuthSignedOut());
    expect(fcm.calls, isEmpty);
    expect(notifier.state, isNull);
  });

  test('đăng xuất lúc mất mạng: giữ topic đã lưu, có mạng lại thì tự thử lại và bỏ được', () async {
    final notifier = create();
    await notifier.onAuthChanged(signedIn('a'));

    fcm.offline = true;
    await notifier.onAuthChanged(const AuthSignedOut());
    expect(notifier.state, 'university_a');
    expect(storage.values[PushNotifier.topicKey], 'university_a');

    fcm.offline = false;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(fcm.calls.last, 'unsub university_a');
    expect(notifier.state, isNull);
    expect(storage.values, isEmpty);
  });

  test('đăng xuất mất mạng rồi tắt app: lần mở sau (đã đăng xuất) bỏ topic cũ', () async {
    storage.values[PushNotifier.topicKey] = 'university_a';
    final notifier = create();
    await notifier.onAuthChanged(const AuthSignedOut());
    expect(fcm.calls, ['unsub university_a']);
    expect(storage.values, isEmpty);
    notifier.dispose();
  });

  test('đăng nhập trường khác khi topic cũ chưa bỏ được: bỏ topic cũ trước', () async {
    storage.values[PushNotifier.topicKey] = 'university_a';
    final notifier = create();
    await notifier.onAuthChanged(signedIn('b'));
    expect(fcm.calls, ['unsub university_a', 'sub university_b']);
  });
}
