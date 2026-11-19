import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'tokens.dart';

class FinancialScoreRing extends StatelessWidget {
  const FinancialScoreRing({
    required this.score,
    required this.size,
    super.key,
  });

  final int? score;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: _RingPainter(score),
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(size * .17),
          child: score == null
              ? const Icon(
                  Icons.monitor_heart_outlined,
                  color: FinsightColors.primary,
                )
              : FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$score',
                        semanticsLabel: '$score점',
                        style: FinsightTypography.displaySb38.copyWith(
                          fontSize: size * .4,
                          height: 1,
                          color: FinsightColors.primary,
                        ),
                      ),
                      Text(
                        '/100',
                        semanticsLabel: '100점 만점',
                        style: FinsightTypography.labelR12.copyWith(
                          color: FinsightColors.gray400,
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

class _RingPainter extends CustomPainter {
  const _RingPainter(this.score);

  final int? score;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.shortestSide * .073;
    final ring = (Offset.zero & size).deflate(stroke);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawOval(ring, track..color = FinsightColors.gray800);
    final sweep = (score ?? 0).clamp(0, 100) * math.pi / 50;
    if (sweep == 0) return;
    final progress = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      ring,
      -math.pi / 2,
      sweep,
      false,
      progress
        ..color = FinsightColors.primary.withValues(alpha: .55)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, stroke * .72),
    );
    canvas.drawArc(
      ring,
      -math.pi / 2,
      sweep,
      false,
      progress
        ..maskFilter = null
        ..shader = const SweepGradient(
          transform: GradientRotation(-math.pi / 2),
          colors: [
            FinsightColors.neonLime300,
            FinsightColors.neonLime700,
            FinsightColors.primary,
            FinsightColors.neonLime300,
          ],
        ).createShader(ring),
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) => score != oldDelegate.score;
}
