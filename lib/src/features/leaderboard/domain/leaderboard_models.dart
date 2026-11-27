import 'package:flutter/painting.dart';

import '../../map/domain/hex_cell.dart' show parseHexColor;

/// Cột NUMERIC của Postgres về client dạng chuỗi ("12.34"), cột FLOAT dạng số.
double _toDouble(Object? value) => switch (value) {
      num n => n.toDouble(),
      String s => double.tryParse(s) ?? 0,
      _ => 0,
    };

/// Điểm một Trường trong Mùa giải hiện tại (một dòng của `GET /leaderboard/scores`).
class CampusScore {
  const CampusScore({
    this.universityId = '',
    this.clusterCode,
    this.clusterHasArena = true,
    required this.name,
    required this.shortName,
    required this.color,
    required this.totalKm,
    required this.territoryPct,
    required this.mileagePct,
    required this.compositePct,
  });

  factory CampusScore.fromJson(Map<String, dynamic> json) => CampusScore(
        universityId: json['university_id'] as String? ?? '',
        clusterCode: json['cluster_code'] as String?,
        clusterHasArena: json['cluster_has_arena'] as bool? ?? true,
        name: json['name'] as String? ?? '',
        shortName: (json['short_name'] ?? json['short_code'] ?? json['name'] ?? '') as String,
        color: parseHexColor(json['hex_color']),
        totalKm: _toDouble(json['total_season_km']),
        territoryPct: _toDouble(json['territory_pct']),
        mileagePct: _toDouble(json['mileage_pct']),
        compositePct: _toDouble(json['composite_power_pct']),
      );

  final String universityId;
  final String? clusterCode;

  /// false = Cụm chưa có Đấu trường: Sức mạnh Tổng hợp tính 100% theo % Km.
  final bool clusterHasArena;
  final String name;
  final String shortName;
  final Color color;
  final double totalKm;
  final double territoryPct;
  final double mileagePct;
  final double compositePct;
}

/// Quán quân của một Mùa giải đã qua (một dòng của `GET /leaderboard/hall-of-fame`).
class HallOfFameEntry {
  const HallOfFameEntry({
    required this.seasonNumber,
    required this.championName,
    required this.color,
    required this.compositePct,
    this.clusterCode,
  });

  factory HallOfFameEntry.fromJson(Map<String, dynamic> json) => HallOfFameEntry(
        seasonNumber: (json['season_number'] as num?)?.toInt() ?? 0,
        championName: json['champion_name'] as String? ?? 'Không rõ',
        color: parseHexColor(json['hex_color']),
        compositePct: _toDouble(json['composite_power_pct']),
        clusterCode: json['cluster_code'] as String?,
      );

  final String? clusterCode;
  final int seasonNumber;
  final String championName;
  final Color color;
  final double compositePct;
}

/// Mùa giải đang mở (`GET /leaderboard/season`).
class ActiveSeason {
  const ActiveSeason({required this.number, required this.endDate, required this.endsAt});

  /// [endDate] là ngày cuối Mùa (lịch VN) để hiển thị; [endsAt] là lúc hết ngày đó (server tính theo giờ VN).
  factory ActiveSeason.fromJson(Map<String, dynamic> json) => ActiveSeason(
        number: (json['season_number'] as num?)?.toInt() ?? 0,
        endDate: DateTime.parse(json['end_date'] as String),
        endsAt: DateTime.parse(json['ends_at'] as String),
      );

  final int number;
  final DateTime endDate;
  final DateTime endsAt;
}

/// "3 ngày 4 giờ", dưới 1 ngày thì "5 giờ 12 phút", dưới 1 giờ thì "12 phút".
String formatSeasonRemaining(Duration left) {
  if (left.inDays >= 1) return '${left.inDays} ngày ${left.inHours % 24} giờ';
  if (left.inHours >= 1) return '${left.inHours} giờ ${left.inMinutes % 60} phút';
  return '${left.inMinutes < 1 ? 1 : left.inMinutes} phút';
}
