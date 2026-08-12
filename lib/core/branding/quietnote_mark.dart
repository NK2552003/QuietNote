import 'package:flutter/material.dart';

/// QuietNote's compact grayscale mark: a written note and quiet sound bars.
/// It stays clear at toolbar and splash sizes.
class QuietNoteMark extends StatelessWidget {
  const QuietNoteMark({super.key, this.size = 56});
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _QuietNoteMarkPainter()),
      );
}

class _QuietNoteMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 108;
    canvas.scale(s, s);
    final paint = Paint()..isAntiAlias = true;
    paint.color = const Color(0xFF202124);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(2, 2, 104, 104), const Radius.circular(28)), paint);
    paint.color = const Color(0xFFF7F7FF);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(27, 22, 50, 70), const Radius.circular(8)), paint);
    paint.color = const Color(0xFFC9C9C9);
    canvas.drawPath(Path()..moveTo(63, 22)..lineTo(77, 36)..lineTo(63, 36)..close(), paint);
    paint.color = const Color(0xFF5F6368);
    paint.strokeWidth = 4;
    paint.strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(39, 48), const Offset(65, 48), paint);
    canvas.drawLine(const Offset(39, 61), const Offset(59, 61), paint);
    canvas.drawLine(const Offset(39, 74), const Offset(53, 74), paint);
    paint.color = const Color(0xFF202124);
    paint.strokeWidth = 5;
    canvas.drawLine(const Offset(70, 57), const Offset(70, 65), paint);
    canvas.drawLine(const Offset(78, 52), const Offset(78, 70), paint);
    canvas.drawLine(const Offset(86, 57), const Offset(86, 65), paint);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
