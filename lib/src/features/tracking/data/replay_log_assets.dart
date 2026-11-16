import 'package:flutter/services.dart';

import '../domain/telemetry_log.dart';

/// Thư mục chứa log thật đã commit (khai báo trong pubspec `assets:`).
const telemetryLogAssetDir = 'assets/telemetry_logs/';

/// Các file `.jsonl` trong [telemetryLogAssetDir], sắp theo tên.
Future<List<String>> listReplayLogAssets([AssetBundle? bundle]) async {
  final manifest = await AssetManifest.loadFromAssetBundle(bundle ?? rootBundle);
  return manifest
      .listAssets()
      .where((p) => p.startsWith(telemetryLogAssetDir) && p.endsWith('.jsonl'))
      .toList()
    ..sort();
}

Future<TelemetryLog> loadReplayLogAsset(String assetPath, [AssetBundle? bundle]) async {
  final content = await (bundle ?? rootBundle).loadString(assetPath, cache: false);
  return TelemetryLog.parse(content);
}

/// Tên file từ đường dẫn asset.
String assetFileName(String assetPath) => assetPath.split('/').last;
