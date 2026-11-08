import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../data/simulated_telemetry_source.dart';
import '../providers/tracking_session_notifier.dart';
import 'speed_cadence_hud.dart';

/// Màn hình Phiên chạy đang diễn ra: HUD, cảnh báo vàng khi một cửa sổ nghi xe máy,
/// và màn hình đỏ khi Phiên chạy bị loại (bằng chứng "còi đỏ" cho buổi test thực địa).
class ActiveRunScreen extends ConsumerWidget {
  const ActiveRunScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final run = ref.watch(trackingSessionNotifierProvider);
    final notifier = ref.read(trackingSessionNotifierProvider.notifier);
    final source = ref.watch(telemetryWindowSourceProvider);

    ref.listen(trackingSessionNotifierProvider, (previous, next) {
      if (previous?.status != TrackingStatus.rejected && next.status == TrackingStatus.rejected) {
        HapticFeedback.heavyImpact();
        Future.delayed(const Duration(milliseconds: 300), HapticFeedback.heavyImpact);
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Phiên Chạy Đang Diễn Ra')),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              const SpeedCadenceHud(),
              if (run.windowWarning && run.status == TrackingStatus.tracking)
                const _Banner(
                  color: Color(0xFFFFC107),
                  icon: Icons.warning_amber_rounded,
                  text: 'Nhịp bước không khớp tốc độ. Thêm một lần nữa Phiên chạy sẽ bị loại.',
                ),
              if (run.connectionIssue)
                const _Banner(
                  color: Color(0xFF90A4AE),
                  icon: Icons.wifi_off,
                  text: 'Mất kết nối, cửa sổ vừa rồi chưa được kiểm định.',
                ),
              if (run.status == TrackingStatus.idle && run.errorCode != null)
                _Banner(
                  color: const Color(0xFFEF9A9A),
                  icon: Icons.error_outline,
                  text: '[${run.errorCode}] ${run.errorMessage}',
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: run.status == TrackingStatus.tracking
                    ? FilledButton.icon(
                        onPressed: notifier.stopRun,
                        icon: const Icon(Icons.stop),
                        label: const Text('Dừng chạy'),
                      )
                    : FilledButton.icon(
                        onPressed: run.status == TrackingStatus.rejected ? null : notifier.startRun,
                        icon: const Icon(Icons.directions_run),
                        label: const Text('Bắt đầu chạy'),
                      ),
              ),
              if (run.sessionId != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text('Phiên chạy: ${run.sessionId}', style: Theme.of(context).textTheme.bodySmall),
                ),
              if (source is SimulatedTelemetrySource) _SimulatorPanel(source: source),
            ],
          ),
          if (run.status == TrackingStatus.rejected)
            _RejectedOverlay(code: run.errorCode ?? 'ERR_202', message: run.errorMessage ?? ''),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.color, required this.icon, required this.text});

  final Color color;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
      child: Row(
        children: [
          Icon(icon, color: Colors.black87),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(color: Colors.black87))),
        ],
      ),
    );
  }
}

class _RejectedOverlay extends StatelessWidget {
  const _RejectedOverlay({required this.code, required this.message});

  final String code;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: const Color(0xFFC62828),
        padding: const EdgeInsets.all(24),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.block, size: 96, color: Colors.white),
              const SizedBox(height: 16),
              const Text(
                'PHIÊN CHẠY BỊ LOẠI',
                style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(code, style: const TextStyle(color: Colors.white, fontSize: 22)),
              const SizedBox(height: 16),
              Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
              const SizedBox(height: 32),
              OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Về bản đồ'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bảng điều khiển nguồn GIẢ LẬP: đổi dáng di chuyển giữa chừng và (khi dev) dán JWT.
class _SimulatorPanel extends StatefulWidget {
  const _SimulatorPanel({required this.source});

  final SimulatedTelemetrySource source;

  @override
  State<_SimulatorPanel> createState() => _SimulatorPanelState();
}

class _SimulatorPanelState extends State<_SimulatorPanel> {
  final _tokenController = TextEditingController();

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nguồn giả lập (không phải cảm biến thật)', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<SimulatedGait>(
              segments: [
                for (final g in SimulatedGait.values) ButtonSegment(value: g, label: Text(g.label)),
              ],
              selected: {widget.source.gait},
              onSelectionChanged: (s) => setState(() => widget.source.gait = s.first),
            ),
            if (kDebugMode) ...[
              const SizedBox(height: 12),
              Text(
                ApiClient.hasAccessToken ? 'Đã có JWT.' : 'Chưa có JWT: dán accessToken lấy từ Swagger (verify-otp).',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _tokenController,
                      decoration: const InputDecoration(labelText: 'accessToken (chỉ khi dev)'),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => ApiClient.setAccessToken(_tokenController.text.trim())),
                    child: const Text('Dùng'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
