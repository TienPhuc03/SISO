import 'dart:convert';

/// Định dạng file log GPS/IMU thật (issue #8): JSON Lines, mỗi dòng một bản ghi.
///
/// - Dòng 1: [TelemetryLogHeader] `{"k":"h", ...}`
/// - Gia tốc: `{"k":"a","t":<ms từ lúc bắt đầu>,"x":..,"y":..,"z":..}`, đơn vị m/s², CÓ trọng lực
///   (giống `accelerometerEventStream` và hợp đồng #3).
/// - GPS: `{"k":"g","t":..,"lat":..,"lng":..,"acc":<m>,"spd":<m/s>,"mock":false}`
///
/// `t` tính theo giờ cảm biến (timestamp của sự kiện), lấy mốc là lúc bấm Bắt đầu.
const telemetryLogFormatVersion = 1;

/// Nhãn dáng di chuyển khi thu mẫu (phục vụ #9).
enum TelemetryLogLabel {
  running('run', 'Chạy bộ'),
  walking('walk', 'Đi bộ'),
  motorbike('motorbike', 'Xe máy'),
  other('other', 'Khác');

  const TelemetryLogLabel(this.code, this.label);
  final String code;
  final String label;

  static TelemetryLogLabel fromCode(String? code) =>
      values.firstWhere((l) => l.code == code, orElse: () => other);
}

class TelemetryLogHeader {
  const TelemetryLogHeader({
    required this.startedAt,
    required this.label,
    this.note = '',
    this.device = '',
    this.platform = '',
    this.version = telemetryLogFormatVersion,
  });

  final int version;
  final DateTime startedAt;
  final TelemetryLogLabel label;
  final String note;
  final String device;
  final String platform;

  Map<String, dynamic> toJson() => {
        'k': 'h',
        'v': version,
        'startedAt': startedAt.toUtc().toIso8601String(),
        'label': label.code,
        'note': note,
        'device': device,
        'platform': platform,
      };

  factory TelemetryLogHeader.fromJson(Map<String, dynamic> json) => TelemetryLogHeader(
        version: (json['v'] as num?)?.toInt() ?? telemetryLogFormatVersion,
        startedAt: DateTime.parse(json['startedAt'] as String),
        label: TelemetryLogLabel.fromCode(json['label'] as String?),
        note: json['note'] as String? ?? '',
        device: json['device'] as String? ?? '',
        platform: json['platform'] as String? ?? '',
      );
}

/// Một mẫu gia tốc kế (m/s², có trọng lực).
class AccelRecord {
  const AccelRecord({required this.tMs, required this.x, required this.y, required this.z});

  final int tMs;
  final double x;
  final double y;
  final double z;

  Map<String, dynamic> toJson() => {'k': 'a', 't': tMs, 'x': _round(x), 'y': _round(y), 'z': _round(z)};
}

/// Một lần nhận vị trí GPS.
class GpsRecord {
  const GpsRecord({
    required this.tMs,
    required this.lat,
    required this.lng,
    required this.accuracyM,
    required this.speedMps,
    required this.isMocked,
  });

  final int tMs;
  final double lat;
  final double lng;
  final double accuracyM;
  final double speedMps;
  final bool isMocked;

  Map<String, dynamic> toJson() => {
        'k': 'g',
        't': tMs,
        'lat': lat,
        'lng': lng,
        'acc': _round(accuracyM, 2),
        'spd': _round(speedMps, 3),
        'mock': isMocked,
      };
}

/// Log đã đọc xong: header + các bản ghi theo thứ tự thời gian.
class TelemetryLog {
  const TelemetryLog({required this.header, required this.accel, required this.gps});

  final TelemetryLogHeader header;
  final List<AccelRecord> accel;
  final List<GpsRecord> gps;

  /// Độ dài log (ms) theo bản ghi cuối cùng.
  int get durationMs {
    final lastA = accel.isEmpty ? 0 : accel.last.tMs;
    final lastG = gps.isEmpty ? 0 : gps.last.tMs;
    return lastA > lastG ? lastA : lastG;
  }

  /// Tần số gia tốc kế thực tế (Hz), 0 nếu quá ít mẫu.
  double get accelRateHz {
    if (accel.length < 2) return 0;
    final spanMs = accel.last.tMs - accel.first.tMs;
    return spanMs <= 0 ? 0 : (accel.length - 1) * 1000 / spanMs;
  }

  /// Đọc nội dung JSON Lines. Bỏ qua dòng trống; dòng hỏng thì ném [FormatException] kèm số dòng.
  static TelemetryLog parse(String content) {
    TelemetryLogHeader? header;
    final accel = <AccelRecord>[];
    final gps = <GpsRecord>[];
    final lines = const LineSplitter().convert(content);

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      try {
        final json = jsonDecode(line) as Map<String, dynamic>;
        switch (json['k']) {
          case 'h':
            header = TelemetryLogHeader.fromJson(json);
          case 'a':
            accel.add(AccelRecord(
              tMs: (json['t'] as num).toInt(),
              x: (json['x'] as num).toDouble(),
              y: (json['y'] as num).toDouble(),
              z: (json['z'] as num).toDouble(),
            ));
          case 'g':
            gps.add(GpsRecord(
              tMs: (json['t'] as num).toInt(),
              lat: (json['lat'] as num).toDouble(),
              lng: (json['lng'] as num).toDouble(),
              accuracyM: (json['acc'] as num).toDouble(),
              speedMps: (json['spd'] as num).toDouble(),
              isMocked: json['mock'] == true,
            ));
          default:
            // Loại bản ghi lạ (bản sau thêm vào): bỏ qua để vẫn đọc được log cũ/mới.
            break;
        }
      } catch (e) {
        throw FormatException('Dòng ${i + 1} của log không hợp lệ: $e');
      }
    }

    if (header == null) {
      throw const FormatException('Log thiếu dòng header {"k":"h"}.');
    }
    accel.sort((a, b) => a.tMs.compareTo(b.tMs));
    gps.sort((a, b) => a.tMs.compareTo(b.tMs));
    return TelemetryLog(header: header, accel: accel, gps: gps);
  }
}

/// Mã hoá một bản ghi thành 1 dòng JSON Lines (có ký tự xuống dòng).
String encodeLogLine(Map<String, dynamic> json) => '${jsonEncode(json)}\n';

/// Tên file log: `siso_<label>_<yyyyMMdd-HHmmss>.jsonl` (giờ máy).
String telemetryLogFileName(TelemetryLogLabel label, DateTime startedAt) {
  String two(int v) => v.toString().padLeft(2, '0');
  final d = startedAt;
  return 'siso_${label.code}_${d.year}${two(d.month)}${two(d.day)}-'
      '${two(d.hour)}${two(d.minute)}${two(d.second)}.jsonl';
}

double _round(double v, [int digits = 4]) {
  final p = _pow10[digits]!;
  return (v * p).roundToDouble() / p;
}

const _pow10 = {2: 100.0, 3: 1000.0, 4: 10000.0};
