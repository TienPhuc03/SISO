import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_provider.dart';
import '../providers/profile_providers.dart';
import 'avatar_view.dart';

/// Ảnh đại diện tròn trên thanh nổi của Bản đồ, chỉ để hiển thị (Hồ sơ mở từ thanh điều hướng).
class ProfileAvatar extends ConsumerWidget {
  const ProfileAvatar({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).valueOrNull;
    final session = ref.watch(authSessionProvider);
    final name = profile?.displayName ?? (session is AuthSignedIn ? session.user.displayName : '');

    return AvatarView(url: profile?.avatarUrl, name: name, size: size);
  }
}
