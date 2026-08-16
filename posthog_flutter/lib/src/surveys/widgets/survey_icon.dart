import 'package:flutter/material.dart';

enum SurveyIconType { close, check }

class SurveyIcon extends StatelessWidget {
  const SurveyIcon({
    super.key,
    required this.type,
    required this.color,
    this.size = 24,
  });

  final SurveyIconType type;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: SurveyIconPainter(type: type, color: color),
      ),
    );
  }
}

class SurveyIconPainter extends CustomPainter {
  const SurveyIconPainter({required this.type, required this.color});

  final SurveyIconType type;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.1
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (type) {
      case SurveyIconType.close:
        canvas
          ..drawLine(
            Offset(size.width * 0.25, size.height * 0.25),
            Offset(size.width * 0.75, size.height * 0.75),
            paint,
          )
          ..drawLine(
            Offset(size.width * 0.75, size.height * 0.25),
            Offset(size.width * 0.25, size.height * 0.75),
            paint,
          );
      case SurveyIconType.check:
        final path = Path()
          ..moveTo(size.width * 0.2, size.height * 0.52)
          ..lineTo(size.width * 0.42, size.height * 0.72)
          ..lineTo(size.width * 0.8, size.height * 0.3);
        canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(SurveyIconPainter oldDelegate) {
    return oldDelegate.type != type || oldDelegate.color != color;
  }
}
