import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'engine/types.dart';
import 'providers/engine_provider.dart';
import 'ui/synth/keyboard.dart';

void main() {
  runApp(const ProviderScope(child: MusicboxApp()));
}

class MusicboxApp extends StatelessWidget {
  const MusicboxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'musicbox',
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF0D0D0D),
      ),
      home: const SynthTestPage(),
    );
  }
}

/// Phase 2 test screen — polyphonic synth with on-screen keyboard.
class SynthTestPage extends ConsumerStatefulWidget {
  const SynthTestPage({super.key});

  @override
  ConsumerState<SynthTestPage> createState() => _SynthTestPageState();
}

class _SynthTestPageState extends ConsumerState<SynthTestPage> {
  static const _trackId = 0;

  OscType _oscType = OscType.values.first;
  double _cutoff    = 1.0;
  double _resonance = 0.0;
  double _attack    = 0.01;
  double _release   = 0.4;

  void _setParam(VoiceParam param, double value) {
    ref.read(engineProvider).setVoiceParam(_trackId, param, value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text(
          'musicbox — synth',
          style: TextStyle(letterSpacing: 2, fontWeight: FontWeight.w300, fontSize: 16),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ---- Oscillator selector ----
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: OscType.values.map((type) {
                  final selected = type == _oscType;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _oscType = type);
                        _setParam(VoiceParam.oscType, type.index.toDouble());
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: const EdgeInsets.all(3),
                        height: 40,
                        decoration: BoxDecoration(
                          color: selected ? Colors.greenAccent : Colors.white12,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          type.name.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: selected ? Colors.black : Colors.white54,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

            // ---- Parameter sliders ----
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  _ParamSlider(
                    label: 'CUTOFF',
                    value: _cutoff,
                    onChanged: (v) { setState(() => _cutoff = v); _setParam(VoiceParam.cutoff, v); },
                  ),
                  _ParamSlider(
                    label: 'RESONANCE',
                    value: _resonance,
                    onChanged: (v) { setState(() => _resonance = v); _setParam(VoiceParam.resonance, v); },
                  ),
                  _ParamSlider(
                    label: 'ATTACK',
                    value: _attack,
                    min: 0.001, max: 2.0,
                    onChanged: (v) { setState(() => _attack = v); _setParam(VoiceParam.attack, v); },
                  ),
                  _ParamSlider(
                    label: 'RELEASE',
                    value: _release,
                    min: 0.01, max: 4.0,
                    onChanged: (v) { setState(() => _release = v); _setParam(VoiceParam.release, v); },
                  ),
                ],
              ),
            ),

            const Spacer(),

            // ---- Keyboard ----
            const Padding(
              padding: EdgeInsets.fromLTRB(0, 0, 0, 16),
              child: KeyboardWidget(),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared slider widget
// ---------------------------------------------------------------------------

class _ParamSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  const _ParamSlider({
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0.0,
    this.max = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: const TextStyle(fontSize: 10, letterSpacing: 1, color: Colors.white54),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
              activeTrackColor: Colors.greenAccent,
              thumbColor: Colors.greenAccent,
              inactiveTrackColor: Colors.white12,
              overlayColor: Colors.greenAccent.withAlpha(40),
            ),
            child: Slider(value: value, min: min, max: max, onChanged: onChanged),
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            value.toStringAsFixed(2),
            style: const TextStyle(fontSize: 10, color: Colors.white38),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}
