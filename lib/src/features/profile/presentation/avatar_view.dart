import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/siso_theme.dart';

/// Ảnh đại diện tròn; chưa có ảnh hoặc tải lỗi thì hiện chữ cái đầu của nickname.
class AvatarView extends StatelessWidget {
  const AvatarView({super.key, required this.url, required this.name, this.size = 40});

  /// Đường dẫn tương đối từ API (`/api/v1/profile/avatar/...`), cần JWT.
  final String? url;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initial = Container(
      color: SisoColors.tint,
      alignment: Alignment.center,
      child: Text(
        name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase(),
        style: TextStyle(fontSize: size * 0.42, fontWeight: FontWeight.w700, color: SisoColors.primaryDark),
      ),
    );
    return ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: url == null
            ? initial
            : Image.network(
                '${AppConstants.apiBaseUrl}$url',
                headers: {if (ApiClient.accessToken case final token?) 'Authorization': 'Bearer $token'},
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => initial,
              ),
      ),
    );
  }
}
