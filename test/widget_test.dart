import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:siso_project/main.dart';
import 'package:siso_project/src/features/auth/providers/auth_provider.dart';

import 'auth_flow_test.dart' show FakeAuthRepository, student;

void main() {
  testWidgets('SisoApp chưa đăng nhập: mở LoginScreen', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
        ],
        child: const SisoApp(),
      ),
    );
    await tester.pump();

    expect(find.text('SISO - Xác thực Sinh viên'), findsOneWidget);
  });

  testWidgets('SisoApp đã đăng nhập: render MapScreen skeleton', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider
              .overrideWithValue(FakeAuthRepository()..restoredUser = student),
        ],
        child: const SisoApp(),
      ),
    );
    await tester.pump();

    expect(find.text('SISO — Đại Chiến Bình Thạnh'), findsOneWidget);
    expect(
      find.text('BỘ ĐẾM SONG SONG: % ĐẤT CHIẾM ĐÓNG & % KM CỐNG HIẾN'),
      findsOneWidget,
    );
  });
}
