import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:siso_project/src/features/auth/data/auth_repository.dart';
import 'package:siso_project/src/features/auth/domain/auth_user.dart';
import 'package:siso_project/src/features/auth/providers/auth_provider.dart';
import 'package:siso_project/src/features/profile/data/profile_repository.dart';
import 'package:siso_project/src/features/profile/domain/profile_models.dart';
import 'package:siso_project/src/features/profile/presentation/profile_screen.dart';
import 'package:siso_project/src/features/profile/presentation/run_detail_screen.dart';
import 'package:siso_project/src/features/profile/providers/profile_providers.dart';

class _SignedOutAuth implements AuthRepository {
  @override
  Future<AuthUser?> restoreSession() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProfileRepository extends ProfileRepository {
  Profile profile = const Profile(
    id: 'u1',
    email: 'minh@ut.edu.vn',
    displayName: 'Minh',
    personalKm: 3.25,
    completedRuns: 2,
    campusShortCode: 'UTH',
    campusColor: '#0B2545',
  );
  final runs = [
    RunSummary(
      sessionId: 's1',
      status: 'COMPLETED',
      sessionType: 'FREE_RUN',
      distanceMeters: 2450,
      durationSeconds: 860,
      hexCount: 0,
      startedAt: DateTime(2026, 11, 20, 16, 14),
    ),
    RunSummary(
      sessionId: 's2',
      status: 'REJECTED',
      sessionType: 'FREE_RUN',
      distanceMeters: 120,
      durationSeconds: 40,
      hexCount: 0,
      rejectionReason: 'ERR_202',
      startedAt: DateTime(2026, 11, 19, 7, 5),
    ),
  ];
  String? savedName;

  @override
  Future<Profile> fetchProfile() async => profile;

  @override
  Future<Profile> updateDisplayName(String displayName) async {
    savedName = displayName;
    return profile;
  }

  @override
  Future<Profile> uploadAvatar(Uint8List bytes, String filename) async => profile;

  @override
  Future<List<RunSummary>> fetchRuns({int limit = 50}) async => runs;

  @override
  Future<RunDetail> fetchRun(String sessionId) async => RunDetail(
        summary: runs.first,
        windows: const [
          RunWindowStat(speedMps: 2.8, cadenceSpm: 168, passed: true),
          RunWindowStat(speedMps: 2.9, cadenceSpm: 172, passed: true),
          RunWindowStat(speedMps: 1.0, cadenceSpm: 0, passed: false),
        ],
        route: const [],
      );
}

void main() {
  group('RunDetail.fromJson', () {
    test('GeoJSON [lng, lat] đổi đúng sang LatLng; đếm Cửa sổ hợp lệ; Nhịp bước TB bỏ Cửa sổ không đo được', () {
      final d = RunDetail.fromJson({
        'sessionId': 's1',
        'status': 'COMPLETED',
        'sessionType': 'FREE_RUN',
        'distanceMeters': 2450.6,
        'durationSeconds': 860,
        'hexCount': 0,
        'rejectionReason': null,
        'startedAt': '2026-11-20T09:14:00.000Z',
        'finishedAt': '2026-11-20T09:28:20.000Z',
        'windows': [
          {'seq': 0, 'speedMps': 2.8, 'cadenceSpm': 168, 'passed': true, 'recordedAt': '2026-11-20T09:14:00.000Z'},
          {'seq': 1, 'speedMps': 1.0, 'cadenceSpm': 0, 'passed': false, 'recordedAt': '2026-11-20T09:14:05.120Z'},
        ],
        'route': {
          'type': 'MultiLineString',
          'coordinates': [
            [
              [106.71, 10.80],
              [106.72, 10.81],
            ],
          ],
        },
      });

      expect(d.summary.km, closeTo(2.4506, 1e-9));
      expect(d.route.single.first, const LatLng(10.80, 106.71));
      expect(d.validWindows, 1);
      expect(d.avgCadence, 168);
    });
  });

  group('ProfileScreen', () {
    late _FakeProfileRepository repo;

    Future<void> pump(WidgetTester tester, Widget home) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_SignedOutAuth()),
          profileRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(home: home),
      ));
      await tester.pumpAndSettle();
    }

    setUp(() => repo = _FakeProfileRepository());

    testWidgets('hiện nickname, Km cá nhân và Lịch sử Phiên chạy (cả Phiên bị loại)', (tester) async {
      await pump(tester, const ProfileScreen());

      expect(find.text('Minh'), findsOneWidget);
      expect(find.text('3,25 km', findRichText: true), findsOneWidget);
      expect(find.text('2,45 km · 14:20'), findsOneWidget);
      expect(find.text('Hợp lệ'), findsOneWidget);
      expect(find.text('Bị loại · ERR_202'), findsOneWidget);
    });

    testWidgets('đổi nickname: gửi tên đã bỏ khoảng trắng', (tester) async {
      await pump(tester, const ProfileScreen());

      await tester.tap(find.byKey(const Key('nickname_edit')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('nickname_field')), '  Minh Mới  ');
      await tester.tap(find.byKey(const Key('nickname_save')));
      await tester.pumpAndSettle();

      expect(repo.savedName, 'Minh Mới');
    });

    testWidgets('bấm một Phiên chạy: mở chi tiết với số liệu và nút Xuất ảnh', (tester) async {
      await pump(tester, const ProfileScreen());

      await tester.tap(find.byKey(const Key('run_s1')));
      await tester.pumpAndSettle();

      expect(find.byType(RunDetailScreen), findsOneWidget);
      expect(find.text('Không có Đường chạy để hiển thị'), findsOneWidget);
      expect(find.text('2/3'), findsOneWidget); // Cửa sổ hợp lệ
      expect(find.text('170 SPM', findRichText: true), findsOneWidget); // Nhịp bước TB, bỏ Cửa sổ 0 SPM
      final export = tester.widget<ButtonStyleButton>(
        find.ancestor(of: find.text('Xuất ảnh'), matching: find.bySubtype<ButtonStyleButton>()),
      );
      expect(export.onPressed, isNotNull);

      await tester.tap(find.text('Xuất ảnh'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('export_save')), findsOneWidget);
      expect(find.text('Lưu vào thư viện ảnh'), findsOneWidget);
      expect(find.byKey(const Key('export_share')), findsOneWidget);
    });
  });
}
