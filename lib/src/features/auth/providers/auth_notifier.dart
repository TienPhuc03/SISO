import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:siso_project/src/features/auth/data/auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository();
});

/// [Dev 1] Quản lý trạng thái đăng nhập và thông tin Trường đại học của sinh viên
class AuthNotifier extends StateNotifier<AsyncValue<String?>> {
  final AuthRepository _repository;

  AuthNotifier(this._repository) : super(const AsyncValue.data(null));

  Future<void> loginWithEduEmail(String email) async {
    state = const AsyncValue.loading();
    try {
      await _repository.requestEduLogin(email);
      state = AsyncValue.data(email);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final authNotifierProvider =
    StateNotifierProvider<AuthNotifier, AsyncValue<String?>>((ref) {
  return AuthNotifier(ref.watch(authRepositoryProvider));
});
