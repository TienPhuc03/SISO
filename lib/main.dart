import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/core/network/api_client.dart';
import 'src/core/network/socket_manager.dart';
import 'src/core/push/push_notifier.dart';
import 'src/core/theme/siso_theme.dart';
import 'src/features/auth/presentation/auth_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load biến môi trường từ file .env
  await dotenv.load(fileName: '.env');

  // Khởi tạo HTTP Client & WebSocket Manager kết nối tới NestJS Custom Backend
  ApiClient.initialize();
  SocketManager.initialize();

  // Thông báo đẩy (FCM): thiếu cấu hình Firebase (.env hoặc file native) thì app vẫn chạy, chỉ không nhận thông báo.
  final firebaseReady = await initFirebase();

  runApp(
    ProviderScope(
      overrides: [
        if (firebaseReady) pushMessagingProvider.overrideWithValue(FirebasePushMessaging()),
      ],
      child: const SisoApp(),
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
      theme: buildSisoTheme(),
      home: const AuthGate(),
    );
  }
}
