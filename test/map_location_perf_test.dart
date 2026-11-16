import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:siso_project/src/features/auth/providers/auth_provider.dart';
import 'package:siso_project/src/features/leaderboard/presentation/leaderboard_screen.dart';
import 'package:siso_project/src/features/leaderboard/providers/season_rank_provider.dart';
import 'package:siso_project/src/features/map/data/user_location_source.dart';
import 'package:siso_project/src/features/map/domain/frame_stats.dart';
import 'package:siso_project/src/features/map/domain/play_area.dart';
import 'package:siso_project/src/features/map/presentation/map_screen.dart';
import 'package:siso_project/src/features/map/providers/map_state_notifier.dart';

import 'auth_flow_test.dart' show FakeAuthRepository, student;
import 'leaderboard_test.dart' show FakeLeaderboardRepository;
import 'map_state_notifier_test.dart' show FakeHexagonRepository;

class FakeLocationSource implements UserLocationSource {
  FakeLocationSource(this.position);

  LatLng? position;
  int calls = 0;

  @override
  Future<LatLng?> currentPosition() async {
    calls++;
    return position;
  }

  /// Vị trí máy còn nhớ; mặc định không có.
  LatLng? lastKnown;

  @override
  Future<LatLng?> lastKnownPosition() async => lastKnown;
}

/// Tile nền giả: ảnh PNG trong suốt 1x1, không gọi mạng.
class _BlankTileProvider extends TileProvider {
  static final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
  );

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) => MemoryImage(_png);
}

/// Sinh ô giả có id `s0`, `s1`, … để test không cần thư viện H3 native.
Future<Map<String, List<LatLng>>> _fakeSynthetic(LatLng center, int count) async => {
      for (var i = 0; i < count; i++) 's$i': [center],
    };

Future<Map<String, List<LatLng>>> _fakeBoundaries(List<String> ids) async => {
      for (final id in ids) id: const [LatLng(10.79, 106.72)],
    };

