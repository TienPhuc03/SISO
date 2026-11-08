import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:siso_project/src/core/errors/siso_exceptions.dart';
import 'package:siso_project/src/features/auth/data/auth_repository.dart';
import 'package:siso_project/src/features/auth/domain/auth_user.dart';
import 'package:siso_project/src/features/auth/presentation/auth_gate.dart';
import 'package:siso_project/src/features/auth/providers/auth_provider.dart';

const hutech = CampusInfo(
  id: 'uni-hutech',
  shortCode: 'HUTECH',
  name: 'ĐH Công Nghệ TP.HCM (HUTECH)',
  color: '#FFCC00',
);
const student = AuthUser(
  id: 'u1',
  email: 'sv@hutech.edu.vn',
  displayName: 'sv',
  university: hutech,
);
const mapTitle = 'SISO — Đại Chiến Bình Thạnh';

/// Repository giả: kịch bản trả lời do từng test đặt.
class FakeAuthRepository implements AuthRepository {
  AuthUser? restoredUser;
  Object? restoreError;
  String correctOtp = '123456';
  Object? requestError;
  Object? verifyError;

  /// Giờ gửi mã giả lập (mặc định: lúc gọi)
  DateTime? sentAtOverride;
  final List<String> otpRequests = [];
  final List<String> verifyAttempts = [];
  int logoutCalls = 0;

  @override
  Future<AuthUser?> restoreSession() async {
    if (restoreError != null) throw restoreError!;
    return restoredUser;
  }

  @override
  Future<OtpRequestResult> requestOtp(String rawEmail) async {
    otpRequests.add(rawEmail.trim().toLowerCase());
    if (requestError != null) throw requestError!;
    return OtpRequestResult(
      email: rawEmail.trim().toLowerCase(),
      message: 'Mã OTP đã được gửi về hộp thư ${rawEmail.trim().toLowerCase()}.',
      expiresInSeconds: 300,
      resendAfterSeconds: 60,
      university: hutech,
      sentAt: sentAtOverride ?? DateTime.now(),
    );
  }

  @override
  Future<AuthUser> verifyOtp(String rawEmail, String otp) async {
    verifyAttempts.add(otp);
    if (verifyError != null) throw verifyError!;
    if (otp != correctOtp) {
      throw const SisoException(
        code: 'ERR_102',
        message: 'Mã OTP không đúng. Bạn còn 4 lần thử.',
      );
    }
    return student;
  }

  @override
  Future<void> logout() async => logoutCalls++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeAuthRepository repo;

