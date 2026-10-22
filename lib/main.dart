import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/core/network/api_client.dart';
import 'src/core/network/socket_manager.dart';
import 'src/features/map/presentation/map_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load biến môi trường từ file .env
  await dotenv.load(fileName: '.env');

  // Khởi tạo HTTP Client & WebSocket Manager kết nối tới NestJS Custom Backend
  ApiClient.initialize();
  SocketManager.initialize();

  runApp(
    const ProviderScope(
      child: SisoApp(),
    ),
  );
}

class SisoApp extends StatelessWidget {
  const SisoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SISO - Step In Step Out',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const MapScreen(),
    );
  }
}
