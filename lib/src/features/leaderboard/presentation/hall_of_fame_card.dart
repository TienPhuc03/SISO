import 'package:flutter/material.dart';

/// [Dev A] Thẻ Đại Sảnh Danh Vọng (Hall of Fame) vinh danh trường vô địch tháng cũ
class HallOfFameCard extends StatelessWidget {
  const HallOfFameCard({super.key});

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: ListTile(
        leading: Icon(Icons.emoji_events, color: Colors.amber),
        title: Text('Đại Sảnh Danh Vọng (Hall of Fame)'),
        subtitle: Text('Vinh danh Quán quân Mùa giải 30 ngày'),
      ),
    );
  }
}
