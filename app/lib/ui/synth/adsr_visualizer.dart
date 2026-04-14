import 'package:flutter/material.dart';

import '../../engine/types.dart';

/// Interactive ADSR envelope visualizer.
///
/// Displays the ADSR shape and lets the user drag each segment to edit:
///   - Attack slope  → drag left/right to change attack time
///   - Decay slope   → drag left/right to change decay time
///   - Sustain plateau → drag up/down to change sustain level
///   - Release slope → drag left/right to change release time
class AdsrVisualizer extends StatefulWidget {
  final double attack;
  final double decay;
  final double sustain;
  final double release;

  /// Called when the user drags to change a parameter.
  final void Function(VoiceParam param, double value)? onChanged;

  const AdsrVisualizer({
    super.key,
    required this.attack,
    required this.decay,
    required this.sustain,
    required this.release,
    this.onChanged,
  });

  @override
  State<AdsrVisualizer> createState() => _AdsrVisualizerState();
}

enum _Region { attack, decay, sustain, release }

class _AdsrVisualizerState extends State<AdsrVisualizer> {
  _Region? _active;

  static const double _height = 72.0;
  // Fixed sustain display window; scales the visual without affecting the param.
  static const double _sustainWindow = 0.5;

  double _totalTime() =>
      widget.attack + widget.decay + _sustainWindow + widget.release;

  _Region _hitRegion(Offset pos, double width) {
    final total = _totalTime();
    if (total <= 0) return _Region.attack;
    final xA = widget.attack / total * width;
    final xD = (widget.attack + widget.decay) / total * width;
    final xS = (widget.attack + widget.decay + _sustainWindow) / total * width;
    if (pos.dx <= xA) return _Region.attack;
    if (pos.dx <= xD) return _Region.decay;
    if (pos.dx <= xS) return _Region.sustain;
    return _Region.release;
  }

  void _onDelta(Offset delta, double width) {
    final cb = widget.onChanged;
    if (cb == null || _active == null) return;
    switch (_active!) {
      case _Region.attack:
        // Full-width swipe = 8 s range
        cb(VoiceParam.attack,
            (widget.attack + delta.dx / width * 8.0).clamp(0.001, 4.0));
      case _Region.decay:
        cb(VoiceParam.decay,
            (widget.decay + delta.dx / width * 8.0).clamp(0.001, 4.0));
      case _Region.sustain:
        // Drag up = increase sustain
        cb(VoiceParam.sustain,
            (widget.sustain - delta.dy / _height).clamp(0.0, 1.0));
      case _Region.release:
        cb(VoiceParam.release,
            (widget.release + delta.dx / width * 16.0).clamp(0.01, 8.0));
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          onPanStart: (d) =>
              setState(() => _active = _hitRegion(d.localPosition, width)),
          onPanUpdate: (d) => _onDelta(d.delta, width),
          onPanEnd: (_) => setState(() => _active = null),
          child: SizedBox(
            height: _height,
            child: CustomPaint(
              painter: _AdsrPainter(
                attack:  widget.attack,
                decay:   widget.decay,
                sustain: widget.sustain,
                release: widget.release,
                active:  _active,
              ),
              // A non-null child makes CustomPaint fill the parent's constraints.
              child: const SizedBox.expand(),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------

class _AdsrPainter extends CustomPainter {
  final double attack, decay, sustain, release;
  final _Region? active;

  const _AdsrPainter({
    required this.attack,
    required this.decay,
    required this.sustain,
    required this.release,
    this.active,
  });

  static const double _sustainWindow = 0.5;

  @override
  void paint(Canvas canvas, Size size) {
    final total = attack + decay + _sustainWindow + release;
    if (total <= 0 || size.width <= 0) return;

    double xOf(double t) => t / total * size.width;
    double yOf(double level) => size.height * (1.0 - level);

    final xA = xOf(attack);
    final xD = xOf(attack + decay);
    final xS = xOf(attack + decay + _sustainWindow);
    final xR = size.width;
    final yS = yOf(sustain);

    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(xA, 0)
      ..lineTo(xD, yS)
      ..lineTo(xS, yS)
      ..lineTo(xR, size.height)
      ..close();

    // Fill
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.greenAccent.withAlpha(40)
        ..style = PaintingStyle.fill,
    );

    // Outline — each segment highlighted when active
    void drawSeg(Offset a, Offset b, _Region region) {
      final isActive = active == region;
      canvas.drawLine(
        a, b,
        Paint()
          ..color = isActive
              ? Colors.greenAccent
              : Colors.greenAccent.withAlpha(160)
          ..strokeWidth = isActive ? 2.5 : 1.5
          ..style = PaintingStyle.stroke,
      );
    }

    drawSeg(Offset(0, size.height), Offset(xA, 0), _Region.attack);
    drawSeg(Offset(xA, 0), Offset(xD, yS), _Region.decay);
    drawSeg(Offset(xD, yS), Offset(xS, yS), _Region.sustain);
    drawSeg(Offset(xS, yS), Offset(xR, size.height), _Region.release);

    // Control-point dots
    final dotPaint = Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.fill;
    for (final pt in [
      Offset(xA, 0),
      Offset(xD, yS),
      Offset(xS, yS),
    ]) {
      canvas.drawCircle(pt, 4, dotPaint);
    }

    // Drag hint labels
    if (active != null) {
      _drawLabel(canvas, size, active!);
    }
  }

  void _drawLabel(Canvas canvas, Size size, _Region region) {
    final labels = {
      _Region.attack:  'ATK',
      _Region.decay:   'DEC',
      _Region.sustain: 'SUS',
      _Region.release: 'REL',
    };
    final tp = TextPainter(
      text: TextSpan(
        text: labels[region],
        style: const TextStyle(
          color: Colors.greenAccent,
          fontSize: 9,
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(4, 4));
  }

  @override
  bool shouldRepaint(_AdsrPainter old) =>
      old.attack  != attack  ||
      old.decay   != decay   ||
      old.sustain != sustain ||
      old.release != release ||
      old.active  != active;
}
