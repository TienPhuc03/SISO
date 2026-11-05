// ⚠️ PROTOTYPE, VỨT ĐI SAU KHI CHỐT. Ticket wayfinder #6.
// Chạy: flutter run -d chrome --profile -t lib/main_prototype_hex_perf.dart
// Không cần .env hay backend.
import 'package:flutter/material.dart';

import 'src/features/map/presentation/prototype_hex_perf_screen.dart';

void main() {
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true),
    home: const PrototypeHexPerfScreen(),
  ));
}
