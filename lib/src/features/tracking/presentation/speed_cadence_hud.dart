import 'package:flutter/material.dart';

/// [Dev A] HUD hiển thị Tốc độ tức thời (km/h) & Nhịp bước chân (SPM - Cadence)
class SpeedCadenceHud extends StatelessWidget {
  const SpeedCadenceHud({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Text('Tốc độ: 0.0 km/h'),
          Text('Nhịp bước: 0 SPM'),
        ],
      ),
    );
  }
}
