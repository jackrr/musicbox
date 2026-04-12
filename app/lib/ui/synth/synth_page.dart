import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/types.dart';
import '../../models/project.dart';
import '../../providers/engine_provider.dart';
import '../../providers/project_provider.dart';
import 'keyboard.dart';

class SynthPage extends ConsumerStatefulWidget {
  const SynthPage({super.key});

  @override
  ConsumerState<SynthPage> createState() => _SynthPageState();
}

class _SynthPageState extends ConsumerState<SynthPage> {
  int _selectedTrack = 0;

  void _setParam(VoiceParam param, double value) {
    ref.read(engineProvider).setVoiceParam(_selectedTrack, param, value);
    ref.read(projectProvider.notifier).updateVoiceParam(_selectedTrack, param, value);
  }

  @override
  Widget build(BuildContext context) {
    final projectAsync = ref.watch(projectProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(
        child: projectAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (project) {
            final vp = project.tracks[_selectedTrack].voiceParams;
            return Column(
              children: [
                // Track selector
                _TrackSelector(
                  selected: _selectedTrack,
                  onChanged: (i) => setState(() => _selectedTrack = i),
                ),

                const Divider(height: 1, color: Colors.white12),

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        // Osc type selector
                        _OscSelector(
                          current: vp.oscType,
                          onChanged: (t) => _setParam(VoiceParam.oscType, t.index.toDouble()),
                        ),

                        const SizedBox(height: 16),

                        // ADSR + filter sliders
                        _ParamRow(label: 'ATK', value: vp.attack,    min: 0.001, max: 4.0,
                            onChanged: (v) => _setParam(VoiceParam.attack, v)),
                        _ParamRow(label: 'DEC', value: vp.decay,     min: 0.001, max: 4.0,
                            onChanged: (v) => _setParam(VoiceParam.decay, v)),
                        _ParamRow(label: 'SUS', value: vp.sustain,
                            onChanged: (v) => _setParam(VoiceParam.sustain, v)),
                        _ParamRow(label: 'REL', value: vp.release,   min: 0.01,  max: 8.0,
                            onChanged: (v) => _setParam(VoiceParam.release, v)),
                        _ParamRow(label: 'CUT', value: vp.cutoff,
                            onChanged: (v) => _setParam(VoiceParam.cutoff, v)),
                        _ParamRow(label: 'RES', value: vp.resonance,
                            onChanged: (v) => _setParam(VoiceParam.resonance, v)),
                        _ParamRow(label: 'VOL', value: vp.volume,
                            onChanged: (v) => _setParam(VoiceParam.volume, v)),
                      ],
                    ),
                  ),
                ),

                // Keyboard
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
                  child: KeyboardWidget(trackId: _selectedTrack),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _TrackSelector extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;

  const _TrackSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 40,
    child: ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: kNumTracks,
      itemBuilder: (_, i) {
        final sel = i == selected;
        return GestureDetector(
          onTap: () => onChanged(i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            margin: const EdgeInsets.only(right: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: sel ? Colors.greenAccent : Colors.white10,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'T${i + 1}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: sel ? Colors.black : Colors.white54,
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _OscSelector extends StatelessWidget {
  final OscType current;
  final ValueChanged<OscType> onChanged;

  const _OscSelector({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) => Row(
    children: OscType.values.map((t) {
      final sel = t == current;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(t),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            margin: const EdgeInsets.all(3),
            height: 36,
            decoration: BoxDecoration(
              color: sel ? Colors.greenAccent : Colors.white12,
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: Text(
              t.name.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: sel ? Colors.black : Colors.white54,
                letterSpacing: 1,
              ),
            ),
          ),
        ),
      );
    }).toList(),
  );
}

class _ParamRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  const _ParamRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0.0,
    this.max = 1.0,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(
        width: 36,
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 10, letterSpacing: 1,
            color: Colors.white54, fontWeight: FontWeight.bold,
          ),
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
          child: Slider(value: value.clamp(min, max), min: min, max: max, onChanged: onChanged),
        ),
      ),
      SizedBox(
        width: 42,
        child: Text(
          value.toStringAsFixed(3),
          style: const TextStyle(fontSize: 9, color: Colors.white38),
          textAlign: TextAlign.right,
        ),
      ),
    ],
  );
}
