import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../map/presentation/map_screen.dart';
import '../providers/auth_provider.dart';
import 'login_screen.dart';

/// Màn hình gốc: chọn Login hay Bản đồ theo phiên đăng nhập.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Bị đăng xuất (bấm Đăng xuất hoặc API trả 401) khi đang ở màn con -> về route đầu
    ref.listen<AuthSession>(authSessionProvider, (previous, next) {
      if (previous is AuthSignedIn && next is AuthSignedOut) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });

    return switch (ref.watch(authSessionProvider)) {
      AuthChecking() => const Scaffold(
          key: Key('auth_checking'),
          body: Center(child: CircularProgressIndicator()),
        ),
      AuthSignedOut() => const LoginScreen(),
      AuthSignedIn() => const MapScreen(),
    };
  }
}