  setUp(() => repo = FakeAuthRepository());

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: AuthGate()),
      ),
    );
    await tester.pump(); // restoreSession xong
  }

  Future<void> goToVerify(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('login_email')), 'SV@hutech.edu.vn');
    await tester.tap(find.byKey(const Key('login_submit')));
    await tester.pumpAndSettle();
  }

  group('AuthGate', () {
    testWidgets('chưa đăng nhập: hiện LoginScreen', (tester) async {
      await pumpApp(tester);
      expect(find.text('SISO - Xác thực Sinh viên'), findsOneWidget);
      expect(find.text(mapTitle), findsNothing);
    });

    testWidgets('khôi phục phiên ném lỗi bất ngờ: về Login, không kẹt loading',
        (tester) async {
      repo.restoreError = StateError('storage hỏng');
      await pumpApp(tester);
      expect(find.byKey(const Key('auth_checking')), findsNothing);
      expect(find.text('SISO - Xác thực Sinh viên'), findsOneWidget);
    });

    testWidgets('còn phiên đã lưu: vào thẳng bản đồ', (tester) async {
      repo.restoredUser = student;
      await pumpApp(tester);
      expect(find.text(mapTitle), findsOneWidget);
    });
  });

  group('LoginScreen', () {
    testWidgets('email trống hoặc ngoài 5 trường: báo lỗi, không gọi API',
        (tester) async {
      await pumpApp(tester);

      await tester.tap(find.byKey(const Key('login_submit')));
      await tester.pump();
      expect(find.text('Vui lòng không để trống email'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('login_email')), 'a@gmail.com');
      await tester.tap(find.byKey(const Key('login_submit')));
      await tester.pump();
      expect(find.text('SISO hiện chỉ hỗ trợ HUTECH, UEF, UTH, FTU2, HIU'),
          findsOneWidget);
      expect(repo.otpRequests, isEmpty);
    });

    testWidgets('email hợp lệ: gửi OTP và mở màn nhập mã', (tester) async {
      await pumpApp(tester);
      await goToVerify(tester);

      expect(repo.otpRequests, ['sv@hutech.edu.vn']);
      expect(find.text('Nhập mã OTP'), findsOneWidget);
      expect(find.text(hutech.name), findsOneWidget);
      expect(find.textContaining('sv@hutech.edu.vn'), findsOneWidget);
    });

    testWidgets('backend báo lỗi: hiện đúng message', (tester) async {
      repo.requestError = const SisoException(
        code: 'ERR_103',
        message: 'Vui lòng đợi 40 giây trước khi gửi lại mã OTP.',
      );
      await pumpApp(tester);
      await goToVerify(tester);

      expect(find.text('Vui lòng đợi 40 giây trước khi gửi lại mã OTP.'),
          findsOneWidget);
      expect(find.text('Nhập mã OTP'), findsNothing);
    });
  });

  group('LoginScreen: lỗi bất ngờ và quay lại', () {
    testWidgets('lỗi không phải SisoException: vẫn hiện thông báo', (tester) async {
      repo.requestError = StateError('response sai định dạng');
      await pumpApp(tester);
      await goToVerify(tester);
      expect(find.text(unexpectedAuthError), findsOneWidget);
    });

    testWidgets('quay lại từ màn OTP trong 60s rồi bấm lại: mở lại màn OTP, không gửi mã mới',
        (tester) async {
      await pumpApp(tester);
      await goToVerify(tester);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('SISO - Xác thực Sinh viên'), findsOneWidget);

      await tester.tap(find.byKey(const Key('login_submit')));
      await tester.pumpAndSettle();

      expect(find.text('Nhập mã OTP'), findsOneWidget);
      expect(repo.otpRequests, ['sv@hutech.edu.vn']);
    });

    testWidgets('quay lại sau khi hết 60s: gửi mã mới', (tester) async {
      repo.sentAtOverride = DateTime.now().subtract(const Duration(seconds: 61));
      await pumpApp(tester);
      await goToVerify(tester);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('login_submit')));
      await tester.pumpAndSettle();

      expect(repo.otpRequests, ['sv@hutech.edu.vn', 'sv@hutech.edu.vn']);
    });

    testWidgets('đổi sang email khác: gửi mã mới cho email đó', (tester) async {
      await pumpApp(tester);
      await goToVerify(tester);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('login_email')), 'khac@hutech.edu.vn');
      await tester.tap(find.byKey(const Key('login_submit')));
      await tester.pumpAndSettle();

      expect(repo.otpRequests, ['sv@hutech.edu.vn', 'khac@hutech.edu.vn']);
    });
  });

  group('VerifyScreen', () {
    testWidgets('lỗi không phải SisoException khi xác thực: hiện thông báo chung',
        (tester) async {
      repo.verifyError = StateError('ghi storage lỗi');
      await pumpApp(tester);
      await goToVerify(tester);

      await tester.enterText(find.byKey(const Key('verify_otp')), '123456');
      await tester.pumpAndSettle();

      expect(find.text(unexpectedAuthError), findsOneWidget);
      expect(find.text(mapTitle), findsNothing);
    });

    testWidgets('màn OTP mở với mã gửi 50s trước: chỉ còn chờ 10s', (tester) async {
      repo.sentAtOverride = DateTime.now().subtract(const Duration(seconds: 50));
      await pumpApp(tester);
      await goToVerify(tester);
      expect(find.text('Gửi lại mã sau 10s'), findsOneWidget);
    });

    testWidgets('OTP sai: hiện lỗi và xoá ô nhập', (tester) async {
      await pumpApp(tester);
      await goToVerify(tester);

      await tester.enterText(find.byKey(const Key('verify_otp')), '000000');
      await tester.pumpAndSettle();

      expect(find.text('Mã OTP không đúng. Bạn còn 4 lần thử.'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byKey(const Key('verify_otp'))).controller!.text,
        isEmpty,
      );
    });

    testWidgets('chỉ nhận chữ số, tối đa 6 ký tự', (tester) async {
      await pumpApp(tester);
      await goToVerify(tester);

      await tester.enterText(find.byKey(const Key('verify_otp')), '12a4');
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byKey(const Key('verify_otp'))).controller!.text,
        '124',
      );
      await tester.tap(find.byKey(const Key('verify_submit')));
      await tester.pump();
      expect(find.text('Mã OTP gồm đúng 6 chữ số.'), findsOneWidget);
      expect(repo.verifyAttempts, isEmpty);
    });

    testWidgets('OTP đúng (tự gửi khi đủ 6 số): vào bản đồ, không quay lại được Login',
        (tester) async {
      await pumpApp(tester);
      await goToVerify(tester);

      await tester.enterText(find.byKey(const Key('verify_otp')), '123456');
      await tester.pumpAndSettle();

      expect(repo.verifyAttempts, ['123456']);
      expect(find.text(mapTitle), findsOneWidget);
      expect(find.text('Nhập mã OTP'), findsNothing);
      expect(find.byType(BackButton), findsNothing);
    });

    testWidgets('nút gửi lại khoá 60 giây rồi mới bấm được', (tester) async {
      await pumpApp(tester);
      await goToVerify(tester);

      TextButton resend() =>
          tester.widget<TextButton>(find.byKey(const Key('verify_resend')));
      expect(resend().onPressed, isNull);
      expect(find.text('Gửi lại mã sau 60s'), findsOneWidget);

      await tester.pump(const Duration(seconds: 59));
      expect(find.text('Gửi lại mã sau 1s'), findsOneWidget);
      expect(resend().onPressed, isNull);

      await tester.pump(const Duration(seconds: 1));
      expect(resend().onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('verify_resend')));
      await tester.pump();
      await tester.pump();
      expect(repo.otpRequests, ['sv@hutech.edu.vn', 'sv@hutech.edu.vn']);
      expect(find.text('Gửi lại mã sau 60s'), findsOneWidget);
    });
  });

  group('Đăng xuất', () {
    testWidgets('xác nhận đăng xuất: xoá phiên, về LoginScreen', (tester) async {
      repo.restoredUser = student;
      await pumpApp(tester);

      await tester.tap(find.byKey(const Key('logout_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('logout_confirm')));
      await tester.pumpAndSettle();

      expect(repo.logoutCalls, 1);
      expect(find.text('SISO - Xác thực Sinh viên'), findsOneWidget);
    });

    testWidgets('bấm Huỷ: vẫn ở bản đồ', (tester) async {
      repo.restoredUser = student;
      await pumpApp(tester);

      await tester.tap(find.byKey(const Key('logout_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Huỷ'));
      await tester.pumpAndSettle();

      expect(repo.logoutCalls, 0);
      expect(find.text(mapTitle), findsOneWidget);
    });

    testWidgets('API trả 401 khi đang đăng nhập: tự về LoginScreen',
        (tester) async {
      repo.restoredUser = student;
      await pumpApp(tester);
      final container = ProviderScope.containerOf(
          tester.element(find.byType(AuthGate)));

      // Mô phỏng interceptor của ApiClient gặp 401
      await container.read(authSessionProvider.notifier).logout();
      await tester.pumpAndSettle();

      expect(find.text('SISO - Xác thực Sinh viên'), findsOneWidget);
    });
  });
}
