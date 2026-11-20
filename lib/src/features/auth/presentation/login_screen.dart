import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/siso_exceptions.dart';
import '../../../core/theme/siso_theme.dart';
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
      body: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: constraints.maxHeight * 0.42, child: const _CampusIllustration()),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: _buildForm(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: SisoColors.tint, borderRadius: BorderRadius.circular(6)),
                child: const HexIcon(size: 14, color: SisoColors.primary, filled: true),
              ),
              const SizedBox(width: 8),
              const Text(
                'SISO · ĐẤU TRƯỜNG LỤC GIÁC',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: SisoColors.primary),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Chạy cho trường của bạn',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: SisoColors.ink),
          ),
          const SizedBox(height: 4),
          const Text(
            'Nhập email trường cấp để đại diện tranh tài',
            style: TextStyle(fontSize: 14, color: SisoColors.body, height: 1.5),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: sisoCard(radius: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Expanded(
                      child: Text('Email sinh viên',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: SisoColors.ink)),
                    ),
                    Text('Tên miền .edu.vn', style: TextStyle(fontSize: 11, color: SisoColors.caption)),
                  ],
                ),
                const SizedBox(height: 6),
                TextFormField(
                  key: const Key('login_email'),
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: SisoColors.ink),
                  decoration: InputDecoration(
                    hintText: 'nguyenvana@hutech.edu.vn',
                    hintStyle: const TextStyle(color: SisoColors.caption),
                    filled: true,
                    fillColor: SisoColors.bg,
                    prefixIcon: const Icon(Icons.school_outlined, color: SisoColors.body, size: 20),
                    contentPadding: const EdgeInsets.symmetric(vertical: 15),
                    enabledBorder: _inputBorder(SisoColors.border),
                    focusedBorder: _inputBorder(SisoColors.primary, 2),
                    errorBorder: _inputBorder(SisoColors.danger),
                    focusedErrorBorder: _inputBorder(SisoColors.danger, 2),
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
                const SizedBox(height: 14),
                const Row(
                  children: [
                    Expanded(
                      child: Text('Đang hỗ trợ 5 trường',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: SisoColors.caption)),
                    ),
                    Text('Bình Thạnh',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: SisoColors.primary)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final (i, (name, color)) in supportedCampuses.indexed) ...[
                      if (i > 0) const SizedBox(width: 6),
                      Expanded(child: _CampusChip(name: name, color: color)),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              key: const Key('login_error'),
              style: const TextStyle(color: SisoColors.danger),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('login_submit'),
            onPressed: _loading ? null : _submit,
            child: _loading
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [Text('Nhận mã OTP'), SizedBox(width: 8), Icon(Icons.arrow_forward, size: 20)],
                  ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Bằng việc tiếp tục, bạn đồng ý với quy chế thi đấu và chiếm đất hợp lệ tại Đấu trường SISO.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: SisoColors.caption),
          ),
        ],
      ),
    );
  }

  OutlineInputBorder _inputBorder(Color color, [double width = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: width),
      );
}

/// 5 trường đang hỗ trợ, theo bảng màu trong thiết kế.
const supportedCampuses = [
  ('HUTECH', Color(0xFFFFCC00)),
  ('UEF', Color(0xFFFFFFFF)),
  ('UTH', Color(0xFF002B49)),
  ('FTU2', Color(0xFF8A0000)),
  ('HIU', Color(0xFFF2711C)),
];

