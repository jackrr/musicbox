import 'package:flutter/material.dart';

/// Draws a simple ADSR envelope shape as a filled path.
///
/// [attack], [decay], [release] are in seconds.
/// [sustain] is a level 0..1.
/// The sustain plateau is displayed with a fixed visual width.
class AdsrVisualizer extends StatelessWidget {
  final double attack;
  final double decay;
  final double sustain;
  final double release;

  const AdsrVisualizer({
    super.key,
    required this.attack,
    required this.decay,
    required this.sustain,
    required this.release,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 64,
    child: CustomPaint(
      painter: _AdsrPainter(
        attack: attack,
        decay: decay,
        sustain: sustain,
        release: release,
      ),
    ),
  );
}

class _AdsrPainter extends CustomPainter {
  final double attack;
  final double decay;
  final double sustain;
  final double release;

  const _AdsrPainter({
    required this.attack,
    required this.decay,
    required this.sustain,
    required this.release,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Fixed visual sustain window (0.5s) so the shape stays readable.
    const sustainWindow = 0.5;
    final total = attack + decay + sustainWindow + release;
    if (total <= 0) return;

    double xOf(double t) => t / total * size.width;
    double yOf(double level) => size.height * (1.0 - level);

    final xA = xOf(attack);
    final xD = xOf(attack + decay);
    final xS = xOf(attack + decay + sustainWindow);
    final xR = size.width;

    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(xA, yOf(1.0))
      ..lineTo(xD, yOf(sustain))
      ..lineTo(xS, yOf(sustain))
      ..lineTo(xR, size.height)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.greenAccent.withAlpha(50)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.greenAccent.withAlpha(180)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_AdsrPainter old) =>
      old.attack != attack ||
      old.decay != decay ||
      old.sustain != sustain ||
      old.release != release;
}
