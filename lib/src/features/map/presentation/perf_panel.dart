import 'dart:async';
import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/frame_stats.dart';
import '../domain/play_area.dart';
import '../providers/map_state_notifier.dart';

/// Bảng "Đo hiệu năng" có đang mở không. Mở bằng cách nhấn giữ tiêu đề màn bản đồ 3 giây.
final perfPanelOpenProvider = StateProvider<bool>((ref) => false);

/// Bảng đo FPS bản đồ ngay trên máy (dùng khi không gắn được DevTools, vd. iPhone cài qua Sideloadly).
///
/// Đọc `FrameTiming` của engine (cùng nguồn số liệu với DevTools) trong [measureDuration],
/// rồi chốt FPS, % khung giật, p90 build/raster và khung tệ nhất. Có công tắc thêm ô giả
/// để bản đồ đủ 500 ô; ô giả chỉ nằm trong bộ nhớ máy này.
class PerfPanel extends ConsumerStatefulWidget {
  const PerfPanel({super.key, this.measureDuration = const Duration(seconds: 30)});

  final Duration measureDuration;

  @override
  ConsumerState<PerfPanel> createState() => _PerfPanelState();
}

class _PerfPanelState extends ConsumerState<PerfPanel> {
  static const int stressTarget = 500;

  final List<FrameSample> _samples = [];
  Timer? _ticker;
  DateTime? _startedAt;
  FrameStats? _result;
  bool _stressOn = false;
  bool _stressLoading = false;

  bool _listening = false;

  bool get _measuring => _startedAt != null;

  void _stopListening() {
    if (!_listening) return;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _listening = false;
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      _samples.add(FrameSample(
        vsyncStartUs: t.timestampInMicroseconds(FramePhase.vsyncStart),
        buildUs: t.buildDuration.inMicroseconds,
        rasterUs: t.rasterDuration.inMicroseconds,
      ));
    }
  }

  void _start() {
    _samples.clear();
    _stopListening();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _listening = true;
    setState(() {
      _result = null;
      _startedAt = DateTime.now();
    });
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (DateTime.now().difference(_startedAt!) >= widget.measureDuration) {
        _finish();
      } else {
        setState(() {}); // cập nhật đồng hồ đếm ngược
      }
    });
  }

  void _finish() {
    _ticker?.cancel();
    _stopListening();
    if (!mounted) return;
    setState(() {
      _startedAt = null;
      _result = FrameStats.from(_samples);
    });
  }

  Future<void> _toggleStress(bool on) async {
    final notifier = ref.read(mapStateNotifierProvider.notifier);
    setState(() {
      _stressOn = on;
      _stressLoading = on;
    });
    if (on) {
      await notifier.addSyntheticCells(center: PlayArea.landmark81, targetTotal: stressTarget);
      if (mounted) setState(() => _stressLoading = false);
    } else {
      notifier.removeSyntheticCells();
    }
  }

  void _close() {
    if (_measuring) _finish();
    if (_stressOn) ref.read(mapStateNotifierProvider.notifier).removeSyntheticCells();
    ref.read(perfPanelOpenProvider.notifier).state = false;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cellCount = ref.watch(mapStateNotifierProvider).length;
    final theme = Theme.of(context);
    const mode = kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug');

    return Card(
      key: const Key('perf_panel'),
      color: Colors.black.withValues(alpha: 0.85),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('Đo hiệu năng bản đồ', style: theme.textTheme.titleSmall)),
                IconButton(
                  key: const Key('perf_close'),
                  icon: const Icon(Icons.close),
                  onPressed: _close,
                ),
              ],
            ),
            Text('Đang vẽ $cellCount ô · bản $mode'),
            if (!kReleaseMode && !kProfileMode)
              const Text(
                'Bản debug chậm hơn nhiều, số đo không đại diện.',
                style: TextStyle(color: Colors.orangeAccent),
              ),
            SwitchListTile(
              key: const Key('perf_stress_switch'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Thêm ô giả cho đủ $stressTarget ô'),
              subtitle: _stressLoading ? const Text('Đang sinh ô…') : null,
              value: _stressOn,
              onChanged: _measuring ? null : _toggleStress,
            ),
            if (_measuring)
              Text(
                'Đang đo… còn ${(widget.measureDuration - DateTime.now().difference(_startedAt!)).inSeconds + 1} giây. '
                'Kéo và zoom bản đồ liên tục.',
              )
            else
              FilledButton.icon(
                key: const Key('perf_start'),
                onPressed: _stressLoading ? null : _start,
                icon: const Icon(Icons.speed),
                label: Text('Đo ${widget.measureDuration.inSeconds} giây'),
              ),
            if (_result case final r?) ...[
              const SizedBox(height: 8),
              Text(
                r.frames == 0
                    ? 'Không ghi được khung nào. Hãy kéo bản đồ trong lúc đo.'
                    : '${r.passed ? 'ĐẠT' : 'CHƯA ĐẠT'} (mục tiêu ≥ ${FrameStats.targetFps.toStringAsFixed(0)} FPS)',
                key: const Key('perf_verdict'),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: r.passed ? Colors.greenAccent : Colors.redAccent,
                ),
              ),
              if (r.frames > 0)
                Text(
                  'FPS: ${r.fps.toStringAsFixed(1)} · ${r.frames} khung · '
                  'giật: ${r.jankPercent.toStringAsFixed(1)}%\n'
                  'p90 build ${r.p90BuildMs.toStringAsFixed(1)} ms · '
                  'p90 raster ${r.p90RasterMs.toStringAsFixed(1)} ms · '
                  'tệ nhất ${r.worstFrameMs.toStringAsFixed(1)} ms\n'
                  '$cellCount ô · ${DateTime.now().toString().substring(0, 16)}',
                  key: const Key('perf_result'),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
