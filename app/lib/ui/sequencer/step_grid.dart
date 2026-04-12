import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/types.dart';
import '../../providers/sequencer_provider.dart';
import '../widgets/step_button.dart';

class StepGrid extends ConsumerWidget {
  final int trackId;
  final List<StepData> steps;
  final int numSteps;
  final int playhead;
  final Color color;

  const StepGrid({
    super.key,
    required this.trackId,
    required this.steps,
    required this.numSteps,
    required this.playhead,
    required this.color,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final cellSize = constraints.maxWidth / numSteps;
        return SizedBox(
          height: cellSize.clamp(30.0, 52.0),
          child: Row(
            children: List.generate(numSteps, (si) {
              final step = si < steps.length ? steps[si] : StepData.empty;
              return Expanded(
                child: StepButton(
                  active:        step.active,
                  isCurrentStep: playhead == si,
                  velocity:      step.velocity,
                  activeColor:   color,
                  onTap: () => ref
                      .read(sequencerProvider.notifier)
                      .toggleStep(trackId, si, pitch: step.pitch),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}
