import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:siso_project/src/features/auth/providers/auth_provider.dart';
import 'package:siso_project/src/features/leaderboard/providers/season_rank_provider.dart';
import 'package:siso_project/src/features/map/data/user_location_source.dart';
import 'package:siso_project/src/features/map/domain/play_area.dart';
import 'package:siso_project/src/features/map/presentation/map_screen.dart';
import 'package:siso_project/src/features/map/providers/map_state_notifier.dart';

import 'auth_flow_test.dart' show FakeAuthRepository, student;
import 'leaderboard_test.dart' show FakeLeaderboardRepository;
import 'map_state_notifier_test.dart' show FakeHexagonRepository;

/// GPS giả do test điều khiển: mỗi lần đo GPS mới trả một Completer để test tự hoàn tất.
class ControlledLocationSource implements UserLocationSource {
  ControlledLocationSource({this.lastKnown});

  LatLng? lastKnown;
  final fixes = <Completer<LatLng?>>[];

  @override
  Future<LatLng?> currentPosition() {
    final c = Completer<LatLng?>();
    fixes.add(c);
    return c.future;
  }

  @override
  Future<LatLng?> lastKnownPosition() async => lastKnown;
}

class _BlankTileProvider extends TileProvider {
  static final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
  );

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) => MemoryImage(_png);
}

const hutech = LatLng(10.8016, 106.7146);
const uef = LatLng(10.7987, 106.7163);
const hanoi = LatLng(21.0285, 105.8542);

void main() {
  Future<ControlledLocationSource> pumpMap(WidgetTester tester, {LatLng? lastKnown}) async {
    final source = ControlledLocationSource(lastKnown: lastKnown);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(FakeAuthRepository()..restoredUser = student),
          hexagonRepositoryProvider.overrideWithValue(FakeHexagonRepository([])),
          leaderboardRepositoryProvider.overrideWithValue(FakeLeaderboardRepository()),
          userLocationSourceProvider.overrideWithValue(source),
        ],
        child: MaterialApp(home: MapScreen(tileProvider: _BlankTileProvider())),
      ),
    );
    await tester.pump();
    await tester.pump();
    return source;
  }

  MapCamera camera(WidgetTester tester) => MapCamera.of(tester.element(find.byType(TileLayer)));
  Finder spinnerOnButton() => find.descendant(
        of: find.byKey(const Key('my_location_button')),
        matching: find.byType(CircularProgressIndicator),
      );

  Future<void> resolve(WidgetTester tester, ControlledLocationSource s, LatLng? p) async {
    s.fixes.last.complete(p);
    await tester.pumpAndSettle();
  }

  group('Căn camera tự động khi mở bản đồ', () {
    testWidgets('GPS trong khu: camera về đúng vị trí, zoom 16, có chấm vị trí', (tester) async {
      final s = await pumpMap(tester);
      await resolve(tester, s, hutech);

      expect(camera(tester).center, hutech);
      expect(camera(tester).zoom, MapScreen.userZoom);
      expect(find.byKey(const Key('user_location_marker')), findsOneWidget);
    });

    testWidgets('có vị trí máy còn nhớ: căn NGAY, chưa cần chờ GPS mới; GPS mới về thì tinh chỉnh',
        (tester) async {
      final s = await pumpMap(tester, lastKnown: uef);
      await tester.pumpAndSettle();
      expect(s.fixes, hasLength(1), reason: 'GPS mới vẫn đang đo');
      expect(camera(tester).center, uef);

      await resolve(tester, s, hutech);
      expect(camera(tester).center, hutech);
    });

    testWidgets('vị trí máy còn nhớ ở ngoài khu: không căn theo nó', (tester) async {
      final s = await pumpMap(tester, lastKnown: hanoi);
      await tester.pumpAndSettle();
      expect(camera(tester).center, PlayArea.defaultCenter);
      await resolve(tester, s, null);
      expect(camera(tester).center, PlayArea.defaultCenter);
      expect(find.byType(SnackBar), findsNothing, reason: 'lần tự động không báo lỗi');
    });

    testWidgets('người dùng đã kéo bản đồ trước khi GPS về: camera KHÔNG giật về, chỉ cập nhật chấm vị trí',
        (tester) async {
      final s = await pumpMap(tester);
      await tester.drag(find.byType(FlutterMap), const Offset(-300, 0));
      await tester.pumpAndSettle();
      final afterPan = camera(tester).center;

      await resolve(tester, s, hutech);

      expect(camera(tester).center, afterPan);
      expect(find.byKey(const Key('user_location_marker')), findsOneWidget);
    });

    testWidgets('kéo bản đồ rồi bấm "Vị trí của tôi": vẫn căn về vị trí người dùng', (tester) async {
      final s = await pumpMap(tester);
      await resolve(tester, s, hutech);
      await tester.drag(find.byType(FlutterMap), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(camera(tester).center, isNot(hutech));

      await tester.tap(find.byKey(const Key('my_location_button')));
      await tester.pump();
      await resolve(tester, s, hutech);

      expect(camera(tester).center, hutech);
    });
  });

  group('Bấm "Vị trí của tôi" khi lần lấy GPS tự động còn đang chạy', () {
    testWidgets('nút bấm được, hiện vòng xoay, không gọi GPS lần hai; có vị trí thì căn camera',
        (tester) async {
      final s = await pumpMap(tester);
      expect(spinnerOnButton(), findsNothing, reason: 'lần tự động chạy ngầm');

      await tester.tap(find.byKey(const Key('my_location_button')));
      await tester.pump();
      expect(spinnerOnButton(), findsOneWidget);
      expect(s.fixes, hasLength(1));

      await resolve(tester, s, hutech);
      expect(spinnerOnButton(), findsNothing);
      expect(camera(tester).center, hutech);
    });

    testWidgets('không lấy được GPS: báo lý do (trước đây im lặng)', (tester) async {
      final s = await pumpMap(tester);
      await tester.tap(find.byKey(const Key('my_location_button')));
      await tester.pump();

      await resolve(tester, s, null);

      expect(find.textContaining('Không lấy được vị trí'), findsOneWidget);
      expect(spinnerOnButton(), findsNothing);
    });

    testWidgets('đã kéo bản đồ, bấm nút lúc GPS tự động còn chạy: vẫn căn camera', (tester) async {
      final s = await pumpMap(tester);
      await tester.drag(find.byType(FlutterMap), const Offset(-300, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('my_location_button')));
      await tester.pump();

      await resolve(tester, s, hutech);
      expect(camera(tester).center, hutech);
    });

    testWidgets('GPS mới thất bại nhưng có vị trí máy còn nhớ: căn theo nó và nói rõ', (tester) async {
      final s = await pumpMap(tester, lastKnown: uef);
      await tester.pumpAndSettle();
      await tester.drag(find.byType(FlutterMap), const Offset(-300, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('my_location_button')));
      await tester.pump();

      await resolve(tester, s, null);

      expect(camera(tester).center, uef);
      expect(find.textContaining('vị trí gần nhất máy còn nhớ'), findsOneWidget);
    });

    testWidgets('đang chờ kết quả thì không bấm thêm được (tránh gọi GPS dồn)', (tester) async {
      final s = await pumpMap(tester);
      await resolve(tester, s, hutech);

      await tester.tap(find.byKey(const Key('my_location_button')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('my_location_button')));
      await tester.pump();
      expect(s.fixes, hasLength(2));

      await resolve(tester, s, hutech);
    });
  });
}
