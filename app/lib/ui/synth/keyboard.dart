import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../providers/engine_provider.dart';

/// One octave of piano keys (C3–B3, MIDI 48–59).
///
/// Supports multi-touch: each pointer independently triggers note on/off.
/// Track 0 with default synth settings.
class KeyboardWidget extends HookConsumerWidget {
  const KeyboardWidget({super.key});

  static const int _trackId = 0;

  static const _keys = [
    _KeyDef(48, 'C',  false),
    _KeyDef(49, 'C#', true),
    _KeyDef(50, 'D',  false),
    _KeyDef(51, 'D#', true),
    _KeyDef(52, 'E',  false),
    _KeyDef(53, 'F',  false),
    _KeyDef(54, 'F#', true),
    _KeyDef(55, 'G',  false),
    _KeyDef(56, 'G#', true),
    _KeyDef(57, 'A',  false),
    _KeyDef(58, 'A#', true),
    _KeyDef(59, 'B',  false),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = ref.watch(engineProvider);

    // Map pointer ID → MIDI pitch currently held by that finger.
    final Map<int, int> heldNotes = {};

    return LayoutBuilder(
      builder: (context, constraints) {
        final keyW = constraints.maxWidth / 7; // white keys fill width
        const keyH = 160.0;

        // Separate white and black keys for z-ordering.
        final whites = _keys.where((k) => !k.isBlack).toList();
        final blacks = _keys.where((k) => k.isBlack).toList();

        // Build pixel rects for each key in the layout.
        final rects = _buildRects(keyW, keyH);

        return SizedBox(
          width: constraints.maxWidth,
          height: keyH,
          child: Listener(
            onPointerDown: (e) {
              final key = _keyAt(e.localPosition, rects);
              if (key != null && !heldNotes.containsKey(e.pointer)) {
                heldNotes[e.pointer] = key.pitch;
                engine.noteOn(_trackId, key.pitch, 100);
              }
            },
            onPointerMove: (e) {
              final key = _keyAt(e.localPosition, rects);
              final prev = heldNotes[e.pointer];
              if (key != null && key.pitch != prev) {
                if (prev != null) engine.noteOff(_trackId, prev);
                heldNotes[e.pointer] = key.pitch;
                engine.noteOn(_trackId, key.pitch, 100);
              }
            },
            onPointerUp: (e) {
              final pitch = heldNotes.remove(e.pointer);
              if (pitch != null) engine.noteOff(_trackId, pitch);
            },
            onPointerCancel: (e) {
              final pitch = heldNotes.remove(e.pointer);
              if (pitch != null) engine.noteOff(_trackId, pitch);
            },
            child: Stack(
              children: [
                // White keys (bottom layer)
                ...whites.map((k) {
                  final r = rects[k.pitch]!;
                  return Positioned(
                    left: r.left, top: r.top,
                    width: r.width, height: r.height,
                    child: _WhiteKey(label: k.label),
                  );
                }),
                // Black keys (top layer)
                ...blacks.map((k) {
                  final r = rects[k.pitch]!;
                  return Positioned(
                    left: r.left, top: r.top,
                    width: r.width, height: r.height,
                    child: const _BlackKey(),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Hit-test: returns the topmost key at [pos] (black keys take priority).
  _KeyDef? _keyAt(Offset pos, Map<int, Rect> rects) {
    // Check black keys first (they overlay white keys).
    for (final k in _keys.where((k) => k.isBlack)) {
      if (rects[k.pitch]?.contains(pos) ?? false) return k;
    }
    for (final k in _keys.where((k) => !k.isBlack)) {
      if (rects[k.pitch]?.contains(pos) ?? false) return k;
    }
    return null;
  }

  /// Compute pixel Rect for every key in the octave.
  ///
  /// White keys are evenly spaced; black keys are centred between their
  /// neighbours using standard piano key offsets.
  Map<int, Rect> _buildRects(double keyW, double keyH) {
    const double bwRatio = 0.65;   // black key width relative to white key
    const double bhRatio = 0.60;   // black key height relative to white key height
    final bw = keyW * bwRatio;
    final bh = keyH * bhRatio;

    // White-key x positions (0-indexed among white keys)
    final whites = _keys.where((k) => !k.isBlack).toList();
    final Map<int, Rect> rects = {};

    for (var i = 0; i < whites.length; i++) {
      rects[whites[i].pitch] = Rect.fromLTWH(i * keyW, 0, keyW, keyH);
    }

    // Black key offsets (fraction of white-key width from left edge of white key)
    // Standard piano positions: C#=0.6, D#=1.6, F#=3.6, G#=4.6, A#=5.6
    const blackOffsets = {
      49: 0.6,  // C#
      51: 1.6,  // D#
      54: 3.6,  // F#
      56: 4.6,  // G#
      58: 5.6,  // A#
    };

    for (final k in _keys.where((k) => k.isBlack)) {
      final offset = blackOffsets[k.pitch]!;
      final x = offset * keyW - bw / 2;
      rects[k.pitch] = Rect.fromLTWH(x, 0, bw, bh);
    }

    return rects;
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _WhiteKey extends StatelessWidget {
  final String label;
  const _WhiteKey({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(4)),
        border: Border.all(color: Colors.black26),
      ),
      alignment: Alignment.bottomCenter,
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          color: Colors.black54,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _BlackKey extends StatelessWidget {
  const _BlackKey();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(4)),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 4, offset: Offset(1, 2))],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Data
// ---------------------------------------------------------------------------

class _KeyDef {
  final int pitch;
  final String label;
  final bool isBlack;
  const _KeyDef(this.pitch, this.label, this.isBlack);
}
