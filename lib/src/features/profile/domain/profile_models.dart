import 'package:latlong2/latlong.dart';

/// Hồ sơ của chính Sinh viên (`GET /api/v1/profile`).
class Profile {
  const Profile({
    required this.id,
    required this.email,
    required this.displayName,
    required this.personalKm,
    required this.completedRuns,
    this.avatarUrl,
    this.campusShortCode,
    this.campusColor,
  });

  final String id;
  final String email;
  final String displayName;
  final double personalKm;
  final int completedRuns;

  /// Đường dẫn tương đối tới ảnh đại diện (cần JWT); null khi chưa có ảnh.
  final String? avatarUrl;
  final String? campusShortCode;
  final String? campusColor;

  factory Profile.fromJson(Map<String, dynamic> json) {
    final campus = json['university'] as Map<String, dynamic>?;
    return Profile(
      id: json['id'] as String,
      email: json['email'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      personalKm: (json['personalKm'] as num?)?.toDouble() ?? 0,
      completedRuns: (json['completedRuns'] as num?)?.toInt() ?? 0,
      avatarUrl: json['avatarUrl'] as String?,
      campusShortCode: campus?['shortCode'] as String?,
      campusColor: campus?['color'] as String?,
    );
  }
}

/// Một dòng trong Lịch sử Phiên chạy (`GET /api/v1/telemetry/sessions`).
class RunSummary {
  const RunSummary({
    required this.sessionId,
    required this.status,
    required this.sessionType,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.hexCount,
    required this.startedAt,
    this.rejectionReason,
    this.finishedAt,
  });

  final String sessionId;

  /// ACTIVE | REJECTED | COMPLETED
  final String status;

  /// FREE_RUN | ARENA_LOOP
  final String sessionType;
  final double distanceMeters;
  final int durationSeconds;
  final int hexCount;
  final String? rejectionReason;
  final DateTime startedAt;
  final DateTime? finishedAt;

  double get km => distanceMeters / 1000;

  /// km/h; 0 khi chưa có thời gian.
  double get avgSpeedKmh => durationSeconds == 0 ? 0 : km / (durationSeconds / 3600);

  factory RunSummary.fromJson(Map<String, dynamic> json) => RunSummary(
        sessionId: json['sessionId'] as String,
        status: json['status'] as String,
        sessionType: json['sessionType'] as String? ?? 'FREE_RUN',
        distanceMeters: (json['distanceMeters'] as num?)?.toDouble() ?? 0,
        durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
        hexCount: (json['hexCount'] as num?)?.toInt() ?? 0,
        rejectionReason: json['rejectionReason'] as String?,
        startedAt: DateTime.parse(json['startedAt'] as String).toLocal(),
        finishedAt: json['finishedAt'] == null ? null : DateTime.parse(json['finishedAt'] as String).toLocal(),
      );
}

/// Một Cửa sổ của Phiên chạy cho biểu đồ / thống kê.
class RunWindowStat {
  const RunWindowStat({required this.speedMps, required this.cadenceSpm, required this.passed});

  final double speedMps;
  final int cadenceSpm;
  final bool passed;
}

/// Chi tiết Phiên chạy (`GET /api/v1/telemetry/sessions/:id`).
class RunDetail {
  const RunDetail({required this.summary, required this.windows, required this.route});

  final RunSummary summary;
  final List<RunWindowStat> windows;

  /// Đường chạy: mỗi phần tử là một đoạn (tách ở chỗ Tạm dừng / mất tín hiệu).
  final List<List<LatLng>> route;

  int get validWindows => windows.where((w) => w.passed).length;

  /// Nhịp bước trung bình của các Cửa sổ có đo được nhịp bước; null khi không có.
  int? get avgCadence {
    final measured = [for (final w in windows) if (w.cadenceSpm > 0) w.cadenceSpm];
    return measured.isEmpty ? null : (measured.reduce((a, b) => a + b) / measured.length).round();
  }

  factory RunDetail.fromJson(Map<String, dynamic> json) {
    final coordinates = (json['route'] as Map?)?['coordinates'] as List? ?? const [];
    return RunDetail(
      summary: RunSummary.fromJson(json),
      windows: [
        for (final w in json['windows'] as List? ?? const [])
          RunWindowStat(
            speedMps: ((w as Map)['speedMps'] as num).toDouble(),
            cadenceSpm: (w['cadenceSpm'] as num?)?.toInt() ?? 0,
            passed: w['passed'] == true,
          ),
      ],
      // GeoJSON là [lng, lat].
      route: [
        for (final segment in coordinates)
          [for (final p in segment as List) LatLng(((p as List)[1] as num).toDouble(), (p[0] as num).toDouble())],
      ],
    );
  }
}

/// Bỏ [meters] đầu và cuối Đường chạy để ảnh chia sẻ không lộ nơi xuất phát / kết thúc (ký túc xá, nhà trọ).
/// Đoạn còn dưới 2 điểm bị bỏ; Đường chạy ngắn hơn 2 × [meters] thì không còn gì.
List<List<LatLng>> hideRouteEnds(List<List<LatLng>> segments, {double meters = 200}) {
  const distance = Distance(roundResult: false);
  final points = [
    for (var s = 0; s < segments.length; s++)
      for (final p in segments[s]) (s, p),
  ];
  if (points.isEmpty) return const [];

  final travelled = List<double>.filled(points.length, 0);
  for (var i = 1; i < points.length; i++) {
    travelled[i] = travelled[i - 1] + distance.distance(points[i - 1].$2, points[i].$2);
  }
  final total = travelled.last;

  final kept = <List<LatLng>>[];
  int? lastSegment;
  for (var i = 0; i < points.length; i++) {
    if (travelled[i] < meters || travelled[i] > total - meters) continue;
    final (segment, point) = points[i];
    if (segment != lastSegment) {
      kept.add([]);
      lastSegment = segment;
    }
    kept.last.add(point);
  }
  return [for (final s in kept) if (s.length >= 2) s];
}
