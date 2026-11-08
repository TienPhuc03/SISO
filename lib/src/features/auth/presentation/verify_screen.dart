import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/siso_exceptions.dart';
import '../data/auth_repository.dart';
import '../domain/auth_user.dart';
import '../providers/auth_provider.dart';

/// [Dev 1] Màn hình nhập mã OTP 6 số gửi về hộp thư trường.
class VerifyScreen extends ConsumerStatefulWidget {
  const VerifyScreen({super.key, required this.request, this.onResent});

  final OtpRequestResult request;

  /// Báo cho màn Login khi đã gửi lại mã (để quay lại vẫn biết lần gửi mới nhất).
  final ValueChanged<OtpRequestResult>? onResent;

  @override
  ConsumerState<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends ConsumerState<VerifyScreen> {
  final _otpController = TextEditingController();
  Timer? _timer;
  late int _resendIn;
  late String _info;
  bool _loading = false;
  bool _resending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _info = widget.request.message;
    _startCountdown(widget.request.resendWaitSeconds(DateTime.now()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otpController.dispose();
    super.dispose();
  }

  void _startCountdown(int seconds) {
    _timer?.cancel();
    _resendIn = seconds;
    if (seconds <= 0) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _resendIn--);
      if (_resendIn <= 0) timer.cancel();
    });
  }

  Future<void> _verify() async {
    final otp = _otpController.text.trim();
    if (_loading) return;
    if (otp.length != 6) {
      setState(() => _error = 'Mã OTP gồm đúng 6 chữ số.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = await ref
          .read(authRepositoryProvider)
          .verifyOtp(widget.request.email, otp);
      if (!mounted) return;
      ref.read(authSessionProvider.notifier).signedIn(user);
      // AuthGate (route đầu) sẽ đổi sang MapScreen
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on SisoException catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
        _otpController.clear();
      }
    } catch (_) {
      if (mounted) setState(() => _error = unexpectedAuthError);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _resending = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(authRepositoryProvider)
          .requestOtp(widget.request.email);
      widget.onResent?.call(result);
      if (!mounted) return;
      setState(() => _info = result.message);
      _startCountdown(result.resendWaitSeconds(DateTime.now()));
    } on SisoException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = unexpectedAuthError);
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final campus = widget.request.university;
    return Scaffold(
      appBar: AppBar(title: const Text('Nhập mã OTP')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    campus.name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _info,
                    key: const Key('verify_info'),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    key: const Key('verify_otp'),
                    controller: _otpController,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 6,
                    style: const TextStyle(fontSize: 28, letterSpacing: 12),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onSubmitted: (_) => _verify(),
                    onChanged: (value) {
                      if (value.length == 6) _verify();
                    },
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: '••••••',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const Key('verify_submit'),
                    onPressed: _loading ? null : _verify,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Xác nhận', style: TextStyle(fontSize: 16)),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    key: const Key('verify_resend'),
                    onPressed: (_resendIn > 0 || _resending) ? null : _resend,
                    child: Text(_resendIn > 0
                        ? 'Gửi lại mã sau ${_resendIn}s'
                        : 'Gửi lại mã OTP'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      key: const Key('verify_error'),
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
    );
  }
}
