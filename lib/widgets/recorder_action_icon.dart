import 'package:flutter/material.dart';

/// Filled removal bin and bracketed waveform, matching the recorder controls.
class RecorderActionIcon extends StatelessWidget {
  final bool extract;
  final Color color, background;
  const RecorderActionIcon({
    super.key,
    required this.extract,
    required this.color,
    required this.background,
  });
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 28,
    height: 28,
    child: CustomPaint(painter: _ActionPainter(extract, color, background)),
  );
}

class _ActionPainter extends CustomPainter {
  final bool extract;
  final Color color, background;
  _ActionPainter(this.extract, this.color, this.background);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 30, size.height / 30);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (extract) {
      canvas.drawPath(
        Path()
          ..moveTo(8, 5)
          ..lineTo(4, 5)
          ..lineTo(4, 25)
          ..lineTo(8, 25),
        stroke,
      );
      canvas.drawPath(
        Path()
          ..moveTo(22, 5)
          ..lineTo(26, 5)
          ..lineTo(26, 25)
          ..lineTo(22, 25),
        stroke,
      );
      for (final bar in [(10.5, 4.0), (15.0, 9.0), (19.5, 6.0)]) {
        canvas.drawLine(
          Offset(bar.$1, 15 - bar.$2),
          Offset(bar.$1, 15 + bar.$2),
          stroke,
        );
      }
    } else {
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          const Rect.fromLTWH(8, 10, 14, 16),
          bottomLeft: const Radius.circular(2),
          bottomRight: const Radius.circular(2),
        ),
        Paint()..color = color,
      );
      canvas.drawLine(const Offset(6, 7), const Offset(24, 7), stroke);
      canvas.drawPath(
        Path()
          ..moveTo(11, 7)
          ..lineTo(12.5, 4)
          ..lineTo(17.5, 4)
          ..lineTo(19, 7)
          ..close(),
        Paint()..color = color,
      );
      final slot = Paint()
        ..color = background
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(const Offset(12, 14), const Offset(12, 22), slot);
      canvas.drawLine(const Offset(18, 14), const Offset(18, 22), slot);
    }
  }

  @override
  bool shouldRepaint(covariant _ActionPainter old) =>
      old.extract != extract ||
      old.color != color ||
      old.background != background;
}
