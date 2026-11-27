import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:siso_project/src/core/theme/siso_theme.dart';
import 'package:siso_project/src/features/auth/domain/auth_user.dart';
import 'package:siso_project/src/features/auth/providers/auth_provider.dart';
import 'package:siso_project/src/features/university/providers/university_providers.dart';

import 'auth_flow_test.dart' show FakeAuthRepository, student;
import 'university_test.dart' show FakeUniversityRepository;
import 'package:siso_project/src/features/leaderboard/data/leaderboard_repository.dart';
import 'package:siso_project/src/features/leaderboard/domain/leaderboard_models.dart';
import 'package:siso_project/src/features/leaderboard/presentation/leaderboard_screen.dart';
import 'package:siso_project/src/features/leaderboard/providers/season_rank_provider.dart';

class FakeLeaderboardRepository extends LeaderboardRepository {
  FakeLeaderboardRepository({this.scores = const [], this.champions = const [], this.fail = false, this.season});

  final List<CampusScore> scores;
  final ActiveSeason? season;
  final List<HallOfFameEntry> champions;
  bool fail;
  int scoreCalls = 0;

  final List<String?> scoreClusters = [];

  @override
  Future<List<CampusScore>> fetchScores({String? cluster}) async {
    scoreCalls++;
    scoreClusters.add(cluster);
    if (fail) throw Exception('500');
    return scores;
  }

  @override
  Future<ActiveSeason?> fetchActiveSeason() async {
    if (fail) throw Exception('500');
    return season;
  }

  @override
  Future<List<HallOfFameEntry>> fetchHallOfFame({String? cluster}) async {
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

  group('Thời gian Mùa giải', () {
    test('đọc Mùa giải từ API', () {
      final s = ActiveSeason.fromJson({
        'season_number': 2,
        'start_date': '2026-11-01',
        'end_date': '2026-11-30',
        'ends_at': '2026-11-30T17:00:00.000Z',
      });

      expect(s.number, 2);
      expect(s.endDate, DateTime(2026, 11, 30));
      expect(s.endsAt, DateTime.utc(2026, 11, 30, 17));
    });

    test('thời gian còn lại: ngày+giờ, dưới 1 ngày giờ+phút, dưới 1 giờ chỉ phút', () {
      expect(formatSeasonRemaining(const Duration(days: 3, hours: 4, minutes: 59)), '3 ngày 4 giờ');
      expect(formatSeasonRemaining(const Duration(hours: 5, minutes: 12)), '5 giờ 12 phút');
      expect(formatSeasonRemaining(const Duration(minutes: 12, seconds: 30)), '12 phút');
      expect(formatSeasonRemaining(const Duration(seconds: 20)), '1 phút');
    });
  });

  group('LeaderboardScreen', () {
    Future<void> pump(WidgetTester tester, FakeLeaderboardRepository repo, {AuthUser? user}) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          leaderboardRepositoryProvider.overrideWithValue(repo),
          universityRepositoryProvider.overrideWithValue(FakeUniversityRepository()),
          if (user != null) authRepositoryProvider.overrideWithValue(FakeAuthRepository()..restoredUser = user),
        ],
        child: const MaterialApp(home: LeaderboardScreen()),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('mặc định xem Cụm của mình; bấm chip đổi Cụm', (tester) async {
      final repo = FakeLeaderboardRepository(scores: [_score('UEF', 30)]);
      await pump(tester, repo, user: student);

      expect(repo.scoreClusters.last, 'NORTH');
      expect(find.textContaining('· của bạn'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('cluster_SOUTH'))); // thanh chip cuộn ngang
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cluster_SOUTH')));
      await tester.pumpAndSettle();
      expect(repo.scoreClusters.last, 'SOUTH');
    });

    testWidgets('Trường của mình nhận theo id, không theo tên ngắn', (tester) async {
      await pump(
        tester,
        FakeLeaderboardRepository(scores: [
          CampusScore.fromJson({'university_id': 'uni-hutech', 'short_name': 'Khác tên', 'composite_power_pct': 1}),
        ]),
        user: student,
      );
      expect(find.text('Trường của bạn'), findsOneWidget);
    });

    testWidgets('Cụm chưa có Đấu trường: ghi rõ xếp hạng 100% theo Km', (tester) async {
      await pump(
        tester,
        FakeLeaderboardRepository(scores: [
          CampusScore.fromJson({'short_name': 'TDTU', 'cluster_code': 'SOUTH', 'cluster_has_arena': false}),
        ]),
      );
      expect(find.byKey(const Key('cluster_no_arena')), findsOneWidget);
      expect(find.text('Sức mạnh Tổng hợp (100% Km)'), findsOneWidget);
    });

    testWidgets('hiện các Trường đúng thứ tự server trả và số phần trăm', (tester) async {
      await pump(tester, FakeLeaderboardRepository(scores: [_score('UEF', 61.25), _score('HUTECH', 20)]));

      expect(find.text('1'), findsOneWidget);
      expect(find.text('UEF'), findsOneWidget);
      expect(find.text('61,3%'), findsOneWidget);
      expect(tester.getTopLeft(find.text('UEF')).dy, lessThan(tester.getTopLeft(find.text('HUTECH')).dy));
    });

    ActiveSeason seasonEndingIn(Duration left) => ActiveSeason(
          number: 2,
          endDate: DateTime(2026, 11, 30),
          endsAt: DateTime.now().add(left),
        );
    String banner(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('season_banner'))).data!;

    testWidgets('hiện Mùa, thời gian còn lại và ngày kết thúc', (tester) async {
      await pump(tester, FakeLeaderboardRepository(season: seasonEndingIn(const Duration(days: 3, hours: 4, minutes: 30))));

      expect(banner(tester), 'Mùa 2 · còn 3 ngày 4 giờ · kết thúc 30/11');
      expect(tester.widget<Text>(find.byKey(const Key('season_banner'))).style!.color, isNot(SisoColors.danger));
    });

    testWidgets('còn dưới 1 ngày thì đổi màu cảnh báo', (tester) async {
      await pump(tester, FakeLeaderboardRepository(season: seasonEndingIn(const Duration(hours: 5, minutes: 30))));

      expect(banner(tester), startsWith('Mùa 2 · còn 5 giờ'));
      expect(tester.widget<Text>(find.byKey(const Key('season_banner'))).style!.color, SisoColors.danger);
    });

    testWidgets('quá hạn nhưng chưa đóng Mùa thì báo đang tổng kết', (tester) async {
      await pump(tester, FakeLeaderboardRepository(season: seasonEndingIn(const Duration(minutes: -5))));

      expect(banner(tester), 'Mùa 2 · đang tổng kết');
    });

    testWidgets('không có Mùa giải mở thì báo chờ mùa mới', (tester) async {
      await pump(tester, FakeLeaderboardRepository());

      expect(banner(tester), 'Đang chờ mùa mới');
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
