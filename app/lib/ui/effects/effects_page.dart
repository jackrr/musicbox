import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/types.dart';
import '../../models/project.dart';
import '../../providers/engine_provider.dart';
import '../../providers/project_provider.dart';

class EffectsPage extends ConsumerStatefulWidget {
  const EffectsPage({super.key});

  @override
  ConsumerState<EffectsPage> createState() => _EffectsPageState();
}

class _EffectsPageState extends ConsumerState<EffectsPage> {
  int _selectedTrack = 0;

  void _setEffect(EffectParam param, double value) {
    ref.read(engineProvider).setEffect(_selectedTrack, param, value);
    ref.read(projectProvider.notifier).updateEffect(_selectedTrack, param, value);
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
            final fx = project.tracks[_selectedTrack].effects;
            return Column(
              children: [
                // Track selector
                SizedBox(
                  height: 40,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    itemCount: kNumTracks,
                    itemBuilder: (_, i) {
                      final sel = i == _selectedTrack;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedTrack = i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 100),
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: sel ? const Color(0xFFCE93D8) : Colors.white10,
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
                ),

                const Divider(height: 1, color: Colors.white12),

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _EffectSection(
                          title: 'REVERB',
                          color: const Color(0xFF4FC3F7),
                          children: [
                            _EffectSlider(
                              label: 'Send',
                              value: fx.reverbSend,
                              onChanged: (v) => _setEffect(EffectParam.reverbSend, v),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        _EffectSection(
                          title: 'DELAY',
                          color: const Color(0xFFFFB74D),
                          children: [
                            _EffectSlider(
                              label: 'Send',
                              value: fx.delaySend,
                              onChanged: (v) => _setEffect(EffectParam.delaySend, v),
                            ),
                            _EffectSlider(
                              label: 'Time (beats)',
                              value: fx.delayTime,
                              min: 0.0625, max: 4.0,
                              onChanged: (v) => _setEffect(EffectParam.delayTime, v),
                            ),
                            _EffectSlider(
                              label: 'Feedback',
                              value: fx.delayFeedback,
                              max: 0.95,
                              onChanged: (v) => _setEffect(EffectParam.delayFeedback, v),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        _EffectSection(
                          title: 'DISTORTION',
                          color: const Color(0xFFEF9A9A),
                          children: [
                            _EffectSlider(
                              label: 'Drive',
                              value: fx.distDrive,
                              onChanged: (v) => _setEffect(EffectParam.distDrive, v),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _EffectSection extends StatelessWidget {
  final String title;
  final Color color;
  final List<Widget> children;

  const _EffectSection({
    required this.title,
    required this.color,
    required this.children,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
          letterSpacing: 2,
        ),
      ),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withAlpha(18),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withAlpha(40)),
        ),
        child: Column(children: children),
      ),
    ],
  );
}

class _EffectSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  const _EffectSlider({
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
        width: 100,
        child: Text(
          label,
          style: const TextStyle(fontSize: 11, color: Colors.white54),
        ),
      ),
      Expanded(
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
            activeTrackColor: Colors.white70,
            thumbColor: Colors.white,
            inactiveTrackColor: Colors.white12,
            overlayColor: Colors.white.withAlpha(30),
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min, max: max,
            onChanged: onChanged,
          ),
        ),
      ),
      SizedBox(
        width: 42,
        child: Text(
          value.toStringAsFixed(2),
          style: const TextStyle(fontSize: 9, color: Colors.white38),
          textAlign: TextAlign.right,
        ),
      ),
    ],
  );
}
