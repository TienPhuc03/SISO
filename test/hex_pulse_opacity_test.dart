import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:siso_project/src/features/map/domain/hex_cell.dart';
import 'package:siso_project/src/features/map/presentation/hex_pulse_layer.dart';
import 'package:siso_project/src/features/map/presentation/hexagon_layer.dart';
import 'package:siso_project/src/features/map/providers/map_state_notifier.dart';

import 'map_state_notifier_test.dart' show FakeHexagonRepository;

const _a = '8a65b5600007fff';
const _b = '8a65b560000ffff';

Future<Map<String, List<LatLng>>> _boundaries(List<String> ids) async => {
      for (final id in ids) id: const [LatLng(10.79, 106.72), LatLng(10.791, 106.72), LatLng(10.791, 106.721)],
    };

MapStateNotifier _notifier() => MapStateNotifier(
      repository: FakeHexagonRepository([
        {'h3Index': _a, 'ownerUniversityId': null, 'hexColor': '#44FFFFFF'},
        {'h3Index': _b, 'ownerUniversityId': null, 'hexColor': '#44FFFFFF'},
      ]),
      boundariesOf: _boundaries,
    );

Map<String, dynamic> _claim(List<String> hexes) => {
      'universityId': 'uni-uef',
      'hexColor': '#ED1C24',
      'claimedHexes': hexes,
    };

HexCell _cell({String? owner = 'uni', int hp = 100}) => HexCell(
      h3Index: _a,
      universityId: owner,
      color: Colors.red,
      shieldHp: hp,
      boundary: const [],
    );

void main() {
  group('Độ mờ ô theo Độ bền', () {
    test('đầy Độ bền giữ độ đậm gốc; còn 50 thì còn một nửa', () {
      expect(HexagonLayer.fillAlpha(_cell(hp: 100)), closeTo(HexagonLayer.ownedAlpha, 1e-9));
      expect(HexagonLayer.fillAlpha(_cell(hp: 50)), closeTo(HexagonLayer.ownedAlpha / 2, 1e-9));
    });

    test('ô Trung lập không phụ thuộc Độ bền', () {
      expect(HexagonLayer.fillAlpha(_cell(owner: null, hp: 0)), HexagonLayer.neutralAlpha);
    });
  });

  group('claimedCells', () {
    test('chỉ phát các ô thực sự đổi chủ', () async {
      final notifier = _notifier();
      await notifier.loadHexagons();
      final events = <Set<String>>[];
      notifier.claimedCells.listen(events.add);

      notifier.applyHexClaimed(_claim([_a, '8a65b56ffffffff']));
      await Future<void>.delayed(Duration.zero);

      expect(events, const [
        {_a},
      ]);
    });

    test('không có ô nào đổi thì không phát', () async {
      final notifier = _notifier();
      await notifier.loadHexagons();
      final events = <Set<String>>[];
      notifier.claimedCells.listen(events.add);

      notifier.applyHexClaimed(_claim(['8a65b56ffffffff']));
      await Future<void>.delayed(Duration.zero);

      expect(events, isEmpty);
    });
  });

  group('HexPulseLayer', () {
    late MapStateNotifier notifier;

    Future<void> pump(WidgetTester tester) async {
      notifier = _notifier();
      await notifier.loadHexagons();
      await tester.pumpWidget(ProviderScope(
        overrides: [mapStateNotifierProvider.overrideWith((ref) => notifier)],
        child: const MaterialApp(
          home: FlutterMap(
            options: MapOptions(initialCenter: LatLng(10.79, 106.72), initialZoom: 15),
            children: [HexPulseLayer()],
          ),
        ),
      ));
      await tester.pump();
    }

    Finder pulse() => find.byKey(const Key('hex_pulse_layer'));

    Future<void> claim(WidgetTester tester, List<String> hexes) async {
      await tester.runAsync(() async {
        notifier.applyHexClaimed(_claim(hexes));
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
    }

    List<Polygon> polygons(WidgetTester tester) => tester.widget<PolygonLayer>(find.byType(PolygonLayer)).polygons;

    testWidgets('chưa có sự kiện thì không vẽ gì', (tester) async {
      await pump(tester);

      expect(pulse(), findsNothing);
    });

    testWidgets('nhận hex_claimed: nháy đúng ô, dùng màu mới, rồi tự tắt', (tester) async {
      await pump(tester);

      await claim(tester, [_a]);

      expect(pulse(), findsOneWidget);
      expect(polygons(tester), hasLength(1));
      expect(polygons(tester).single.color!.toARGB32() & 0xFFFFFF, 0xED1C24);

      await tester.pump(HexPulseLayer.duration + const Duration(milliseconds: 50));
      await tester.pump();
      expect(pulse(), findsNothing);
    });

    testWidgets('sự kiện mới giữa chừng gộp thêm ô, không làm tắt ô trước', (tester) async {
      await pump(tester);

      await claim(tester, [_a]);
      await tester.pump(const Duration(milliseconds: 200));
      await claim(tester, [_b]);

      expect(polygons(tester), hasLength(2));
    });
  });
}
