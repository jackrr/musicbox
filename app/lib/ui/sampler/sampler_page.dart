import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../engine/types.dart';
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

// ---------------------------------------------------------------------------
// Individual sample pad
// ---------------------------------------------------------------------------

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

  Future<void> _recordSample(BuildContext context, WidgetRef ref) async {
    // Request microphone permission
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission required to record.')),
        );
      }
      return;
    }

    final engine = ref.read(engineProvider);
    final started = engine.startRecording();
    if (!started) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open microphone.')),
        );
      }
      return;
    }

    // Show a dialog while recording — dismiss to stop
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Recording…', style: TextStyle(color: Colors.redAccent)),
        content: const Text(
          'Tap Stop when done (max 60 s).',
          style: TextStyle(color: Colors.white54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Stop', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      // Discard — still need to stop the stream; we'll ignore the file
      final dir = await getApplicationDocumentsDirectory();
      final tmpPath = '${dir.path}/_rec_discard.wav';
      engine.stopRecording(tmpPath);
      try { File(tmpPath).deleteSync(); } catch (_) {}
      return;
    }

    // Save to app documents directory
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/rec_t${trackIndex + 1}_${DateTime.now().millisecondsSinceEpoch}.wav';

    final ok = engine.stopRecording(path);
    if (!ok) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recording failed.')),
        );
      }
      return;
    }

    // Load the recorded file into the sampler track
    final loaded = engine.loadSample(trackIndex, path);
    if (loaded) {
      ref.read(projectProvider.notifier).updateSamplePath(trackIndex, path);
    }
  }

  void _showEditor(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF111111),
      isScrollControlled: true,
      builder: (_) => _SampleEditorSheet(
        trackIndex: trackIndex,
        track: track,
        color: color,
        onPickSample: () => _pickSample(ref),
        onRecordSample: () => _recordSample(context, ref),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasPath = track.samplePath != null;
    final name = hasPath
        ? track.samplePath!.split('/').last
        : 'T${trackIndex + 1}  —  empty';

    return GestureDetector(
      onTap: () {
        final engine = ref.read(engineProvider);
        engine.noteOn(trackIndex, 60, 100);
        if (!hasPath) engine.noteOff(trackIndex, 60);
      },
      onLongPress: () => _showEditor(context, ref),
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
                'hold to edit',
                style: TextStyle(fontSize: 9, color: Colors.white24),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sample editor bottom sheet
// ---------------------------------------------------------------------------

class _SampleEditorSheet extends ConsumerStatefulWidget {
  final int trackIndex;
  final TrackConfig track;
  final Color color;
  final VoidCallback onPickSample;
  final VoidCallback onRecordSample;

  const _SampleEditorSheet({
    required this.trackIndex,
    required this.track,
    required this.color,
    required this.onPickSample,
    required this.onRecordSample,
  });

  @override
  ConsumerState<_SampleEditorSheet> createState() => _SampleEditorSheetState();
}

class _SampleEditorSheetState extends ConsumerState<_SampleEditorSheet> {
  void _setSampleParam(SampleParam param, double value) {
    ref.read(engineProvider).setSampleParam(widget.trackIndex, param, value);
    ref.read(projectProvider.notifier).updateSampleParam(widget.trackIndex, param, value);
  }

  @override
  Widget build(BuildContext context) {
    final sp = widget.track.sampleParams;
    final color = widget.color;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.album, color: color, size: 18),
              const SizedBox(width: 8),
              Text(
                'T${widget.trackIndex + 1}  —  sample editor',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Load / Record buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onPickSample();
                  },
                  icon: const Icon(Icons.folder_open, size: 16),
                  label: const Text('Load file'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onRecordSample();
                  },
                  icon: const Icon(Icons.mic, size: 16, color: Colors.redAccent),
                  label: const Text('Record', style: TextStyle(color: Colors.redAccent)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                  ),
                ),
              ),
            ],
          ),

          if (widget.track.samplePath != null) ...[
            const SizedBox(height: 20),
            const Divider(color: Colors.white12),
            const SizedBox(height: 12),

            // Trim start
            _SliderRow(
              label: 'Trim start',
              value: sp.trimStart,
              min: 0.0, max: 0.99,
              color: color,
              onChanged: (v) => _setSampleParam(SampleParam.trimStart, v),
            ),
            // Trim end
            _SliderRow(
              label: 'Trim end',
              value: sp.trimEnd,
              min: 0.01, max: 1.0,
              color: color,
              onChanged: (v) => _setSampleParam(SampleParam.trimEnd, v),
            ),
            // Root note (base pitch)
            _SliderRow(
              label: 'Root note  (${_noteName(sp.basePitch)})',
              value: sp.basePitch.toDouble(),
              min: 0.0, max: 127.0,
              divisions: 127,
              color: color,
              onChanged: (v) => _setSampleParam(SampleParam.basePitch, v),
            ),
            // Playback rate
            _SliderRow(
              label: 'Speed  ×${sp.playbackRate.toStringAsFixed(2)}',
              value: sp.playbackRate,
              min: 0.25, max: 4.0,
              color: color,
              onChanged: (v) => _setSampleParam(SampleParam.playbackRate, v),
            ),
          ],
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final Color color;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 130,
          child: Text(label,
            style: const TextStyle(fontSize: 11, color: Colors.white54)),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: color,
              thumbColor: color,
              inactiveTrackColor: Colors.white12,
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min, max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

String _noteName(int midi) {
  const names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
  return '${names[midi % 12]}${midi ~/ 12 - 1}';
}
