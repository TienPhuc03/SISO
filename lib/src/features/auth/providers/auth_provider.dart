import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../data/auth_repository.dart';
import '../domain/auth_user.dart';

/// Trạng thái phiên đăng nhập của app.
sealed class AuthSession {
  const AuthSession();
}

/// Đang đọc token đã lưu khi mở app.
class AuthChecking extends AuthSession {
  const AuthChecking();
}

class AuthSignedOut extends AuthSession {
  const AuthSignedOut();
}

class AuthSignedIn extends AuthSession {
  const AuthSignedIn(this.user);
  final AuthUser user;
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository();
});

/// [Dev 1] Quản lý phiên đăng nhập: khôi phục khi mở app, đăng nhập, đăng xuất,
/// và tự đăng xuất khi API trả 401.
class AuthSessionNotifier extends StateNotifier<AuthSession> {
  AuthSessionNotifier(this._repository) : super(const AuthChecking()) {
    ApiClient.onUnauthorized = _handleUnauthorized;
    _restore();
  }

  final AuthRepository _repository;

  Future<void> _restore() async {
    AuthUser? user;
    try {
      user = await _repository.restoreSession();
    } catch (_) {
      // Không bao giờ để app kẹt ở màn hình loading
      user = null;
    }
    if (!mounted) return;
    state = user == null ? const AuthSignedOut() : AuthSignedIn(user);
  }

  /// Gọi sau khi `AuthRepository.verifyOtp` thành công.
  void signedIn(AuthUser user) => state = AuthSignedIn(user);

  Future<void> logout() async {
    try {
      await _repository.logout();
    } catch (_) {
      // Xoá storage lỗi vẫn phải đưa người dùng về màn hình Login
      ApiClient.setAccessToken(null);
    }
    if (mounted) state = const AuthSignedOut();
  }

  void _handleUnauthorized() {
    if (state is AuthSignedIn) logout();
  }

  @override
  void dispose() {
    if (ApiClient.onUnauthorized == _handleUnauthorized) {
      ApiClient.onUnauthorized = null;
    }
    super.dispose();
  }
}

final authSessionProvider =
    StateNotifierProvider<AuthSessionNotifier, AuthSession>((ref) {
  return AuthSessionNotifier(ref.watch(authRepositoryProvider));
});
