import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/project.dart';
import '../../providers/engine_provider.dart';
import '../../providers/project_provider.dart';

class SamplerPage extends ConsumerWidget {
  const SamplerPage({super.key});

  static const _colors = [
    Colors.greenAccent,
    Color(0xFF4FC3F7),
    Color(0xFFFFB74D),
    Color(0xFFCE93D8),
    Color(0xFFEF9A9A),
    Color(0xFFA5D6A7),
    Color(0xFFFFF176),
    Color(0xFFB0BEC5),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectAsync = ref.watch(projectProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(
        child: projectAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('$e')),
          data: (project) => Padding(
            padding: const EdgeInsets.all(16),
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.4,
              ),
              itemCount: kNumTracks,
              itemBuilder: (ctx, ti) => _SamplePad(
                trackIndex: ti,
                track: project.tracks[ti],
                color: _colors[ti % _colors.length],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SamplePad extends ConsumerWidget {
  final int trackIndex;
  final TrackConfig track;
  final Color color;

  const _SamplePad({
    required this.trackIndex,
    required this.track,
    required this.color,
  });

  Future<void> _pickSample(WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;

    final engine = ref.read(engineProvider);
    final ok = engine.loadSample(trackIndex, path);
    if (ok) {
      ref.read(projectProvider.notifier).updateSamplePath(trackIndex, path);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasPath = track.samplePath != null;
    final name = hasPath
        ? track.samplePath!.split('/').last
        : 'T${trackIndex + 1}  —  empty';

    return GestureDetector(
      onTap: () => ref.read(engineProvider).noteOn(trackIndex, 60, 100),
      onLongPress: () => _pickSample(ref),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        decoration: BoxDecoration(
          color: hasPath ? color.withAlpha(40) : Colors.white10,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasPath ? color : Colors.white24,
            width: 2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              hasPath ? Icons.music_note : Icons.add,
              color: hasPath ? color : Colors.white38,
              size: 32,
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                name,
                style: TextStyle(
                  fontSize: 11,
                  color: hasPath ? color : Colors.white38,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (!hasPath)
              const Text(
                'hold to load',
                style: TextStyle(fontSize: 9, color: Colors.white24),
              ),
          ],
        ),
      ),
    );
  }
}
