import 'package:flutter/material.dart';
import 'dart:math' show min;

// see: https://www.flutterclutter.dev/tools/svg-to-flutter-path-converter/
class RatingIconPainter extends CustomPainter {
  final RatingIconType type;
  final bool selected;
  final Color color;
  late double _scale;

  RatingIconPainter({
    required this.type,
    this.selected = false,
    required this.color,
  });

  // Convert SVG x-coordinate to canvas coordinate
  double x(double coord) => (coord / 960.0) * _scale;

  // Convert SVG y-coordinate to canvas coordinate
  double y(double coord) => ((coord + 960.0) / 960.0) * _scale;

  @override
  bool shouldRepaint(RatingIconPainter oldDelegate) {
    return oldDelegate.selected != selected ||
        oldDelegate.type != type ||
        oldDelegate.color != color;
  }

  @override
  void paint(Canvas canvas, Size size) {
    _scale = min(size.width, size.height);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    // // Draw face features based on type
    switch (type) {
      case RatingIconType.veryDissatisfied:
        _drawVeryDissatisfied(canvas, size, paint);
        break;
      case RatingIconType.dissatisfied:
        _drawDissatisfied(canvas, size, paint);
        break;
      case RatingIconType.neutral:
        _drawNeutral(canvas, size, paint);
        break;
      case RatingIconType.satisfied:
        _drawSatisfied(canvas, size, paint);
        break;
      case RatingIconType.verySatisfied:
        _drawVerySatisfied(canvas, size, paint);
        break;
    }
  }

  void _drawVeryDissatisfied(Canvas canvas, Size size, Paint paint) {
    // Create fill paint for features
    final fillPaint = Paint()
      ..color = paint.color
      ..style = PaintingStyle.fill;

    // Draw facial features (mouth and eyes)
    final featurePath = Path();

    // Draw mouth (frown)
    featurePath.moveTo(x(480), y(-417));
    featurePath.quadraticBezierTo(x(413), y(-417), x(358.5), y(-379.5));
    featurePath.quadraticBezierTo(x(304), y(-342), x(278), y(-280));
    featurePath.lineTo(x(682), y(-280));
    featurePath.quadraticBezierTo(x(657), y(-343), x(602), y(-380));
    featurePath.quadraticBezierTo(x(547), y(-417), x(480), y(-417));
    featurePath.close();

    // Draw left X eye
    featurePath.moveTo(x(297), y(-489));
    featurePath.lineTo(x(347), y(-534));
    featurePath.lineTo(x(392), y(-489));
    featurePath.lineTo(x(423), y(-525));
    featurePath.lineTo(x(378), y(-570));
    featurePath.lineTo(x(423), y(-615));
    featurePath.lineTo(x(392), y(-651));
    featurePath.lineTo(x(347), y(-606));
    featurePath.lineTo(x(297), y(-651));
    featurePath.lineTo(x(266), y(-615));
    featurePath.lineTo(x(311), y(-570));
    featurePath.lineTo(x(266), y(-525));
    featurePath.lineTo(x(297), y(-489));
    featurePath.close();

    // Draw right X eye
    featurePath.moveTo(x(569), y(-489));
    featurePath.lineTo(x(613), y(-534));
    featurePath.lineTo(x(664), y(-489));
    featurePath.lineTo(x(695), y(-525));
    featurePath.lineTo(x(650), y(-570));
    featurePath.lineTo(x(695), y(-615));
    featurePath.lineTo(x(664), y(-651));
    featurePath.lineTo(x(613), y(-606));
    featurePath.lineTo(x(569), y(-651));
    featurePath.lineTo(x(538), y(-615));
    featurePath.lineTo(x(582), y(-570));
    featurePath.lineTo(x(538), y(-525));
    featurePath.lineTo(x(569), y(-489));
    featurePath.close();

    // Draw the filled features
    canvas.drawPath(featurePath, fillPaint);

    // Draw circle outline
    final path = Path();
    path.moveTo(x(480), y(-80));
    path.quadraticBezierTo(x(397), y(-80), x(324), y(-111.5));
    path.quadraticBezierTo(x(251), y(-143), x(197), y(-197));
    path.quadraticBezierTo(x(143), y(-251), x(111.5), y(-324));
    path.quadraticBezierTo(x(80), y(-397), x(80), y(-480));
    path.quadraticBezierTo(x(80), y(-563), x(111.5), y(-636));
    path.quadraticBezierTo(x(143), y(-709), x(197), y(-763));
    path.quadraticBezierTo(x(251), y(-817), x(324), y(-848.5));
    path.quadraticBezierTo(x(397), y(-880), x(480), y(-880));
    path.quadraticBezierTo(x(563), y(-880), x(636), y(-848.5));
    path.quadraticBezierTo(x(709), y(-817), x(763), y(-763));
    path.quadraticBezierTo(x(817), y(-709), x(848.5), y(-636));
    path.quadraticBezierTo(x(880), y(-563), x(880), y(-480));
    path.quadraticBezierTo(x(880), y(-397), x(848.5), y(-324));
    path.quadraticBezierTo(x(817), y(-251), x(763), y(-197));
    path.quadraticBezierTo(x(709), y(-143), x(636), y(-111.5));
    path.quadraticBezierTo(x(563), y(-80), x(480), y(-80));
    path.close();

    // Draw the outline with stroke paint
    canvas.drawPath(path, paint);
  }

