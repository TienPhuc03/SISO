import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/tracking_session_notifier.dart';

/// HUD hiển thị Tốc độ tức thời (km/h, liên tục) và Nhịp bước (SPM, do server tính mỗi ~5 s).
class SpeedCadenceHud extends ConsumerWidget {
  const SpeedCadenceHud({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final run = ref.watch(trackingSessionNotifierProvider);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: _Metric(
              label: 'Tốc độ',
              value: run.speedKmh.toStringAsFixed(1),
              unit: 'km/h',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _Metric(
              label: 'Nhịp bước',
              value: run.cadenceSpm?.toString() ?? '--',
              unit: 'SPM',
            ),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.unit});

  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        child: Column(
          children: [
            Text(label, style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(value, style: theme.textTheme.displaySmall),
            Text(unit, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
