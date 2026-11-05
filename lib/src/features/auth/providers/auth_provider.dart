import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/auth_repository.dart';
import '../../../core/errors/siso_exceptions.dart';

enum AuthState { initial, loading, otpSent, authenticated, error }

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthRepository _repository;
  String? currentEmail;
  String errorMessage = '';

  AuthNotifier(this._repository) : super(AuthState.initial);

  Future<void> loginWithEduEmail(String email) async {
    state = AuthState.loading;
    try {
      // Dùng hàm của bạn, nếu lỗi nó sẽ ném thẳng vào catch
      await _repository.requestEduLogin(email); 
      currentEmail = email;
      state = AuthState.otpSent;
    } on SisoException catch (e) {
      errorMessage = e.message;
      state = AuthState.error;
    } catch (e) {
      errorMessage = 'Lỗi không xác định: $e';
      state = AuthState.error;
    }
  }

  Future<void> verifyOtp(String otp) async {
    if (currentEmail == null) return;
    
    state = AuthState.loading;
    try {
      // Dùng hàm của bạn để xác thực
      await _repository.verifyOtp(currentEmail!, otp); 
      state = AuthState.authenticated;
    } on SisoException catch (e) {
      errorMessage = e.message;
      state = AuthState.error;
    } catch (e) {
      errorMessage = 'Lỗi hệ thống: $e';
      state = AuthState.error;
    }
  }
}

// Cung cấp Repository
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository();
});

// Cung cấp Notifier cho UI (Giao diện)
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final repository = ref.read(authRepositoryProvider);
  return AuthNotifier(repository);
});