void main() {
  group('PlayArea / cameraTargetFor', () {
    test('trong khu Bình Thạnh: căn tới vị trí người dùng', () {
      const hutech = LatLng(10.8016, 106.7146);
      expect(cameraTargetFor(hutech), hutech);
      expect(PlayArea.contains(PlayArea.landmark81), isTrue);
      expect(PlayArea.contains(const LatLng(10.7705, 106.7215)), isTrue); // Sala
    });

    test('không có GPS hoặc ở ngoài khu (vd. Hà Nội): giữ nguyên camera', () {
      expect(cameraTargetFor(null), isNull);
      expect(cameraTargetFor(const LatLng(21.0285, 105.8542)), isNull);
    });
  });

  group('FrameStats', () {
    List<FrameSample> steady(int count, {int intervalUs = 16667, int costUs = 6000, int startUs = 0}) => [
          for (var i = 0; i < count; i++)
            FrameSample(vsyncStartUs: startUs + i * intervalUs, buildUs: costUs, rasterUs: costUs ~/ 2),
        ];

    test('khung đều 60 Hz: khoảng 60 FPS, không giật, ĐẠT', () {
      final stats = FrameStats.from(steady(120));

      expect(stats.frames, 120);
      expect(stats.fps, closeTo(60, 0.5));
      expect(stats.jankPercent, 0);
      expect(stats.p90BuildMs, closeTo(6, 0.01));
      expect(stats.passed, isTrue);
    });

    test('khoảng nghỉ khi bản đồ đứng yên không kéo FPS xuống', () {
      final stats = FrameStats.from([
        ...steady(60),
        ...steady(60, startUs: 60 * 16667 + 2000000), // nghỉ 2 giây giữa hai lần kéo
      ]);

      expect(stats.fps, closeTo(60, 0.5));
    });

    test('khung 30 Hz và quá ngân sách: CHƯA ĐẠT, tính đúng % giật và khung tệ nhất', () {
      final stats = FrameStats.from([
        ...steady(50, intervalUs: 33333, costUs: 25000),
        const FrameSample(vsyncStartUs: 50 * 33333, buildUs: 40000, rasterUs: 1000),
      ]);

      expect(stats.fps, closeTo(30, 0.5));
      expect(stats.jankPercent, 100);
      expect(stats.worstFrameMs, closeTo(40, 0.01));
      expect(stats.passed, isFalse);
    });

    test('không có khung nào: rỗng, không ĐẠT', () {
      expect(FrameStats.from([]).frames, 0);
      expect(FrameStats.from([]).passed, isFalse);
    });
  });

  group('MapStateNotifier: ô giả cho bảng đo', () {
    Future<MapStateNotifier> loaded() async {
      final notifier = MapStateNotifier(
        repository: FakeHexagonRepository([
          {'h3Index': 'real-1', 'ownerUniversityId': 'uni-hutech', 'hexColor': '#FFCC00'},
          {'h3Index': 's0', 'ownerUniversityId': null, 'hexColor': '#44FFFFFF'}, // trùng id ô giả
        ]),
        boundariesOf: _fakeBoundaries,
        syntheticCells: _fakeSynthetic,
      );
      await notifier.loadHexagons();
      return notifier;
    }

    test('thêm ô giả cho tới đúng tổng 500, giữ nguyên ô thật', () async {
      final notifier = await loaded();

      await notifier.addSyntheticCells(center: PlayArea.landmark81, targetTotal: 500);

      expect(notifier.state, hasLength(500));
      expect(notifier.syntheticCount, 498);
      expect(notifier.state['real-1']!.universityId, 'uni-hutech');
      expect(notifier.state['s0']!.isNeutral, isTrue);
    });

    test('gỡ ô giả trả bản đồ về dữ liệu thật', () async {
      final notifier = await loaded();
      await notifier.addSyntheticCells(center: PlayArea.landmark81, targetTotal: 500);

      notifier.removeSyntheticCells();

      expect(notifier.state.keys, unorderedEquals(['real-1', 's0']));
      expect(notifier.syntheticCount, 0);
    });

    test('đã đủ ô thật thì không thêm ô giả', () async {
      final notifier = await loaded();

      await notifier.addSyntheticCells(center: PlayArea.landmark81, targetTotal: 2);

      expect(notifier.state, hasLength(2));
      expect(notifier.syntheticCount, 0);
    });
  });

  group('MapScreen: căn camera theo GPS và bảng đo', () {
    Future<FakeLocationSource> pumpMap(WidgetTester tester, LatLng? position) async {
      final location = FakeLocationSource(position);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(FakeAuthRepository()..restoredUser = student),
            hexagonRepositoryProvider.overrideWithValue(FakeHexagonRepository([])),
            userLocationSourceProvider.overrideWithValue(location),
            leaderboardRepositoryProvider.overrideWithValue(FakeLeaderboardRepository()),
          ],
          child: MaterialApp(home: MapScreen(tileProvider: _BlankTileProvider())),
        ),
      );
      await tester.pump();
      await tester.pump();
      return location;
    }

    testWidgets('mở bản đồ: tự lấy vị trí một lần và hiện chấm vị trí khi trong khu', (tester) async {
      final location = await pumpMap(tester, const LatLng(10.8016, 106.7146));

      expect(location.calls, 1);
      expect(find.byKey(const Key('user_location_marker')), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('không có GPS: mở bản đồ im lặng, bấm nút thì báo lý do', (tester) async {
      final location = await pumpMap(tester, null);
      expect(find.byType(SnackBar), findsNothing);

      await tester.tap(find.byKey(const Key('my_location_button')));
      await tester.pump();
      await tester.pump();

      expect(location.calls, 2);
      expect(find.textContaining('Không lấy được vị trí'), findsOneWidget);
    });

    testWidgets('ở ngoài khu thi đấu: bấm nút thì báo ngoài khu', (tester) async {
      await pumpMap(tester, const LatLng(21.0285, 105.8542));

      await tester.tap(find.byKey(const Key('my_location_button')));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('ngoài khu thi đấu'), findsOneWidget);
    });

    testWidgets('nút Bảng xếp hạng mở màn hình xếp hạng', (tester) async {
      await pumpMap(tester, null);

      await tester.tap(find.byKey(const Key('leaderboard_button')));
      await tester.pumpAndSettle();

      expect(find.byType(LeaderboardScreen), findsOneWidget);
    });

    testWidgets('nhấn giữ tiêu đề 3 giây mở bảng đo; nhấn ngắn thì không', (tester) async {
      await pumpMap(tester, null);
      final title = find.byKey(const Key('map_title'));

      final quick = await tester.startGesture(tester.getCenter(title));
      await tester.pump(const Duration(seconds: 1));
      await quick.up();
      await tester.pump(const Duration(seconds: 3));
      expect(find.byKey(const Key('perf_panel')), findsNothing);

      final hold = await tester.startGesture(tester.getCenter(title));
      await tester.pump(MapScreen.perfPanelHold);
      await hold.up();
      await tester.pump();
      expect(find.byKey(const Key('perf_panel')), findsOneWidget);

      await tester.tap(find.byKey(const Key('perf_close')));
      await tester.pump();
      expect(find.byKey(const Key('perf_panel')), findsNothing);
    });
  });
}
