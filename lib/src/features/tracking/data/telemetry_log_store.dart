import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'telemetry_log_recorder.dart';

/// Thông tin một file log đã ghi.
class LogFileInfo {
  const LogFileInfo({required this.file, required this.sizeBytes, required this.modified});

  final File file;
  final int sizeBytes;
  final DateTime modified;

  String get name => file.uri.pathSegments.last;
}

/// Ghi dòng log vào file qua [IOSink] (có đệm sẵn).
class FileLogSink implements LogSink {
  FileLogSink(this.file) : _sink = file.openWrite();

  final File file;
  final IOSink _sink;

  @override
  void writeLine(String line) => _sink.write(line);

  @override
  Future<void> close() async {
    await _sink.flush();
    await _sink.close();
  }
}

/// Thư mục log trên máy: `<Documents của app>/telemetry_logs/`.
///
/// Trên iPhone thư mục này hiện trong ứng dụng Tệp: Trên iPhone > SISO > telemetry_logs
/// (nhờ `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace` trong Info.plist).
class TelemetryLogStore {
  TelemetryLogStore({Future<Directory> Function()? baseDir})
      : _baseDir = baseDir ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _baseDir;

  Future<Directory> directory() async {
    final dir = Directory('${(await _baseDir()).path}${Platform.pathSeparator}telemetry_logs');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<FileLogSink> create(String fileName) async {
    final dir = await directory();
    return FileLogSink(File('${dir.path}${Platform.pathSeparator}$fileName'));
  }

  /// Các file `.jsonl`, mới nhất lên đầu.
  Future<List<LogFileInfo>> list() async {
    final dir = await directory();
    final infos = <LogFileInfo>[];
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.jsonl')) {
        final stat = await entity.stat();
        infos.add(LogFileInfo(file: entity, sizeBytes: stat.size, modified: stat.modified));
      }
    }
    infos.sort((a, b) => b.modified.compareTo(a.modified));
    return infos;
  }

  Future<void> delete(LogFileInfo info) => info.file.delete();

  /// Mở share sheet (AirDrop, Zalo, Mail, Lưu vào Tệp...). [origin] cần cho iPad.
  Future<void> share(LogFileInfo info, {Rect? origin}) => SharePlus.instance.share(
        ShareParams(
          files: [XFile(info.file.path, mimeType: 'application/x-ndjson')],
          subject: 'SISO log ${info.name}',
          sharePositionOrigin: origin,
        ),
      );
}
