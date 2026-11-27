import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:siso_project/src/core/errors/siso_exceptions.dart';
import 'package:siso_project/src/core/storage/token_storage.dart';
import 'package:siso_project/src/features/auth/domain/auth_user.dart';
import 'package:siso_project/src/features/auth/presentation/auth_gate.dart';
import 'package:siso_project/src/features/auth/providers/auth_provider.dart';
import 'package:siso_project/src/features/university/data/university_repository.dart';
import 'package:siso_project/src/features/university/domain/university_catalog.dart';
import 'package:siso_project/src/features/university/presentation/season_switch_prompt.dart';
import 'package:siso_project/src/features/university/providers/university_providers.dart';

import 'auth_flow_test.dart' show FakeAuthRepository, hutech, student;

final testCatalog = UniversityCatalog.fromJson({
  'clusters': [
    {'code': 'NORTH', 'name': 'Cụm Bình Thạnh - Phú Nhuận - Gò Vấp (Khu Bắc & Đông Bắc)'},
    {'code': 'SOUTH', 'name': 'Cụm Khu Nam (Quận 7, Bình Chánh)'},
  ],
  'districts': [
    {'name': 'Bình Thạnh', 'clusterCode': 'NORTH'},
    {'name': 'Bình Chánh', 'clusterCode': 'SOUTH'},
  ],
  'universities': [
    {
      'id': 'uni-hutech',
      'shortName': 'HUTECH',
      'name': 'ĐH Công Nghệ TP.HCM (HUTECH)',
      'district': 'Bình Thạnh',
      'clusterCode': 'NORTH',
      'color': '#FFCC00',
      'verified': true,
    },
    {
      'id': 'uni-ueh-n',
      'shortName': 'UEH Cơ sở N',
      'name': 'ĐH Kinh tế TP.HCM (UEH) - Cơ sở N (Bình Chánh)',
      'parentName': 'UEH',
      'aliases': 'kinh te ueh',
      'district': 'Bình Chánh',
      'clusterCode': 'SOUTH',
      'color': '#005F69',
      'verified': true,
    },
    {
      'id': 'uni-new',
      'shortName': 'ABC',
      'name': 'Trường ABC',
      'district': 'Bình Chánh',
      'clusterCode': 'SOUTH',
      'color': '#E53935',
      'verified': false,
    },
  ],
});

class FakeUniversityRepository extends UniversityRepository {
  @override
  Future<UniversityCatalog> fetchCatalog() async => testCatalog;
}

const newbie = AuthUser(id: 'u9', email: 'a@gmail.com', displayName: 'a', university: null, seasonNumber: 3);

