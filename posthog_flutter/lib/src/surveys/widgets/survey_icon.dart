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
    // These paths match the canonical Material Icons 24px SVGs.
    // https://github.com/google/material-design-icons/tree/master/src/navigation
    final path = Path();
    switch (type) {
      case SurveyIconType.close:
        path
          ..moveTo(19, 6.41)
          ..lineTo(17.59, 5)
          ..lineTo(12, 10.59)
          ..lineTo(6.41, 5)
          ..lineTo(5, 6.41)
          ..lineTo(10.59, 12)
          ..lineTo(5, 17.59)
          ..lineTo(6.41, 19)
          ..lineTo(12, 13.41)
          ..lineTo(17.59, 19)
          ..lineTo(19, 17.59)
          ..lineTo(13.41, 12)
          ..close();
      case SurveyIconType.check:
        path
          ..moveTo(9, 16.17)
          ..lineTo(4.83, 12)
          ..lineTo(3.41, 13.41)
          ..lineTo(9, 19)
          ..lineTo(21, 7)
          ..lineTo(19.59, 5.59)
          ..close();
    }

    canvas
      ..save()
      ..scale(size.width / 24, size.height / 24)
      ..drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.fill,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(SurveyIconPainter oldDelegate) {
    return oldDelegate.type != type || oldDelegate.color != color;
  }
}
