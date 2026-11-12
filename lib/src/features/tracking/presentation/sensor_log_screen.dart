import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../data/raw_sensor_streams.dart';
import '../data/telemetry_log_recorder.dart';
import '../data/telemetry_log_store.dart';
import '../domain/telemetry_log.dart';

/// Giữ màn hình sáng khi ghi (iOS ngừng cảm biến khi khoá máy). Override trong test.
abstract class ScreenAwake {
  Future<void> enable();
  Future<void> disable();
}

class WakelockScreenAwake implements ScreenAwake {
  const WakelockScreenAwake();

  @override
  Future<void> enable() => WakelockPlus.enable();

  @override
  Future<void> disable() => WakelockPlus.disable();
}

final rawSensorStreamsProvider = Provider<RawSensorStreams>((ref) => const DeviceSensorStreams());
final telemetryLogStoreProvider = Provider<TelemetryLogStore>((ref) => TelemetryLogStore());
final screenAwakeProvider = Provider<ScreenAwake>((ref) => const WakelockScreenAwake());

/// Dưới mức này coi như cảm biến không đạt 50 Hz (server FFT giả định 50 Hz).
const minHealthyAccelHz = 45.0;

/// Màn GHI LOG cảm biến thật (issue #8, phục vụ #9 và Demo Simulator).
/// Mở bằng cách nhấn giữ nút "Chạy" trên bản đồ. Ghi offline, không cần backend.
class SensorLogScreen extends ConsumerStatefulWidget {
  const SensorLogScreen({super.key});

  @override
  ConsumerState<SensorLogScreen> createState() => _SensorLogScreenState();
}

