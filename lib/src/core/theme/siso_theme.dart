import 'package:flutter/material.dart';

/// Bảng màu giao diện SISO theo thiết kế Stitch "SISO Running App UI".
class SisoColors {
  SisoColors._();

  static const primary = Color(0xFF008689);
  static const primaryDark = Color(0xFF005B5D);
  static const tint = Color(0xFFE3F1F1);
  static const accent = Color(0xFFF2A65A);

  static const ink = Color(0xFF1B2426);
  static const body = Color(0xFF5C6B6D);
  static const caption = Color(0xFF9AA6A7);

  static const bg = Color(0xFFF7F8F7);
  static const card = Color(0xFFFFFFFF);
  static const border = Color(0xFFE6EAEA);
  static const divider = Color(0xFFF0F3F3);
  static const track = Color(0xFFF0F2F2);

  /// Viền cho màu trường quá sáng (UEF trắng) để vẫn nhìn thấy trên nền trắng.
  static const lightSwatchBorder = Color(0xFF8C9A9B);

  static const danger = Color(0xFFC62828);
  static const recording = Color(0xFFE53935);
  static const gpsGood = Color(0xFF2E7D32);
  static const gpsSearching = Color(0xFFF59E0B);
  static const ready = Color(0xFF10B981);

  static const warningBg = Color(0xFFFDF3DC);
  static const warningBorder = Color(0xFFF3DEB0);
  static const warningText = Color(0xFF7A4E0E);
  static const infoBg = Color(0xFFEEF1F1);
  static const infoBorder = Color(0xFFE2E7E7);
  static const successBg = Color(0xFFE4F3EC);
  static const successBorder = Color(0xFFBCE1D0);
  static const successText = Color(0xFF1E5A41);
}

ThemeData buildSisoTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: SisoColors.primary,
      primary: SisoColors.primary,
      surface: SisoColors.bg,
      onSurface: SisoColors.ink,
    ),
    scaffoldBackgroundColor: SisoColors.bg,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: SisoColors.ink, displayColor: SisoColors.ink),
    appBarTheme: const AppBarTheme(
      backgroundColor: SisoColors.bg,
      foregroundColor: SisoColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: SisoColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

/// Chấm tròn màu trường; màu sáng (UEF trắng) có viền xám như thiết kế.
class CampusDot extends StatelessWidget {
  const CampusDot({super.key, required this.color, this.size = 10});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: isLightSwatch(color) ? Border.all(color: SisoColors.lightSwatchBorder) : null,
      ),
    );
  }
}

bool isLightSwatch(Color c) => c.computeLuminance() > 0.8;

/// Khung trắng bo góc viền mảnh dùng chung cho các thẻ.
BoxDecoration sisoCard({double radius = 24, Color border = SisoColors.border, double width = 1}) =>
    BoxDecoration(
      color: SisoColors.card,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: border, width: width),
    );

/// Số thập phân kiểu Việt Nam: 30,3
String viDecimal(double v, [int digits = 1]) => v.toStringAsFixed(digits).replaceAll('.', ',');

/// Hình lục giác đầu nhọn (pointy-top) vẽ trong khung [size].
Path hexagonPath(Size size) {
  final w = size.width, h = size.height;
  return Path()
    ..moveTo(w / 2, 0)
    ..lineTo(w, h * 0.25)
    ..lineTo(w, h * 0.75)
    ..lineTo(w / 2, h)
    ..lineTo(0, h * 0.75)
    ..lineTo(0, h * 0.25)
    ..close();
}

/// Biểu tượng lục giác (logo SISO).
class HexIcon extends StatelessWidget {
  const HexIcon({super.key, this.size = 16, this.color = Colors.white, this.filled = false, this.stroke = 2});

  final double size;
  final Color color;
  final bool filled;
  final double stroke;

  @override
  Widget build(BuildContext context) =>
      // Lục giác đều đầu nhọn: rộng = cao × √3/2
      CustomPaint(size: Size(size * 0.866, size), painter: _HexPainter(color, filled, stroke));
}

class _HexPainter extends CustomPainter {
  _HexPainter(this.color, this.filled, this.stroke);

  final Color color;
  final bool filled;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = filled ? 0.0 : stroke / 2;
    canvas.translate(inset, inset);
    final path = hexagonPath(Size(size.width - inset * 2, size.height - inset * 2));
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = filled ? PaintingStyle.fill : PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeJoin = StrokeJoin.round,
    );
    if (!filled) {
      canvas.drawCircle(
        Offset(size.width / 2 - inset, size.height / 2 - inset),
        size.width * 0.12,
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_HexPainter old) => old.color != color || old.filled != filled || old.stroke != stroke;
}

/// Nút tròn trắng viền mảnh (Quay lại / Đóng / Đăng xuất).
class SisoCircleButton extends StatelessWidget {
  const SisoCircleButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 40,
    this.background = SisoColors.card,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final Color background;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: background,
      shape: const CircleBorder(side: BorderSide(color: SisoColors.border)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox.square(dimension: size, child: Icon(icon, size: size * 0.45, color: SisoColors.ink)),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}
