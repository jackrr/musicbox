import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/project.dart';
import '../../providers/project_provider.dart';
import '../../providers/sequencer_provider.dart';
import 'step_grid.dart';
import 'transport_bar.dart';

class SequencerPage extends ConsumerWidget {
  const SequencerPage({super.key});

  static const _trackColors = [
    Colors.greenAccent,
    Color(0xFF4FC3F7), // light blue
    Color(0xFFFFB74D), // orange
    Color(0xFFCE93D8), // purple
    Color(0xFFEF9A9A), // pink
    Color(0xFFA5D6A7), // light green
    Color(0xFFFFF176), // yellow
    Color(0xFFB0BEC5), // grey-blue
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectAsync = ref.watch(projectProvider);
    final seq          = ref.watch(sequencerProvider);
    final playhead     = ref.watch(playheadProvider).value ?? -1;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(
        child: Column(
          children: [
            // Transport bar
            TransportBar(
              bpm:      seq.bpm,
              numSteps: seq.numSteps,
              playing:  seq.playing,
            ),

            const Divider(height: 1, color: Colors.white12),

            // Step grid
            Expanded(
              child: projectAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (project) => ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: kNumTracks,
                  itemBuilder: (ctx, ti) => _TrackRow(
                    trackIndex: ti,
                    track:      project.tracks[ti],
                    numSteps:   seq.numSteps,
                    playhead:   playhead,
                    color:      _trackColors[ti % _trackColors.length],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _TrackRow extends ConsumerWidget {
  final int trackIndex;
  final TrackConfig track;
  final int numSteps;
  final int playhead;
  final Color color;

  const _TrackRow({
    required this.trackIndex,
    required this.track,
    required this.numSteps,
    required this.playhead,
    required this.color,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          // Track label
          SizedBox(
            width: 36,
            child: Text(
              'T${trackIndex + 1}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: color,
                letterSpacing: 1,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          // Steps
          Expanded(
            child: StepGrid(
              trackId:  trackIndex,
              steps:    track.steps.take(numSteps).toList(),
              numSteps: numSteps,
              playhead: playhead,
              color:    color,
            ),
          ),
        ],
      ),
    );
  }
}