void main() {
  group('Tìm Trường không dấu', () {
    test('foldVietnamese bỏ dấu, chữ thường, gộp khoảng trắng', () {
      expect(foldVietnamese('  Đại Học   KINH TẾ '), 'dai hoc kinh te');
      expect(foldVietnamese('Tôn Đức Thắng'), 'ton duc thang');
    });

    test('khớp tên, tên ngắn, thương hiệu, từ khoá, quận; mọi từ đều phải có', () {
      final all = testCatalog.universities;
      expect(searchUniversities(all, 'kinh tế').map((u) => u.id), ['uni-ueh-n']);
      expect(searchUniversities(all, 'ueh').map((u) => u.id), ['uni-ueh-n']);
      expect(searchUniversities(all, 'binh chanh').map((u) => u.id), containsAll(['uni-ueh-n', 'uni-new']));
      expect(searchUniversities(all, 'kinh te hutech'), isEmpty);
      expect(searchUniversities(all, '   '), hasLength(3));
    });

    test('tên ngắn bắt đầu bằng từ khoá lên trước', () {
      final hits = searchUniversities(testCatalog.universities, 'abc');
      expect(hits.first.id, 'uni-new');
    });
  });

  group('UniversityPickerScreen', () {
    late FakeAuthRepository auth;
    late ProviderContainer container;

    Future<void> pump(WidgetTester tester) async {
      container = ProviderContainer(overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        universityRepositoryProvider.overrideWithValue(FakeUniversityRepository()),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: AuthGate()),
      ));
      await tester.pumpAndSettle();
    }

    setUp(() => auth = FakeAuthRepository()..restoredUser = newbie);

    testWidgets('tài khoản chưa có Trường thấy màn chọn; chọn Trường có sẵn sau khi xác nhận', (tester) async {
      await pump(tester);
      expect(find.byKey(const Key('uni_picker')), findsOneWidget);

      await tester.enterText(find.byKey(const Key('uni_search')), 'ueh');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('uni_uni-hutech')), findsNothing);
      await tester.tap(find.byKey(const Key('uni_uni-ueh-n')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Mùa 3'), findsOneWidget);

      await tester.tap(find.byKey(const Key('uni_confirm')));
      await tester.pumpAndSettle();

      expect(auth.chosen!['universityId'], 'uni-ueh-n');
      final session = container.read(authSessionProvider);
      expect(session is AuthSignedIn && session.user.university != null, isTrue);
      expect(find.byKey(const Key('uni_picker')), findsNothing);
    });

    testWidgets('Trường chờ duyệt có nhãn', (tester) async {
      await pump(tester);
      expect(find.text('Chờ duyệt'), findsOneWidget);
    });

    testWidgets('thêm Trường mới: tên lấy sẵn từ ô tìm, chọn quận thì hiện Cụm, gửi đủ 3 trường', (tester) async {
      await pump(tester);
      await tester.enterText(find.byKey(const Key('uni_search')), 'ĐH Mới Toanh');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('uni_add')));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextFormField, 'ĐH Mới Toanh'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('new_uni_short')), 'DHMT');
      await tester.tap(find.byKey(const Key('new_uni_district')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bình Chánh').last);
      await tester.pumpAndSettle();
      expect(find.text('Cụm Khu Nam (Quận 7, Bình Chánh)'), findsOneWidget);

      await tester.tap(find.byKey(const Key('new_uni_submit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('uni_confirm')));
      await tester.pumpAndSettle();

      expect(auth.chosen, {'universityId': null, 'name': 'ĐH Mới Toanh', 'shortName': 'DHMT', 'district': 'Bình Chánh'});
    });

    testWidgets('server báo đang khoá: hiện lý do, vẫn ở màn chọn', (tester) async {
      auth.chooseError = const SisoException(code: SisoErrorCodes.universityLocked, message: 'Đang khoá đến Mùa 4.');
      await pump(tester);
      await tester.tap(find.byKey(const Key('uni_uni-hutech')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('uni_confirm')));
      await tester.pumpAndSettle();

      expect(find.text('Đang khoá đến Mùa 4.'), findsOneWidget);
      expect(find.byKey(const Key('uni_picker')), findsOneWidget);
    });

    testWidgets('admin không có Trường: bỏ qua màn chọn', (tester) async {
      auth.restoredUser = const AuthUser(id: 'a1', email: 'q@gmail.com', displayName: 'Q', university: null, role: 'admin');
      await pump(tester);
      expect(find.byKey(const Key('uni_picker')), findsNothing);
    });
  });

  group('SeasonSwitchPrompt', () {
    const returning = AuthUser(
      id: 'u1',
      email: 'sv@hutech.edu.vn',
      displayName: 'sv',
      university: hutech,
      canChangeUniversity: true,
      seasonNumber: 4,
    );

    Future<void> pump(WidgetTester tester, AuthUser user, InMemoryTokenStorage storage) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(FakeAuthRepository()..restoredUser = user),
          seasonPromptStorageProvider.overrideWithValue(storage),
          universityRepositoryProvider.overrideWithValue(FakeUniversityRepository()),
        ],
        child: const MaterialApp(home: Scaffold(body: _Gate())),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('đầu Mùa còn đổi được: hỏi một lần mỗi Mùa', (tester) async {
      final storage = InMemoryTokenStorage();
      await pump(tester, returning, storage);
      expect(find.text('Mùa 4 đã bắt đầu'), findsOneWidget);

      await tester.tap(find.byKey(const Key('season_stay')));
      await tester.pumpAndSettle();
      expect(storage.values[seasonPromptKey], '4');

      await pump(tester, returning, storage);
      expect(find.text('Mùa 4 đã bắt đầu'), findsNothing);
    });

    testWidgets('bấm Đổi Trường mở màn chọn', (tester) async {
      await pump(tester, returning, InMemoryTokenStorage());
      await tester.tap(find.byKey(const Key('season_switch')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('uni_picker')), findsOneWidget);
    });

    testWidgets('đang khoá (đã chạy Mùa này): không hỏi', (tester) async {
      await pump(tester, student, InMemoryTokenStorage());
      expect(find.byType(AlertDialog), findsNothing);
    });
  });
}

/// Chờ khôi phục phiên rồi mới gắn SeasonSwitchPrompt (như AuthGate), không dựng cả MapScreen.
class _Gate extends ConsumerWidget {
  const _Gate();

  @override
  Widget build(BuildContext context, WidgetRef ref) => switch (ref.watch(authSessionProvider)) {
        AuthSignedIn() => const SeasonSwitchPrompt(child: Text('map')),
        _ => const SizedBox(),
      };
}
