import 'package:flutter/material.dart';

/// A simple procedural standing-figure outline shown during the framing
/// check, so the user has something concrete to line their body up with —
/// no image asset or package needed for a static illustrative guide.
class GhostSilhouettePainter extends CustomPainter {
  const GhostSilhouettePainter({this.color = Colors.white, this.opacity = 0.35});

  final Color color;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.012
      ..strokeCap = StrokeCap.round;

    final centerX = size.width / 2;
    final headCenterY = size.height * 0.12;
    final headRadius = size.height * 0.06;
    final shoulderY = size.height * 0.20;
    final hipY = size.height * 0.55;
    final feetY = size.height * 0.92;
    final shoulderHalfWidth = size.width * 0.14;
    final hipHalfWidth = size.width * 0.10;
    final handY = size.height * 0.50;
    final handHalfWidth = size.width * 0.20;
    final footHalfSpread = size.width * 0.09;

    canvas.drawCircle(Offset(centerX, headCenterY), headRadius, paint);

    final torso = Path()
      ..moveTo(centerX - shoulderHalfWidth, shoulderY)
      ..lineTo(centerX + shoulderHalfWidth, shoulderY)
      ..lineTo(centerX + hipHalfWidth, hipY)
      ..lineTo(centerX - hipHalfWidth, hipY)
      ..close();
    canvas.drawPath(torso, paint);

    canvas.drawLine(
      Offset(centerX - shoulderHalfWidth, shoulderY),
      Offset(centerX - handHalfWidth, handY),
      paint,
    );
    canvas.drawLine(
      Offset(centerX + shoulderHalfWidth, shoulderY),
      Offset(centerX + handHalfWidth, handY),
      paint,
    );

    canvas.drawLine(
      Offset(centerX - hipHalfWidth, hipY),
      Offset(centerX - footHalfSpread, feetY),
      paint,
    );
    canvas.drawLine(
      Offset(centerX + hipHalfWidth, hipY),
      Offset(centerX + footHalfSpread, feetY),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant GhostSilhouettePainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.opacity != opacity;
  }
}
