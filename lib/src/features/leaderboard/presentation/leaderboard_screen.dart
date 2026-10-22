import 'package:flutter/material.dart';
import 'hall_of_fame_card.dart';

/// [Dev A] Màn hình Bảng xếp hạng Liên trường & Mùa giải 30 Ngày
class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bảng Xếp Hạng Mùa Giải')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          HallOfFameCard(),
          SizedBox(height: 16),
          Text('Xếp hạng Sức Mạnh Tổng Hợp (50% Đất + 50% Km)'),
        ],
      ),
    );
  }
}