  void _drawDissatisfied(Canvas canvas, Size size, Paint paint) {
    // Create filled paint style for features
    final fillPaint = Paint()
      ..color = paint.color
      ..style = PaintingStyle.fill;

    Path path = Path();
    Path featurePath = Path();

    // Right eye
    featurePath.moveTo(x(626), y(-533));
    featurePath.quadraticBezierTo(x(648.5), y(-533), x(664.25), y(-548.75));
    featurePath.quadraticBezierTo(x(680), y(-564.5), x(680), y(-587));
    featurePath.quadraticBezierTo(x(680), y(-609.5), x(664.25), y(-625.25));
    featurePath.quadraticBezierTo(x(648.5), y(-641), x(626), y(-641));
    featurePath.quadraticBezierTo(x(603.5), y(-641), x(587.75), y(-625.25));
    featurePath.quadraticBezierTo(x(572), y(-609.5), x(572), y(-587));
    featurePath.quadraticBezierTo(x(572), y(-564.5), x(587.75), y(-548.75));
    featurePath.quadraticBezierTo(x(603.5), y(-533), x(626), y(-533));
    featurePath.close();

    // Left eye
    featurePath.moveTo(x(334), y(-533));
    featurePath.quadraticBezierTo(x(356.5), y(-533), x(372.25), y(-548.75));
    featurePath.quadraticBezierTo(x(388), y(-564.5), x(388), y(-587));
    featurePath.quadraticBezierTo(x(388), y(-609.5), x(372.25), y(-625.25));
    featurePath.quadraticBezierTo(x(356.5), y(-641), x(334), y(-641));
    featurePath.quadraticBezierTo(x(311.5), y(-641), x(295.75), y(-625.25));
    featurePath.quadraticBezierTo(x(280), y(-609.5), x(280), y(-587));
    featurePath.quadraticBezierTo(x(280), y(-564.5), x(295.75), y(-548.75));
    featurePath.quadraticBezierTo(x(311.5), y(-533), x(334), y(-533));
    featurePath.close();

    // Frown
    featurePath.moveTo(x(480.174), y(-417));
    featurePath.quadraticBezierTo(x(413), y(-417), x(358.5), y(-379.5));
    featurePath.quadraticBezierTo(x(304), y(-342), x(278), y(-280));
    featurePath.lineTo(x(331), y(-280));
    featurePath.quadraticBezierTo(x(353), y(-322), x(393.173), y(-345));
    featurePath.quadraticBezierTo(x(433.346), y(-368), x(480.673), y(-368));
    featurePath.quadraticBezierTo(x(528), y(-368), x(567.5), y(-344.5));
    featurePath.quadraticBezierTo(x(607), y(-321), x(630), y(-280));
    featurePath.lineTo(x(682), y(-280));
    featurePath.quadraticBezierTo(x(657), y(-343), x(602.174), y(-380));
    featurePath.quadraticBezierTo(x(547.348), y(-417), x(480.174), y(-417));
    featurePath.close();

    // Draw filled features
    canvas.drawPath(featurePath, fillPaint);

    // Circle outline
    path.moveTo(x(480), y(-80));
    path.quadraticBezierTo(x(397), y(-80), x(324), y(-111.5));
    path.quadraticBezierTo(x(251), y(-143), x(197), y(-197));
    path.quadraticBezierTo(x(143), y(-251), x(111.5), y(-324));
    path.quadraticBezierTo(x(80), y(-397), x(80), y(-480));
    path.quadraticBezierTo(x(80), y(-563), x(111.5), y(-636));
    path.quadraticBezierTo(x(143), y(-709), x(197), y(-763));
    path.quadraticBezierTo(x(251), y(-817), x(324), y(-848.5));
    path.quadraticBezierTo(x(397), y(-880), x(480), y(-880));
    path.quadraticBezierTo(x(563), y(-880), x(636), y(-848.5));
    path.quadraticBezierTo(x(709), y(-817), x(763), y(-763));
    path.quadraticBezierTo(x(817), y(-709), x(848.5), y(-636));
    path.quadraticBezierTo(x(880), y(-563), x(880), y(-480));
    path.quadraticBezierTo(x(880), y(-397), x(848.5), y(-324));
    path.quadraticBezierTo(x(817), y(-251), x(763), y(-197));
    path.quadraticBezierTo(x(709), y(-143), x(636), y(-111.5));
    path.quadraticBezierTo(x(563), y(-80), x(480), y(-80));
    path.close();

    // Draw circle outline
    canvas.drawPath(path, paint);
  }

