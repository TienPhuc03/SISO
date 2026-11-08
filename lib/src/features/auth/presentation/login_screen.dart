import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/siso_exceptions.dart';
import '../data/auth_repository.dart';
import '../domain/auth_user.dart';
import '../providers/auth_provider.dart';
import 'verify_screen.dart';

/// [Dev 1] Màn hình Đăng nhập bằng Email Sinh viên (HUTECH, UEF, UTH, FTU2, HIU).
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  String? _error;

  /// Lần gửi mã gần nhất (để quay lại màn OTP mà không gửi mã mới trong 60s)
  OtpRequestResult? _lastRequest;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading || !_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final email = _emailController.text.trim().toLowerCase();
      final last = _lastRequest;
      // Vừa gửi mã cho email này (quay lại từ màn OTP): mở lại màn OTP, không gửi mã mới
      final request = (last != null &&
              last.email == email &&
              last.resendWaitSeconds(DateTime.now()) > 0)
          ? last
          : await ref.read(authRepositoryProvider).requestOtp(email);
      _lastRequest = request;
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VerifyScreen(
            request: request,
            onResent: (latest) => _lastRequest = latest,
          ),
        ),
      );
    } on SisoException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = unexpectedAuthError);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SISO - Xác thực Sinh viên')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Nhập Email trường cấp để đại diện tranh tài',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 32),
                    TextFormField(
                      key: const Key('login_email'),
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Email Sinh viên',
                        hintText: 'nguyenvana@hutech.edu.vn',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        prefixIcon: const Icon(Icons.school),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Vui lòng không để trống email';
                        }
                        if (!isValidCampusEmail(value)) {
                          return 'SISO hiện chỉ hỗ trợ HUTECH, UEF, UTH, FTU2, HIU';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      key: const Key('login_submit'),
                      onPressed: _loading ? null : _submit,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Nhận mã OTP',
                              style: TextStyle(fontSize: 16)),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        key: const Key('login_error'),
                        style: const TextStyle(color: Colors.redAccent),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