class _SensorLogScreenState extends ConsumerState<SensorLogScreen> {
  late final TelemetryLogRecorder _recorder;
  final _noteController = TextEditingController();
  TelemetryLogLabel _label = TelemetryLogLabel.running;
  List<LogFileInfo> _files = const [];
  String? _message;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _recorder = TelemetryLogRecorder(sensors: ref.read(rawSensorStreamsProvider));
    _refreshFiles();
  }

  @override
  void dispose() {
    if (_recorder.isRecording) {
      _recorder.stop();
      ref.read(screenAwakeProvider).disable();
    }
    _recorder.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _refreshFiles() async {
    try {
      final files = await ref.read(telemetryLogStoreProvider).list();
      if (mounted) setState(() => _files = files);
    } catch (e) {
      if (mounted) setState(() => _message = 'Không đọc được thư mục log: $e');
    }
  }

  Future<void> _start() async {
    setState(() {
      _starting = true;
      _message = null;
    });
    try {
      final permissionError = await ref.read(rawSensorStreamsProvider).ensureLocationPermission();
      if (permissionError != null) {
        setState(() => _message = permissionError);
        return;
      }
      final startedAt = DateTime.now();
      final sink = await ref.read(telemetryLogStoreProvider).create(telemetryLogFileName(_label, startedAt));
      _recorder.start(
        header: TelemetryLogHeader(
          startedAt: startedAt,
          label: _label,
          note: _noteController.text.trim(),
          platform: kIsWeb ? 'web' : Platform.operatingSystem,
          device: kIsWeb ? '' : Platform.operatingSystemVersion,
        ),
        sink: sink,
      );
      await ref.read(screenAwakeProvider).enable();
    } catch (e) {
      if (mounted) setState(() => _message = 'Không bắt đầu ghi được: $e');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _stop() async {
    final stats = await _recorder.stop();
    await ref.read(screenAwakeProvider).disable();
    if (!mounted) return;
    setState(() => _message =
        'Đã lưu: ${stats.accelCount} mẫu IMU, ${stats.gpsCount} lần GPS trong ${_fmt(stats.elapsed)}.');
    await _refreshFiles();
  }

  Future<void> _share(LogFileInfo info, BuildContext buttonContext) async {
    final box = buttonContext.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    try {
      await ref.read(telemetryLogStoreProvider).share(info, origin: origin);
    } catch (e) {
      if (mounted) setState(() => _message = 'Không chia sẻ được: $e');
    }
  }

  Future<void> _delete(LogFileInfo info) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Xoá log?'),
        content: Text('${info.name} sẽ bị xoá khỏi máy, không khôi phục được.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Huỷ')),
          FilledButton(
            key: const Key('log_delete_confirm'),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Xoá'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(telemetryLogStoreProvider).delete(info);
    await _refreshFiles();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ghi log cảm biến')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Chỉ ghi log được trên điện thoại thật. Trên Chrome, dùng "Phát lại log" ở màn Chạy.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Ghi log cảm biến')),
      body: ListenableBuilder(
        listenable: _recorder,
        builder: (context, _) {
          final recording = _recorder.isRecording;
          final stats = _recorder.stats;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Ghi GPS (1 lần/giây) và gia tốc kế 50 Hz ra file .jsonl để phát lại trên Chrome. '
                'Chỉ ghi ở nơi công cộng; không bắt đầu ghi từ nhà.',
              ),
              const SizedBox(height: 16),
              SegmentedButton<TelemetryLogLabel>(
                segments: [
                  for (final l in TelemetryLogLabel.values) ButtonSegment(value: l, label: Text(l.label)),
                ],
                selected: {_label},
                onSelectionChanged: recording ? null : (s) => setState(() => _label = s.first),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('log_note'),
                controller: _noteController,
                enabled: !recording,
                decoration: const InputDecoration(
                  labelText: 'Ghi chú (nơi ghi, cách cầm máy...)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              recording
                  ? FilledButton.icon(
                      key: const Key('log_stop'),
                      onPressed: _stop,
                      style: FilledButton.styleFrom(backgroundColor: Colors.red),
                      icon: const Icon(Icons.stop),
                      label: const Text('Dừng và lưu'),
                    )
                  : FilledButton.icon(
                      key: const Key('log_start'),
                      onPressed: _starting ? null : _start,
                      icon: const Icon(Icons.fiber_manual_record),
                      label: const Text('Bắt đầu ghi'),
                    ),
              if (recording) ...[
                const SizedBox(height: 12),
                _StatsCard(stats: stats),
              ],
              if (_recorder.error != null) ...[
                const SizedBox(height: 8),
                Text('Lỗi cảm biến: ${_recorder.error}', style: const TextStyle(color: Colors.redAccent)),
              ],
              if (_message != null) ...[
                const SizedBox(height: 8),
                Text(_message!, key: const Key('log_message')),
              ],
              const Divider(height: 32),
              Text('File đã ghi (${_files.length})', style: Theme.of(context).textTheme.titleSmall),
              if (_files.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Chưa có file nào.'),
                ),
              for (final f in _files)
                ListTile(
                  key: Key('log_file_${f.name}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(f.name, style: const TextStyle(fontSize: 13)),
                  subtitle: Text('${(f.sizeBytes / 1024).toStringAsFixed(0)} KB'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Builder(
                        builder: (buttonContext) => IconButton(
                          tooltip: 'Chia sẻ',
                          icon: const Icon(Icons.ios_share),
                          onPressed: () => _share(f, buttonContext),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Xoá',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: recording ? null : () => _delete(f),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.stats});

  final RecorderStats stats;

  @override
  Widget build(BuildContext context) {
    final lowRate = stats.accelCount > 100 && stats.accelRateHz < minHealthyAccelHz;
    return Card(
      key: const Key('log_stats'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Đang ghi ${_fmt(stats.elapsed)}', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('IMU: ${stats.accelCount} mẫu · ${stats.accelRateHz.toStringAsFixed(1)} Hz'),
            Text('GPS: ${stats.gpsCount} lần'
                '${stats.lastAccuracyM == null ? '' : ' · sai số ${stats.lastAccuracyM!.toStringAsFixed(1)} m'}'
                '${stats.lastSpeedMps == null || stats.lastSpeedMps! < 0 ? '' : ' · ${(stats.lastSpeedMps! * 3.6).toStringAsFixed(1)} km/h'}'),
            if (lowRate)
              const Text(
                'Cảm biến chưa đạt 50 Hz: server FFT giả định 50 Hz, kết quả có thể lệch.',
                style: TextStyle(color: Colors.orange),
              ),
            if (stats.lastAccuracyM != null && stats.lastAccuracyM! > 20)
              const Text('Sai số GPS > 20 m (server sẽ báo ERR_203). Ra chỗ thoáng.',
                  style: TextStyle(color: Colors.orange)),
          ],
        ),
      ),
    );
  }
}

String _fmt(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '${m}m${s.toString().padLeft(2, '0')}s';
}