  void _drawSatisfied(Canvas canvas, Size size, Paint paint) {
    // Create filled paint style for features
    final fillPaint = Paint()
      ..color = paint.color
      ..style = PaintingStyle.fill;

    Path path = Path();
    Path featurePath = Path();

    // Right eye
    featurePath.moveTo(x(626), y(-533));
    featurePath.quadraticBezierTo(x(648.5), y(-533), x(664.25), y(-548.75));
    featurePath.quadraticBezierTo(x(680), y(-564.5), x(680), y(-587));
    featurePath.quadraticBezierTo(x(680), y(-609.5), x(664.25), y(-625.25));
    featurePath.quadraticBezierTo(x(648.5), y(-641), x(626), y(-641));
    featurePath.quadraticBezierTo(x(603.5), y(-641), x(587.75), y(-625.25));
    featurePath.quadraticBezierTo(x(572), y(-609.5), x(572), y(-587));
    featurePath.quadraticBezierTo(x(572), y(-564.5), x(587.75), y(-548.75));
    featurePath.quadraticBezierTo(x(603.5), y(-533), x(626), y(-533));
    featurePath.close();

    // Left eye
    featurePath.moveTo(x(334), y(-533));
    featurePath.quadraticBezierTo(x(356.5), y(-533), x(372.25), y(-548.75));
    featurePath.quadraticBezierTo(x(388), y(-564.5), x(388), y(-587));
    featurePath.quadraticBezierTo(x(388), y(-609.5), x(372.25), y(-625.25));
    featurePath.quadraticBezierTo(x(356.5), y(-641), x(334), y(-641));
    featurePath.quadraticBezierTo(x(311.5), y(-641), x(295.75), y(-625.25));
    featurePath.quadraticBezierTo(x(280), y(-609.5), x(280), y(-587));
    featurePath.quadraticBezierTo(x(280), y(-564.5), x(295.75), y(-548.75));
    featurePath.quadraticBezierTo(x(311.5), y(-533), x(334), y(-533));
    featurePath.close();

    // Smile
    featurePath.moveTo(x(480), y(-261));
    featurePath.quadraticBezierTo(x(546), y(-261), x(601.5), y(-296.5));
    featurePath.quadraticBezierTo(x(657), y(-332), x(682), y(-393));
    featurePath.lineTo(x(630), y(-393));
    featurePath.quadraticBezierTo(x(607), y(-353), x(567), y(-331.5));
    featurePath.quadraticBezierTo(x(527), y(-310), x(480.5), y(-310));
    featurePath.quadraticBezierTo(x(434), y(-310), x(393.5), y(-331));
    featurePath.quadraticBezierTo(x(353), y(-352), x(331), y(-393));
    featurePath.lineTo(x(278), y(-393));
    featurePath.quadraticBezierTo(x(304), y(-332), x(359), y(-296.5));
    featurePath.quadraticBezierTo(x(414), y(-261), x(480), y(-261));
    featurePath.close();

    // Draw filled features first
    canvas.drawPath(featurePath, fillPaint);

    // Circle outline
    path.moveTo(x(480), y(-80));
    path.quadraticBezierTo(x(397), y(-80), x(324), y(-111.5));
    path.quadraticBezierTo(x(251), y(-143), x(197), y(-197));
    path.quadraticBezierTo(x(143), y(-251), x(111.5), y(-324));
    path.quadraticBezierTo(x(80), y(-397), x(80), y(-480));
    path.quadraticBezierTo(x(80), y(-563), x(111.5), y(-636));
    path.quadraticBezierTo(x(143), y(-709), x(197), y(-763));
    path.quadraticBezierTo(x(251), y(-817), x(324), y(-848.5));
    path.quadraticBezierTo(x(397), y(-880), x(480), y(-880));
    path.quadraticBezierTo(x(563), y(-880), x(636), y(-848.5));
    path.quadraticBezierTo(x(709), y(-817), x(763), y(-763));
    path.quadraticBezierTo(x(817), y(-709), x(848.5), y(-636));
    path.quadraticBezierTo(x(880), y(-563), x(880), y(-480));
    path.quadraticBezierTo(x(880), y(-397), x(848.5), y(-324));
    path.quadraticBezierTo(x(817), y(-251), x(763), y(-197));
    path.quadraticBezierTo(x(709), y(-143), x(636), y(-111.5));
    path.quadraticBezierTo(x(563), y(-80), x(480), y(-80));
    path.close();

    canvas.drawPath(path, paint);
  }

