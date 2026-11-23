import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/push/push_notifier.dart';
import '../../../core/theme/siso_theme.dart';
import '../../map/presentation/map_screen.dart';
import '../providers/auth_provider.dart';
import 'login_screen.dart';

/// Màn hình gốc: chọn Login hay Bản đồ theo phiên đăng nhập.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Giữ PushNotifier sống suốt app: nó tự đăng ký/huỷ topic FCM theo phiên đăng nhập.
    ref.listen<String?>(pushNotifierProvider, (_, __) {});
    // Bị đăng xuất (bấm Đăng xuất hoặc API trả 401) khi đang ở màn con -> về route đầu
    ref.listen<AuthSession>(authSessionProvider, (previous, next) {
      if (previous is AuthSignedIn && next is AuthSignedOut) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });

    return switch (ref.watch(authSessionProvider)) {
      AuthChecking() => const SplashScreen(key: Key('auth_checking')),
      AuthSignedOut() => const LoginScreen(),
      AuthSignedIn() => const MapScreen(),
    };
  }
}

/// S-01 Khởi động: nền teal, logo lục giác, chờ kiểm tra phiên đăng nhập.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SisoColors.primary,
      body: SafeArea(
        child: SizedBox(
          width: double.infinity,
          child: Column(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const HexIcon(size: 96, stroke: 5),
                    const SizedBox(height: 24),
                    const Text(
                      'SISO',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 44,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'STEP IN STEP OUT',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 2.8,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.15)),
                      ),
                      child: Text(
                        'Đấu trường Lục giác Sinh viên',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                    backgroundColor: Colors.white24),
              ),
              const SizedBox(height: 16),
              Text(
                'Đang kiểm tra phiên đăng nhập…',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 13.5),
              ),
              const SizedBox(height: 56),
            ],
          ),
        ),
      ),
    );
  }
}
