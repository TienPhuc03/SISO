import 'package:flutter/material.dart';
import 'speed_cadence_hud.dart';

/// [Dev A] Màn hình Theo dõi phiên chạy bộ trực tiếp (Active Run)
class ActiveRunScreen extends StatelessWidget {
  const ActiveRunScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Phiên Chạy Đang Diễn Ra')),
      body: const Column(
        children: [
          SpeedCadenceHud(),
          Expanded(
            child: Center(
              child: Text('Vệt đường chạy (Trail) & Kiểm định Anti-GIGO'),
            ),
          ),
        ],
      ),
    );
  }
}