  void _drawVerySatisfied(Canvas canvas, Size size, Paint paint) {
    Path path = Path();

    // Create filled paint style for features
    final fillPaint = Paint()
      ..color = paint.color
      ..style = PaintingStyle.fill;

    Path featurePath = Path();

    // Smile
    featurePath.moveTo(x(479.504), y(-261));
    featurePath.quadraticBezierTo(x(537), y(-261), x(585.5), y(-287));
    featurePath.quadraticBezierTo(x(634), y(-313), x(664), y(-359.4));
    featurePath.quadraticBezierTo(x(670), y(-371), x(663.25), y(-382));
    featurePath.quadraticBezierTo(x(656.5), y(-393), x(643), y(-393));
    featurePath.lineTo(x(316.918), y(-393));
    featurePath.quadraticBezierTo(x(303), y(-393), x(296.5), y(-382));
    featurePath.quadraticBezierTo(x(290), y(-371), x(296), y(-359.4));
    featurePath.quadraticBezierTo(x(326), y(-313), x(374.5), y(-287));
    featurePath.quadraticBezierTo(x(423), y(-261), x(479.504), y(-261));
    featurePath.close();

    // Left eye
    featurePath.moveTo(x(347), y(-578));
    featurePath.lineTo(x(374), y(-551));
    featurePath.quadraticBezierTo(x(381.636), y(-543), x(391.818), y(-543));
    featurePath.quadraticBezierTo(x(402), y(-543), x(410), y(-551));
    featurePath.quadraticBezierTo(x(418), y(-559), x(418), y(-569));
    featurePath.quadraticBezierTo(x(418), y(-579), x(410), y(-587));
    featurePath.lineTo(x(368), y(-629));
    featurePath.quadraticBezierTo(x(359.2), y(-638), x(347.1), y(-638));
    featurePath.quadraticBezierTo(x(335), y(-638), x(326), y(-629));
    featurePath.lineTo(x(284), y(-587));
    featurePath.quadraticBezierTo(x(276), y(-579.364), x(276), y(-569.182));
    featurePath.quadraticBezierTo(x(276), y(-559), x(284), y(-551));
    featurePath.quadraticBezierTo(x(292), y(-543), x(302), y(-543));
    featurePath.quadraticBezierTo(x(312), y(-543), x(320), y(-551));
    featurePath.lineTo(x(347), y(-578));
    featurePath.close();

    // Right eye
    featurePath.moveTo(x(614), y(-578));
    featurePath.lineTo(x(641), y(-551));
    featurePath.quadraticBezierTo(x(648.714), y(-543), x(659), y(-543));
    featurePath.quadraticBezierTo(x(669.286), y(-543), x(677), y(-551));
    featurePath.quadraticBezierTo(x(685), y(-558.636), x(685), y(-568.818));
    featurePath.quadraticBezierTo(x(685), y(-579), x(677), y(-587));
    featurePath.lineTo(x(635), y(-629));
    featurePath.quadraticBezierTo(x(626.2), y(-638), x(614.1), y(-638));
    featurePath.quadraticBezierTo(x(602), y(-638), x(593), y(-629));
    featurePath.lineTo(x(551), y(-587));
    featurePath.quadraticBezierTo(x(543), y(-579.286), x(543), y(-569));
    featurePath.quadraticBezierTo(x(543), y(-558.714), x(551), y(-551));
    featurePath.quadraticBezierTo(x(558.636), y(-543), x(568.818), y(-543));
    featurePath.quadraticBezierTo(x(579), y(-543), x(587), y(-551));
    featurePath.lineTo(x(614), y(-578));
    featurePath.close();

    // Draw filled features
    canvas.drawPath(featurePath, fillPaint);

    // Circle outline
    path.moveTo(x(480), y(-80));
    path.quadraticBezierTo(x(397), y(-80), x(324), y(-111.5));
    path.quadraticBezierTo(x(251), y(-143), x(197), y(-197));
    path.quadraticBezierTo(x(143), y(-251), x(111.5), y(-324));
    path.quadraticBezierTo(x(80), y(-397), x(80), y(-480));
    path.quadraticBezierTo(x(80), y(-563), x(111.5), y(-636));
    path.quadraticBezierTo(x(143), y(-709), x(197), y(-763));
    path.quadraticBezierTo(x(251), y(-817), x(324), y(-848.5));
    path.quadraticBezierTo(x(397), y(-880), x(480), y(-880));
    path.quadraticBezierTo(x(563), y(-880), x(636), y(-848.5));
    path.quadraticBezierTo(x(709), y(-817), x(763), y(-763));
    path.quadraticBezierTo(x(817), y(-709), x(848.5), y(-636));
    path.quadraticBezierTo(x(880), y(-563), x(880), y(-480));
    path.quadraticBezierTo(x(880), y(-397), x(848.5), y(-324));
    path.quadraticBezierTo(x(817), y(-251), x(763), y(-197));
    path.quadraticBezierTo(x(709), y(-143), x(636), y(-111.5));
    path.quadraticBezierTo(x(563), y(-80), x(480), y(-80));
    path.close();

    canvas.drawPath(path, paint);
  }