class _CampusChip extends StatelessWidget {
  const _CampusChip({required this.name, required this.color});

  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: SisoColors.bg,
        border: Border.all(color: SisoColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CampusDot(color: color),
          const SizedBox(width: 4),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(name,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: SisoColors.ink)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Minh hoạ phía trên: khuôn viên trường, các ô lục giác sáng màu trường và hai người chạy.
class _CampusIllustration extends StatelessWidget {
  const _CampusIllustration();

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(painter: _CampusPainter()),
          const Align(
            alignment: Alignment(0.35, 0.25),
            child: Icon(Icons.directions_run, size: 110, color: SisoColors.primary),
          ),
          const Align(
            alignment: Alignment(-0.25, 0.4),
            child: Icon(Icons.directions_run, size: 86, color: SisoColors.accent),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.6, 1],
                colors: [Color(0x00F7F8F7), Color(0x99F7F8F7)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CampusPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Vẽ trong hệ toạ độ 390 x 310 của thiết kế rồi co giãn theo khung thật.
    final sx = size.width / 390, sy = size.height / 310;
    canvas.scale(sx, sy);
    Paint fill(int c) => Paint()..color = Color(c);

    canvas.drawRect(const Rect.fromLTWH(0, 0, 390, 310), fill(0xFFE8F1F0));
    canvas.drawRect(const Rect.fromLTRB(20, 100, 90, 180), fill(0xFFD3E6E5));
    canvas.drawRect(const Rect.fromLTRB(80, 70, 160, 180), fill(0xFFC2DCDA));
    canvas.drawRect(const Rect.fromLTRB(150, 110, 220, 180), fill(0xFFD8ECE9));
    canvas.drawRect(const Rect.fromLTRB(210, 85, 290, 180), fill(0xFFC5DFDD));
    canvas.drawRect(const Rect.fromLTRB(280, 125, 360, 180), fill(0xFFD8ECE9));
    // Cửa sổ toà nhà
    for (final (left, top, w, h) in [(88.0, 78.0, 64.0, 90.0), (218.0, 93.0, 64.0, 75.0)]) {
      for (var x = left; x + 9 <= left + w; x += 14) {
        for (var y = top; y + 13 <= top + h; y += 18) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromLTWH(x + 2, y + 3, 7, 10), const Radius.circular(1)),
            fill(0xCCE3F1F1),
          );
        }
      }
    }
    // Tháp đồng hồ
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(125, 42, 22, 30), const Radius.circular(2)),
        fill(0xFF005B5D));
    canvas.drawCircle(const Offset(136, 56), 4.5, fill(0xFFFFFFFF));
    canvas.drawPath(Path()..addPolygon(const [Offset(125, 42), Offset(136, 26), Offset(147, 42)], true),
        fill(0xFFF2A65A));
    // Tia sáng chéo
    canvas.drawPath(
        Path()..addPolygon(const [Offset(-20, 280), Offset(240, 40), Offset(290, 60), Offset(-10, 330)], true),
        fill(0x4DFFFFFF));
    canvas.drawPath(
        Path()..addPolygon(const [Offset(60, 320), Offset(340, 50), Offset(370, 70), Offset(80, 340)], true),
        fill(0x26F2A65A));
    // Mặt đất
    canvas.drawPath(
      Path()
        ..moveTo(-20, 210)
        ..quadraticBezierTo(140, 185, 410, 215)
        ..lineTo(410, 320)
        ..lineTo(-20, 320)
        ..close(),
      fill(0xFFD9E7E5),
    );
    canvas.drawPath(
      Path()
        ..moveTo(-20, 240)
        ..quadraticBezierTo(160, 215, 410, 245)
        ..lineTo(410, 320)
        ..lineTo(-20, 320)
        ..close(),
      fill(0xFFCBDDD9),
    );
    // Các ô lục giác sáng màu trường
    void hex(double cx, double cy, double r, int fillColor, int stroke, {bool dashed = false}) {
      final path = Path();
      for (var i = 0; i < 6; i++) {
        final a = (60 * i - 90) * 3.1415926535 / 180;
        final p = Offset(cx + r * _cos(a), cy + r * _sin(a));
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      path.close();
      if (!dashed) canvas.drawPath(path, fill(fillColor));
      canvas.drawPath(
        path,
        Paint()
          ..color = Color(stroke)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    hex(85, 238.5, 17, 0xFF008689, 0xFF005B5D);
    hex(130, 223.5, 17, 0xFFF2A65A, 0xFFC87A2E);
    hex(174, 208, 16, 0xFFE3F1F1, 0xFF008689);
    hex(50, 246, 12, 0xFFFFCC00, 0xFFD4A700);
    hex(210, 233.5, 17, 0xFF002B49, 0xFF00182A);
    hex(248, 217.5, 15, 0, 0xFF9AA6A7, dashed: true);
    canvas.drawCircle(
      const Offset(85, 238.5),
      26,
      Paint()
        ..color = const Color(0x99008689)
        ..style = PaintingStyle.stroke,
    );
    canvas.drawCircle(const Offset(85, 238.5), 2.5, fill(0xFFFFFFFF));
  }

  static double _cos(double a) => math.cos(a);
  static double _sin(double a) => math.sin(a);

  @override
  bool shouldRepaint(_CampusPainter oldDelegate) => false;
}
