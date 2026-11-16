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
    required this.name,
    required this.shortName,
    required this.color,
    required this.totalKm,
    required this.territoryPct,
    required this.mileagePct,
    required this.compositePct,
  });

  factory CampusScore.fromJson(Map<String, dynamic> json) => CampusScore(
        name: json['name'] as String? ?? '',
        shortName: (json['short_name'] ?? json['short_code'] ?? json['name'] ?? '') as String,
        color: parseHexColor(json['hex_color']),
        totalKm: _toDouble(json['total_season_km']),
        territoryPct: _toDouble(json['territory_pct']),
        mileagePct: _toDouble(json['mileage_pct']),
        compositePct: _toDouble(json['composite_power_pct']),
      );

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
  });

  factory HallOfFameEntry.fromJson(Map<String, dynamic> json) => HallOfFameEntry(
        seasonNumber: (json['season_number'] as num?)?.toInt() ?? 0,
        championName: json['champion_name'] as String? ?? 'Không rõ',
        color: parseHexColor(json['hex_color']),
        compositePct: _toDouble(json['composite_power_pct']),
      );

  final int seasonNumber;
  final String championName;
  final Color color;
  final double compositePct;
}