  void _drawNeutral(Canvas canvas, Size size, Paint paint) {
    // Create filled paint style for features
    final fillPaint = Paint()
      ..color = paint.color
      ..style = PaintingStyle.fill;

    Path path = Path();
    Path featurePath = Path();

    // Right eye
    featurePath.moveTo(x(626), y(-533));
    featurePath.quadraticBezierTo(x(648.5), y(-533), x(664.25), y(-548.75));
    featurePath.quadraticBezierTo(x(680), y(-564.5), x(680), y(-587));
    featurePath.quadraticBezierTo(x(680), y(-609.5), x(664.25), y(-625.25));
    featurePath.quadraticBezierTo(x(648.5), y(-641), x(626), y(-641));
    featurePath.quadraticBezierTo(x(603.5), y(-641), x(587.75), y(-625.25));
    featurePath.quadraticBezierTo(x(572), y(-609.5), x(572), y(-587));
    featurePath.quadraticBezierTo(x(572), y(-564.5), x(587.75), y(-548.75));
    featurePath.quadraticBezierTo(x(603.5), y(-533), x(626), y(-533));
    featurePath.close();

    // Left eye
    featurePath.moveTo(x(334), y(-533));
    featurePath.quadraticBezierTo(x(356.5), y(-533), x(372.25), y(-548.75));
    featurePath.quadraticBezierTo(x(388), y(-564.5), x(388), y(-587));
    featurePath.quadraticBezierTo(x(388), y(-609.5), x(372.25), y(-625.25));
    featurePath.quadraticBezierTo(x(356.5), y(-641), x(334), y(-641));
    featurePath.quadraticBezierTo(x(311.5), y(-641), x(295.75), y(-625.25));
    featurePath.quadraticBezierTo(x(280), y(-609.5), x(280), y(-587));
    featurePath.quadraticBezierTo(x(280), y(-564.5), x(295.75), y(-548.75));
    featurePath.quadraticBezierTo(x(311.5), y(-533), x(334), y(-533));
    featurePath.close();

    // Neutral mouth
    featurePath.moveTo(x(354), y(-339));
    featurePath.lineTo(x(607), y(-339));
    featurePath.lineTo(x(607), y(-388));
    featurePath.lineTo(x(354), y(-388));
    featurePath.lineTo(x(354), y(-339));
    featurePath.close();

    // Draw filled features
    canvas.drawPath(featurePath, fillPaint);

    // Circle outline
    path.moveTo(x(480), y(-80));
    path.quadraticBezierTo(x(397), y(-80), x(324), y(-111.5));
    path.quadraticBezierTo(x(251), y(-143), x(197), y(-197));
    path.quadraticBezierTo(x(143), y(-251), x(111.5), y(-324));
    path.quadraticBezierTo(x(80), y(-397), x(80), y(-480));
    path.quadraticBezierTo(x(80), y(-563), x(111.5), y(-636));
    path.quadraticBezierTo(x(143), y(-709), x(197), y(-763));
    path.quadraticBezierTo(x(251), y(-817), x(324), y(-848.5));
    path.quadraticBezierTo(x(397), y(-880), x(480), y(-880));
    path.quadraticBezierTo(x(563), y(-880), x(636), y(-848.5));
    path.quadraticBezierTo(x(709), y(-817), x(763), y(-763));
    path.quadraticBezierTo(x(817), y(-709), x(848.5), y(-636));
    path.quadraticBezierTo(x(880), y(-563), x(880), y(-480));
    path.quadraticBezierTo(x(880), y(-397), x(848.5), y(-324));
    path.quadraticBezierTo(x(817), y(-251), x(763), y(-197));
    path.quadraticBezierTo(x(709), y(-143), x(636), y(-111.5));
    path.quadraticBezierTo(x(563), y(-80), x(480), y(-80));
    path.close();

    // Draw circle outline
    canvas.drawPath(path, paint);
  }
}

