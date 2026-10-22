import 'package:flutter/material.dart';

/// [Dev A] Dual-Metric Live HUD hiển thị song song % Lãnh thổ & % Cống hiến Km
class PercentDominanceBar extends StatelessWidget {
  const PercentDominanceBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.black87,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Text(
              'BỘ ĐẾM SONG SONG: % ĐẤT CHIẾM ĐÓNG & % KM CỐNG HIẾN',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
