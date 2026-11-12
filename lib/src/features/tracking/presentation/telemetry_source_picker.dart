import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/replay_log_assets.dart';
import '../data/replay_telemetry_source.dart';
import '../domain/telemetry_source_choice.dart';
import '../providers/tracking_session_notifier.dart';

/// Danh sách log trong assets (override được trong test).
final replayLogAssetsProvider = FutureProvider<List<String>>((ref) => listReplayLogAssets());

/// Đọc một log trong assets (override được trong test).
final replayLogLoaderProvider = Provider((ref) => loadReplayLogAsset);

const replaySpeedFactors = [1.0, 4.0, 10.0];

/// Chọn nguồn dữ liệu cho màn Chạy: giả lập hoặc phát lại log GPS/IMU thật (issue #8).
class TelemetrySourcePicker extends ConsumerStatefulWidget {
  const TelemetrySourcePicker({super.key, this.enabled = true});

  /// Tắt khi đang chạy (đổi nguồn giữa chừng sẽ làm mất Phiên chạy).
  final bool enabled;

  @override
  ConsumerState<TelemetrySourcePicker> createState() => _TelemetrySourcePickerState();
}

class _TelemetrySourcePickerState extends ConsumerState<TelemetrySourcePicker> {
  bool _replayMode = false;
  String? _loadingPath;
  String? _error;

  @override
  void initState() {
    super.initState();
    _replayMode = ref.read(telemetrySourceChoiceProvider) is ReplaySourceChoice;
  }

  Future<void> _selectLog(String assetPath, double speed) async {
    setState(() {
      _loadingPath = assetPath;
      _error = null;
    });
    try {
      final log = await ref.read(replayLogLoaderProvider)(assetPath, null);
      if (!mounted) return;
      ref.read(telemetrySourceChoiceProvider.notifier).state =
          ReplaySourceChoice(name: assetFileName(assetPath), log: log, speedFactor: speed);
    } catch (e) {
      if (mounted) setState(() => _error = 'Không đọc được log: $e');
    } finally {
      if (mounted) setState(() => _loadingPath = null);
    }
  }

  void _setSpeed(ReplaySourceChoice current, double speed) {
    ref.read(telemetrySourceChoiceProvider.notifier).state =
        ReplaySourceChoice(name: current.name, log: current.log, speedFactor: speed);
  }

  @override
  Widget build(BuildContext context) {
    final choice = ref.watch(telemetrySourceChoiceProvider);
    final textTheme = Theme.of(context).textTheme;

    return Card(
      key: const Key('source_picker'),
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nguồn dữ liệu', style: textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Giả lập')),
                ButtonSegment(value: true, label: Text('Phát lại log')),
              ],
              selected: {_replayMode},
              onSelectionChanged: widget.enabled
                  ? (s) {
                      setState(() => _replayMode = s.first);
                      if (!s.first) {
                        ref.read(telemetrySourceChoiceProvider.notifier).state =
                            const SimulatedSourceChoice();
                      }
                    }
                  : null,
            ),
            if (_replayMode) ...[
              const SizedBox(height: 8),
              _buildLogList(choice, textTheme),
              if (choice is ReplaySourceChoice) ...[
                const SizedBox(height: 8),
                _LogSummary(choice: choice),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final f in replaySpeedFactors)
                      ChoiceChip(
                        key: Key('replay_speed_${f.toInt()}'),
                        label: Text('${f.toInt()}x'),
                        selected: choice.speedFactor == f,
                        onSelected: widget.enabled ? (_) => _setSpeed(choice, f) : null,
                      ),
                  ],
                ),
              ],
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLogList(TelemetrySourceChoice choice, TextTheme textTheme) {
    final assets = ref.watch(replayLogAssetsProvider);
    return assets.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Text('Không liệt kê được log: $e'),
      data: (paths) {
        if (paths.isEmpty) {
          return Text(
            'Chưa có log nào trong $telemetryLogAssetDir. Ghi log trên iPhone (nhấn giữ nút "Chạy" '
            'trên bản đồ), chia sẻ file về máy rồi chép vào thư mục đó.',
            key: const Key('replay_empty'),
            style: textTheme.bodySmall,
          );
        }
        final selectedName = choice is ReplaySourceChoice ? choice.name : null;
        final speed = choice is ReplaySourceChoice ? choice.speedFactor : 1.0;
        final canSelect = widget.enabled && _loadingPath == null;
        return RadioGroup<String>(
          groupValue: selectedName,
          onChanged: (name) {
            if (!canSelect || name == null) return;
            _selectLog(paths.firstWhere((p) => assetFileName(p) == name), speed);
          },
          child: Column(
            children: [
              for (final path in paths)
                RadioListTile<String>(
                  key: Key('replay_log_${assetFileName(path)}'),
                  dense: true,
                  enabled: canSelect,
                  contentPadding: EdgeInsets.zero,
                  title: Text(assetFileName(path)),
                  value: assetFileName(path),
                  secondary: _loadingPath == path
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : null,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _LogSummary extends StatelessWidget {
  const _LogSummary({required this.choice});

  final ReplaySourceChoice choice;

  @override
  Widget build(BuildContext context) {
    final log = choice.log;
    final seconds = (log.durationMs / 1000).round();
    final windows = buildReplayWindows(log, baseEpochMs: 0).length;
    return Text(
      '${log.header.label.label}${log.header.note.isEmpty ? '' : ' · ${log.header.note}'}\n'
      '${seconds ~/ 60} phút ${seconds % 60} giây · IMU ${log.accelRateHz.toStringAsFixed(1)} Hz · '
      '${log.gps.length} lần GPS · $windows cửa sổ',
      key: const Key('replay_summary'),
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}