enum RatingIconType {
  veryDissatisfied,
  dissatisfied,
  neutral,
  satisfied,
  verySatisfied,
}

class RatingIcon extends StatelessWidget {
  final bool selected;
  final RatingIconType type;
  final Color? color;
  final double size;

  const RatingIcon({
    super.key,
    required this.type,
    this.selected = false,
    this.color,
    this.size = 48.0,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: RatingIconPainter(
          selected: selected,
          type: type,
          color: color ?? Theme.of(context).iconTheme.color ?? Colors.grey,
        ),
      ),
    );
  }
}

class MyPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = Paint();
    Path path = Path();

    // Path number 1

    paint.color = Color(0xffffffff).withOpacity(0);
    path = Path();
    path.lineTo(size.width * 0.6, -0.33);
    path.cubicTo(size.width * 0.65, -0.33, size.width * 0.69, -0.34,
        size.width * 0.73, -0.36);
    path.cubicTo(size.width * 0.77, -0.38, size.width * 0.81, -0.41,
        size.width * 0.83, -0.45);
    path.cubicTo(size.width * 0.84, -0.46, size.width * 0.83, -0.47,
        size.width * 0.83, -0.48);
    path.cubicTo(size.width * 0.82, -0.49, size.width * 0.82, -0.49,
        size.width * 0.8, -0.49);
    path.cubicTo(size.width * 0.8, -0.49, size.width * 0.4, -0.49,
        size.width * 0.4, -0.49);
    path.cubicTo(size.width * 0.38, -0.49, size.width * 0.38, -0.49,
        size.width * 0.37, -0.48);
    path.cubicTo(size.width * 0.37, -0.47, size.width * 0.37, -0.46,
        size.width * 0.37, -0.45);
    path.cubicTo(size.width * 0.4, -0.41, size.width * 0.43, -0.38,
        size.width * 0.47, -0.36);
    path.cubicTo(size.width * 0.51, -0.34, size.width * 0.55, -0.33,
        size.width * 0.6, -0.33);
    path.cubicTo(size.width * 0.6, -0.33, size.width * 0.6, -0.33,
        size.width * 0.6, -0.33);
    path.lineTo(size.width * 0.43, -0.72);
    path.cubicTo(size.width * 0.43, -0.72, size.width * 0.47, -0.69,
        size.width * 0.47, -0.69);
    path.cubicTo(size.width * 0.47, -0.68, size.width * 0.48, -0.68,
        size.width * 0.49, -0.68);
    path.cubicTo(size.width / 2, -0.68, size.width * 0.51, -0.68,
        size.width * 0.51, -0.69);
    path.cubicTo(size.width * 0.52, -0.7, size.width * 0.52, -0.7,
        size.width * 0.52, -0.71);
    path.cubicTo(size.width * 0.52, -0.72, size.width * 0.52, -0.73,
        size.width * 0.51, -0.73);
    path.cubicTo(size.width * 0.51, -0.73, size.width * 0.46, -0.79,
        size.width * 0.46, -0.79);
    path.cubicTo(size.width * 0.45, -0.79, size.width * 0.44, -0.8,
        size.width * 0.43, -0.8);
    path.cubicTo(size.width * 0.42, -0.8, size.width * 0.42, -0.79,
        size.width * 0.41, -0.79);
    path.cubicTo(size.width * 0.41, -0.79, size.width * 0.36, -0.73,
        size.width * 0.36, -0.73);
    path.cubicTo(size.width * 0.35, -0.73, size.width * 0.35, -0.72,
        size.width * 0.35, -0.71);
    path.cubicTo(size.width * 0.35, -0.7, size.width * 0.35, -0.7,
        size.width * 0.36, -0.69);
    path.cubicTo(size.width * 0.36, -0.68, size.width * 0.37, -0.68,
        size.width * 0.38, -0.68);
    path.cubicTo(size.width * 0.39, -0.68, size.width * 0.39, -0.68,
        size.width * 0.4, -0.69);
    path.cubicTo(size.width * 0.4, -0.69, size.width * 0.43, -0.72,
        size.width * 0.43, -0.72);
    path.cubicTo(size.width * 0.43, -0.72, size.width * 0.43, -0.72,
        size.width * 0.43, -0.72);
    path.lineTo(size.width * 0.77, -0.72);
    path.cubicTo(size.width * 0.77, -0.72, size.width * 0.8, -0.69,
        size.width * 0.8, -0.69);
    path.cubicTo(size.width * 0.81, -0.68, size.width * 0.82, -0.68,
        size.width * 0.82, -0.68);
    path.cubicTo(size.width * 0.83, -0.68, size.width * 0.84, -0.68,
        size.width * 0.85, -0.69);
    path.cubicTo(size.width * 0.85, -0.7, size.width * 0.86, -0.7,
        size.width * 0.86, -0.71);
    path.cubicTo(size.width * 0.86, -0.72, size.width * 0.85, -0.73,
        size.width * 0.85, -0.73);
    path.cubicTo(size.width * 0.85, -0.73, size.width * 0.79, -0.79,
        size.width * 0.79, -0.79);
    path.cubicTo(size.width * 0.79, -0.79, size.width * 0.78, -0.8,
        size.width * 0.77, -0.8);
    path.cubicTo(size.width * 0.76, -0.8, size.width * 0.75, -0.79,
        size.width * 0.74, -0.79);
    path.cubicTo(size.width * 0.74, -0.79, size.width * 0.69, -0.73,
        size.width * 0.69, -0.73);
    path.cubicTo(size.width * 0.68, -0.73, size.width * 0.68, -0.72,
        size.width * 0.68, -0.71);
    path.cubicTo(size.width * 0.68, -0.7, size.width * 0.68, -0.7,
        size.width * 0.69, -0.69);
    path.cubicTo(size.width * 0.7, -0.68, size.width * 0.7, -0.68,
        size.width * 0.71, -0.68);
    path.cubicTo(size.width * 0.72, -0.68, size.width * 0.73, -0.68,
        size.width * 0.73, -0.69);
    path.cubicTo(size.width * 0.73, -0.69, size.width * 0.77, -0.72,
        size.width * 0.77, -0.72);
    path.cubicTo(size.width * 0.77, -0.72, size.width * 0.77, -0.72,
        size.width * 0.77, -0.72);
    path.lineTo(size.width * 0.6, -0.1);
    path.cubicTo(size.width * 0.53, -0.1, size.width * 0.47, -0.11,
        size.width * 0.41, -0.14);
    path.cubicTo(size.width * 0.34, -0.17, size.width * 0.29, -0.2,
        size.width / 4, -0.25);
    path.cubicTo(size.width / 5, -0.29, size.width * 0.17, -0.34,
        size.width * 0.14, -0.4);
    path.cubicTo(size.width * 0.11, -0.47, size.width * 0.1, -0.53,
        size.width * 0.1, -0.6);
    path.cubicTo(size.width * 0.1, -0.67, size.width * 0.11, -0.73,
        size.width * 0.14, -0.79);
    path.cubicTo(
        size.width * 0.17, -0.86, size.width / 5, -0.91, size.width / 4, -0.95);
    path.cubicTo(size.width * 0.29, -1, size.width * 0.34, -1.03,
        size.width * 0.41, -1.06);
    path.cubicTo(size.width * 0.47, -1.09, size.width * 0.53, -1.1,
        size.width * 0.6, -1.1);
    path.cubicTo(size.width * 0.67, -1.1, size.width * 0.73, -1.09,
        size.width * 0.8, -1.06);
    path.cubicTo(size.width * 0.86, -1.03, size.width * 0.91, -1,
        size.width * 0.95, -0.95);
    path.cubicTo(
        size.width, -0.91, size.width * 1.03, -0.86, size.width * 1.06, -0.79);
    path.cubicTo(size.width * 1.09, -0.73, size.width * 1.1, -0.67,
        size.width * 1.1, -0.6);
    path.cubicTo(size.width * 1.1, -0.53, size.width * 1.09, -0.47,
        size.width * 1.06, -0.4);
    path.cubicTo(
        size.width * 1.03, -0.34, size.width, -0.29, size.width * 0.95, -0.25);
    path.cubicTo(size.width * 0.91, -0.2, size.width * 0.86, -0.17,
        size.width * 0.8, -0.14);
    path.cubicTo(size.width * 0.73, -0.11, size.width * 0.67, -0.1,
        size.width * 0.6, -0.1);
    path.cubicTo(
        size.width * 0.6, -0.1, size.width * 0.6, -0.1, size.width * 0.6, -0.1);
    path.lineTo(size.width * 0.6, -0.6);
    path.cubicTo(
        size.width * 0.6, -0.6, size.width * 0.6, -0.6, size.width * 0.6, -0.6);
    path.lineTo(size.width * 0.6, -0.17);
    path.cubicTo(size.width * 0.72, -0.17, size.width * 0.82, -0.22,
        size.width * 0.9, -0.3);
    path.cubicTo(size.width * 0.98, -0.38, size.width * 1.03, -0.48,
        size.width * 1.03, -0.6);
    path.cubicTo(size.width * 1.03, -0.72, size.width * 0.98, -0.82,
        size.width * 0.9, -0.9);
    path.cubicTo(size.width * 0.82, -0.98, size.width * 0.72, -1.02,
        size.width * 0.6, -1.02);
    path.cubicTo(size.width * 0.48, -1.02, size.width * 0.38, -0.98,
        size.width * 0.3, -0.9);
    path.cubicTo(size.width * 0.22, -0.82, size.width * 0.18, -0.72,
        size.width * 0.18, -0.6);
    path.cubicTo(size.width * 0.18, -0.48, size.width * 0.22, -0.38,
        size.width * 0.3, -0.3);
    path.cubicTo(size.width * 0.38, -0.22, size.width * 0.48, -0.17,
        size.width * 0.6, -0.17);
    path.cubicTo(size.width * 0.6, -0.17, size.width * 0.6, -0.17,
        size.width * 0.6, -0.17);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return true;
  }
}
