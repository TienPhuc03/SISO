import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:siso_project/src/features/leaderboard/data/leaderboard_repository.dart';
import 'package:siso_project/src/features/leaderboard/domain/leaderboard_models.dart';
import 'package:siso_project/src/features/leaderboard/presentation/leaderboard_screen.dart';
import 'package:siso_project/src/features/leaderboard/providers/season_rank_provider.dart';

class FakeLeaderboardRepository extends LeaderboardRepository {
  FakeLeaderboardRepository({this.scores = const [], this.champions = const [], this.fail = false});

  final List<CampusScore> scores;
  final List<HallOfFameEntry> champions;
  bool fail;
  int scoreCalls = 0;

  @override
  Future<List<CampusScore>> fetchScores() async {
    scoreCalls++;
    if (fail) throw Exception('500');
    return scores;
  }

  @override
  Future<List<HallOfFameEntry>> fetchHallOfFame() async {
    if (fail) throw Exception('500');
    return champions;
  }
}

CampusScore _score(String name, double pct) => CampusScore.fromJson({
      'short_name': name,
      'hex_color': '#FFCC00',
      'total_season_km': 12.5,
      'territory_pct': '40.0',
      'mileage_pct': '60.0',
      'composite_power_pct': pct.toString(),
    });

void main() {
  group('Đọc dữ liệu API', () {
    test('cột NUMERIC dạng chuỗi và FLOAT dạng số đều đọc được', () {
      final s = CampusScore.fromJson({
        'name': 'ĐH Công Nghệ TP.HCM (HUTECH)',
        'short_name': 'HUTECH',
        'hex_color': '#FFCC00',
        'total_season_km': 0,
        'territory_pct': '12.34',
        'mileage_pct': 5.5,
        'composite_power_pct': '0.00',
      });

      expect(s.shortName, 'HUTECH');
      expect(s.color, const Color(0xFFFFCC00));
      expect(s.totalKm, 0);
      expect(s.territoryPct, 12.34);
      expect(s.mileagePct, 5.5);
      expect(s.compositePct, 0);
    });

    test('thiếu short_name thì dùng short_code; giá trị lạ thành 0', () {
      final s = CampusScore.fromJson({'short_code': 'UEF', 'territory_pct': 'không-phải-số'});

      expect(s.shortName, 'UEF');
      expect(s.territoryPct, 0);
    });

    test('Quán quân đọc số Mùa và tên Trường', () {
      final e = HallOfFameEntry.fromJson({
        'season_number': 2,
        'champion_name': 'UEF',
        'hex_color': '#ED1C24',
        'composite_power_pct': 61.25,
      });

      expect(e.seasonNumber, 2);
      expect(e.championName, 'UEF');
      expect(e.compositePct, 61.25);
    });
  });

  group('LeaderboardScreen', () {
    Future<void> pump(WidgetTester tester, FakeLeaderboardRepository repo) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [leaderboardRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: LeaderboardScreen()),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('hiện các Trường đúng thứ tự server trả và số phần trăm', (tester) async {
      await pump(tester, FakeLeaderboardRepository(scores: [_score('UEF', 61.25), _score('HUTECH', 20)]));

      expect(find.text('#1'), findsOneWidget);
      expect(find.text('UEF'), findsOneWidget);
      expect(find.text('61.3%'), findsOneWidget);
      expect(tester.getTopLeft(find.text('UEF')).dy, lessThan(tester.getTopLeft(find.text('HUTECH')).dy));
    });

    testWidgets('chưa có Quán quân thì nói rõ', (tester) async {
      await pump(tester, FakeLeaderboardRepository());

      expect(find.textContaining('Chưa có Quán quân'), findsOneWidget);
    });

    testWidgets('có Quán quân thì hiện tên và Mùa', (tester) async {
      await pump(
        tester,
        FakeLeaderboardRepository(champions: [
          HallOfFameEntry.fromJson({'season_number': 1, 'champion_name': 'FTU2', 'composite_power_pct': 50}),
        ]),
      );

      expect(find.text('FTU2'), findsOneWidget);
      expect(find.text('Mùa 1'), findsOneWidget);
    });

    testWidgets('API lỗi thì báo lỗi, bấm Thử lại thì tải lại được', (tester) async {
      final repo = FakeLeaderboardRepository(scores: [_score('UEF', 10)], fail: true);
      await pump(tester, repo);
      expect(find.byKey(const Key('leaderboard_error')), findsOneWidget);
      expect(find.text('UEF'), findsNothing);

      repo.fail = false;
      await tester.tap(find.text('Thử lại').last);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('leaderboard_error')), findsNothing);
      expect(find.text('UEF'), findsOneWidget);
    });
  });
}
