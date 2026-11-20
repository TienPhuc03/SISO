import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:siso_project/src/core/permissions/notification_permission.dart';
import 'package:siso_project/src/core/storage/token_storage.dart';

/// Không gọi hệ điều hành: chỉ đếm số lần xin quyền.
class _FakePermission extends NotificationPermission {
  _FakePermission(TokenStorage storage) : super(storage: storage);

  int requests = 0;

  @override
  Future<bool> request() async {
    requests++;
    return true;
  }
}

void main() {
  late InMemoryTokenStorage storage;
  late _FakePermission permission;

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [notificationPermissionProvider.overrideWithValue(permission)],
      child: const MaterialApp(home: NotificationPermissionPrompt(child: Text('Xếp hạng'))),
    ));
    await tester.pumpAndSettle();
  }

  setUp(() {
    storage = InMemoryTokenStorage();
    permission = _FakePermission(storage);
  });

  testWidgets('lần đầu mở: giải thích lý do, bấm "Bật thông báo" mới xin quyền của hệ điều hành', (tester) async {
    await open(tester);

    expect(find.text('Bật thông báo?'), findsOneWidget);
    expect(permission.requests, 0);
    await tester.tap(find.byKey(const Key('notification_allow')));
    await tester.pumpAndSettle();

    expect(permission.requests, 1);
    expect(storage.values[NotificationPermission.askedKey], isNotNull);
  });

  testWidgets('chọn "Để sau": không xin quyền, lần mở sau không hỏi lại', (tester) async {
    await open(tester);
    await tester.tap(find.text('Để sau'));
    await tester.pumpAndSettle();
    expect(permission.requests, 0);

    await tester.pumpWidget(const SizedBox());
    await open(tester);
    expect(find.text('Bật thông báo?'), findsNothing);
  });
}
