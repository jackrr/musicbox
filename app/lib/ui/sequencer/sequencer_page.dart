import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/project.dart';
import '../../providers/engine_provider.dart';
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

  Future<void> _assignSample(BuildContext context, WidgetRef ref) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF111111),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_open, color: Colors.white70),
              title: const Text('Load sample file',
                style: TextStyle(color: Colors.white70)),
              onTap: () => Navigator.pop(context, 'load'),
            ),
            ListTile(
              leading: const Icon(Icons.piano, color: Colors.white70),
              title: const Text('Use synth (clear sample)',
                style: TextStyle(color: Colors.white70)),
              onTap: () => Navigator.pop(context, 'synth'),
            ),
          ],
        ),
      ),
    );

    if (action == 'load') {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio, allowMultiple: false);
      if (result == null || result.files.isEmpty) return;
      final path = result.files.single.path;
      if (path == null) return;
      final engine = ref.read(engineProvider);
      final ok = engine.loadSample(trackIndex, path);
      if (ok) ref.read(projectProvider.notifier).updateSamplePath(trackIndex, path);
    } else if (action == 'synth') {
      // Clear sample: update mode back to synth (samplePath stays but mode = synth)
      final tracks = List<TrackConfig>.from(
        ref.read(projectProvider).value!.tracks);
      final updated = tracks[trackIndex].copyWith(mode: TrackMode.synth);
      ref.read(projectProvider.notifier).updateSamplePath(
        trackIndex, updated.samplePath ?? '');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSampler = track.mode == TrackMode.sampler;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          // Track label + mode badge
          GestureDetector(
            onTap: () => _assignSample(context, ref),
            child: SizedBox(
              width: 36,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'T${trackIndex + 1}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: color,
                      letterSpacing: 1,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: isSampler ? color.withAlpha(40) : Colors.white10,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      isSampler ? 'S' : '~',
                      style: TextStyle(
                        fontSize: 9,
                        color: isSampler ? color : Colors.white38,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
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
