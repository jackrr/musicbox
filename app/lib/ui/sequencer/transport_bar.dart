import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/sequencer_provider.dart';

class TransportBar extends ConsumerWidget {
  final double bpm;
  final int numSteps;
  final bool playing;

  const TransportBar({
    super.key,
    required this.bpm,
    required this.numSteps,
    required this.playing,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(sequencerProvider.notifier);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Play / Stop
          GestureDetector(
            onTap: playing ? notifier.stop : notifier.play,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: playing ? Colors.greenAccent : Colors.white12,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                playing ? Icons.stop : Icons.play_arrow,
                color: playing ? Colors.black : Colors.white,
                size: 28,
              ),
            ),
          ),

          const SizedBox(width: 16),

          // BPM
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('BPM', style: TextStyle(fontSize: 9, color: Colors.white38, letterSpacing: 1)),
              Row(
                children: [
                  _NudgeButton(
                    icon: Icons.remove,
                    onTap: () => notifier.setBpm((bpm - 1).clamp(40, 240)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      bpm.toStringAsFixed(1),
                      style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold,
                        color: Colors.white, letterSpacing: 1,
                      ),
                    ),
                  ),
                  _NudgeButton(
                    icon: Icons.add,
                    onTap: () => notifier.setBpm((bpm + 1).clamp(40, 240)),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(width: 20),

          // Steps selector
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('STEPS', style: TextStyle(fontSize: 9, color: Colors.white38, letterSpacing: 1)),
              Row(
                children: [8, 16, 32, 64].map((n) {
                  final sel = n == numSteps;
                  return GestureDetector(
                    onTap: () => notifier.setNumSteps(n),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 100),
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: sel ? Colors.greenAccent : Colors.white10,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$n',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: sel ? Colors.black : Colors.white54,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NudgeButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _NudgeButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 28, height: 28,
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(icon, size: 16, color: Colors.white54),
    ),
  );
}
