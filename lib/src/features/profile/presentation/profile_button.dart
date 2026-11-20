import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_provider.dart';
import '../providers/profile_providers.dart';
import 'avatar_view.dart';
import 'profile_screen.dart';

/// Ảnh đại diện tròn trên thanh nổi của Bản đồ; bấm mở Hồ sơ.
class ProfileButton extends ConsumerWidget {
  const ProfileButton({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).valueOrNull;
    final session = ref.watch(authSessionProvider);
    final name = profile?.displayName ?? (session is AuthSignedIn ? session.user.displayName : '');

    return Tooltip(
      message: 'Hồ sơ',
      child: InkWell(
        key: const Key('profile_button'),
        customBorder: const CircleBorder(),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ProfileScreen())),
        child: AvatarView(url: profile?.avatarUrl, name: name, size: size),
      ),
    );
  }
}
