import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';

/// Nút Đăng xuất (đặt trên AppBar của MapScreen).
class LogoutButton extends ConsumerWidget {
  const LogoutButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authSessionProvider);
    final campus = session is AuthSignedIn ? session.user.university.shortCode : null;

    return IconButton(
      key: const Key('logout_button'),
      tooltip: campus == null ? 'Đăng xuất' : 'Đăng xuất ($campus)',
      icon: const Icon(Icons.logout),
      onPressed: () async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Đăng xuất?'),
            content: const Text('Bạn sẽ cần nhập lại email và mã OTP để vào lại.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Huỷ'),
              ),
              FilledButton(
                key: const Key('logout_confirm'),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Đăng xuất'),
              ),
            ],
          ),
        );
        if (confirmed == true) {
          await ref.read(authSessionProvider.notifier).logout();
        }
      },
    );
  }
}
