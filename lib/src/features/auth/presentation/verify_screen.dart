import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/siso_exceptions.dart';
import '../../../core/theme/siso_theme.dart';
import '../../map/domain/hex_cell.dart' show parseHexColor;
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
    final otp = _otpController.text;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SisoCircleButton(
                    icon: Icons.chevron_left,
                    tooltip: 'Quay lại',
                    background: SisoColors.infoBg,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.fromLTRB(8, 4, 12, 4),
                    decoration: BoxDecoration(
                      color: SisoColors.card,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: SisoColors.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CampusDot(color: parseHexColor(campus.color), size: 8),
                        const SizedBox(width: 6),
                        Text(campus.shortCode,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    campus.name,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, height: 1.28),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _info,
                    key: const Key('verify_info'),
                    style: const TextStyle(fontSize: 14.5, color: SisoColors.body, height: 1.45),
                  ),
                  const SizedBox(height: 28),
                  Stack(
                    children: [
                      Row(
                        children: [
                          for (var i = 0; i < 6; i++) ...[
                            if (i > 0) const SizedBox(width: 10),
                            Expanded(
                              child: _OtpBox(
                                digit: i < otp.length ? otp[i] : null,
                                focused: i == otp.length || (i == 5 && otp.length == 6),
                              ),
                            ),
                          ],
                        ],
                      ),
                      // Ô nhập thật nằm trong suốt phía trên 6 ô hiển thị
                      Positioned.fill(
                        child: TextField(
                          key: const Key('verify_otp'),
                          controller: _otpController,
                          autofocus: true,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          showCursor: false,
                          enableInteractiveSelection: false,
                          style: const TextStyle(color: Colors.transparent),
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          onSubmitted: (_) => _verify(),
                          onChanged: (value) {
                            setState(() {});
                            if (value.length == 6) _verify();
                          },
                          decoration: const InputDecoration(counterText: '', border: InputBorder.none),
                        ),
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      key: const Key('verify_error'),
                      style: const TextStyle(color: SisoColors.danger),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    key: const Key('verify_submit'),
                    onPressed: _loading ? null : _verify,
                    child: _loading
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [Text('Xác nhận'), SizedBox(width: 8), Icon(Icons.arrow_forward, size: 18)],
                          ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: TextButton.icon(
                      key: const Key('verify_resend'),
                      onPressed: (_resendIn > 0 || _resending) ? null : _resend,
                      style: TextButton.styleFrom(
                        foregroundColor: SisoColors.primary,
                        disabledForegroundColor: SisoColors.caption,
                        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
                      ),
                      icon: const Icon(Icons.schedule, size: 14),
                      label: Text(_resendIn > 0 ? 'Gửi lại mã sau ${_resendIn}s' : 'Gửi lại mã OTP'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OtpBox extends StatelessWidget {
  const _OtpBox({required this.digit, required this.focused});

  final String? digit;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: focused ? const Color(0xFFF8FCFC) : SisoColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: focused ? SisoColors.primary : (digit != null ? const Color(0xFFD6DDDE) : SisoColors.border),
          width: focused ? 2 : 1.5,
        ),
      ),
      child: Text(digit ?? '', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
    );
  }
}
