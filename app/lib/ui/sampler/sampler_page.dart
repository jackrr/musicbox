import 'dart:io';
import 'dart:typed_data';

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
      final dir = await getApplicationDocumentsDirectory();
      final tmpPath = '${dir.path}/_rec_discard.wav';
      engine.stopRecording(tmpPath);
      try { File(tmpPath).deleteSync(); } catch (_) {}
      return;
    }

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
      // Disable sheet drag-to-dismiss — it swallows slider/waveform gestures.
      enableDrag: false,
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

    // Use Listener for immediate noteOn on pointer-down (no tap-disambiguation
    // delay), while GestureDetector handles the long-press to open the editor.
    // Guard with hasSample() so we never accidentally trigger a synth voice.
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) {
        final engine = ref.read(engineProvider);
        if (engine.hasSample(trackIndex)) engine.noteOn(trackIndex, 60, 100);
      },
      child: GestureDetector(
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
  Float32List? _peaks;

  @override
  void initState() {
    super.initState();
    if (widget.track.samplePath != null) {
      _peaks = ref.read(engineProvider).getSamplePeaks(widget.trackIndex);
    }
  }

  void _setSampleParam(SampleParam param, double value) {
    ref.read(engineProvider).setSampleParam(widget.trackIndex, param, value);
    ref.read(projectProvider.notifier).updateSampleParam(widget.trackIndex, param, value);
  }

  @override
  Widget build(BuildContext context) {
    // Watch provider so sliders reflect live values after each change.
    final sp = ref.watch(projectProvider).valueOrNull
        ?.tracks[widget.trackIndex].sampleParams
        ?? widget.track.sampleParams;
    final color = widget.color;
    final hasPath = ref.watch(projectProvider).valueOrNull
        ?.tracks[widget.trackIndex].samplePath != null
        || widget.track.samplePath != null;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20, 16, 20,
        MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row with close button
          Row(
            children: [
              Icon(Icons.album, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'T${widget.trackIndex + 1}  —  sample editor',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white38, size: 20),
                onPressed: () => Navigator.pop(context),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
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

          if (hasPath) ...[
            const SizedBox(height: 20),
            const Divider(color: Colors.white12),
            const SizedBox(height: 12),

            // Waveform + trim handles
            _WaveformView(
              peaks: _peaks,
              trimStart: sp.trimStart,
              trimEnd: sp.trimEnd,
              color: color,
              onTrimStartChanged: (v) => _setSampleParam(SampleParam.trimStart, v),
              onTrimEndChanged:   (v) => _setSampleParam(SampleParam.trimEnd,   v),
            ),

            const SizedBox(height: 16),

            // Root note slider
            _SliderRow(
              label: 'Root note  (${_noteName(sp.basePitch)})',
              value: sp.basePitch.toDouble(),
              min: 0.0, max: 127.0,
              divisions: 127,
              color: color,
              onChanged: (v) => _setSampleParam(SampleParam.basePitch, v),
            ),
            // Playback rate slider
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

// ---------------------------------------------------------------------------
// Waveform display + draggable trim handles
// ---------------------------------------------------------------------------

class _WaveformView extends StatefulWidget {
  final Float32List? peaks;
  final double trimStart;
  final double trimEnd;
  final Color color;
  final ValueChanged<double> onTrimStartChanged;
  final ValueChanged<double> onTrimEndChanged;

  const _WaveformView({
    required this.peaks,
    required this.trimStart,
    required this.trimEnd,
    required this.color,
    required this.onTrimStartChanged,
    required this.onTrimEndChanged,
  });

  @override
  State<_WaveformView> createState() => _WaveformViewState();
}

class _WaveformViewState extends State<_WaveformView> {
  _DragTarget _dragging = _DragTarget.none;
  // Touch threshold in logical pixels for grabbing a handle.
  static const _kHandleHitSlop = 28.0;

  void _onPanStart(DragStartDetails d, double width) {
    final x = d.localPosition.dx;
    final startX = widget.trimStart * width;
    final endX   = widget.trimEnd   * width;
    final dStart = (x - startX).abs();
    final dEnd   = (x - endX).abs();

    if (dStart < _kHandleHitSlop && dStart <= dEnd) {
      setState(() => _dragging = _DragTarget.start);
    } else if (dEnd < _kHandleHitSlop) {
      setState(() => _dragging = _DragTarget.end);
    } else {
      _dragging = _DragTarget.none;
    }
  }

  void _onPanUpdate(DragUpdateDetails d, double width) {
    if (_dragging == _DragTarget.none) return;
    final norm = (d.localPosition.dx / width).clamp(0.0, 1.0);
    if (_dragging == _DragTarget.start) {
      widget.onTrimStartChanged(norm.clamp(0.0, (widget.trimEnd - 0.02).clamp(0.0, 0.99)));
    } else {
      widget.onTrimEndChanged(norm.clamp((widget.trimStart + 0.02).clamp(0.01, 1.0), 1.0));
    }
  }

  void _onPanEnd(DragEndDetails _) => setState(() => _dragging = _DragTarget.none);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart:  (d) => _onPanStart(d, width),
        onPanUpdate: (d) => _onPanUpdate(d, width),
        onPanEnd:    _onPanEnd,
        child: CustomPaint(
          size: Size(width, 100),
          painter: _WaveformPainter(
            peaks:     widget.peaks,
            trimStart: widget.trimStart,
            trimEnd:   widget.trimEnd,
            color:     widget.color,
            dragging:  _dragging,
          ),
        ),
      );
    });
  }
}

enum _DragTarget { none, start, end }

class _WaveformPainter extends CustomPainter {
  final Float32List? peaks;
  final double trimStart;
  final double trimEnd;
  final Color color;
  final _DragTarget dragging;

  _WaveformPainter({
    required this.peaks,
    required this.trimStart,
    required this.trimEnd,
    required this.color,
    required this.dragging,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final half = h / 2;

    // Background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()..color = Colors.white.withAlpha(8),
    );

    // Waveform bars
    final numPeaks = (peaks?.length ?? 0) ~/ 2;
    if (numPeaks > 0) {
      final barW = w / numPeaks;
      final activePaint   = Paint()..color = color.withAlpha(200)..strokeWidth = barW.clamp(1.0, 3.0);
      final inactivePaint = Paint()..color = color.withAlpha(50) ..strokeWidth = barW.clamp(1.0, 3.0);

      for (var i = 0; i < numPeaks; i++) {
        final mn   = peaks![i * 2];
        final mx   = peaks![i * 2 + 1];
        final x    = (i + 0.5) * barW;
        final norm = x / w;
        final p    = (norm >= trimStart && norm <= trimEnd) ? activePaint : inactivePaint;
        // Map -1..1 amplitude to pixel coords (positive = up from centre)
        final yTop = (half - mx.clamp(-1.0, 1.0) * half).clamp(0.0, h);
        final yBot = (half - mn.clamp(-1.0, 1.0) * half).clamp(0.0, h);
        canvas.drawLine(Offset(x, yTop), Offset(x, yBot.clamp(yTop, h)), p);
      }
    } else {
      // No sample — placeholder line
      canvas.drawLine(
        Offset(0, half), Offset(w, half),
        Paint()..color = Colors.white12..strokeWidth = 1,
      );
    }

    // Inactive region overlay
    final overlayPaint = Paint()..color = Colors.black.withAlpha(110);
    final sx = trimStart * w;
    final ex = trimEnd * w;
    if (sx > 0) canvas.drawRect(Rect.fromLTWH(0, 0, sx, h), overlayPaint);
    if (ex < w) canvas.drawRect(Rect.fromLTWH(ex, 0, w - ex, h), overlayPaint);

    // Trim handles
    _drawHandle(canvas, size, sx, isStart: true,  active: dragging == _DragTarget.start);
    _drawHandle(canvas, size, ex, isStart: false, active: dragging == _DragTarget.end);
  }

  void _drawHandle(Canvas canvas, Size size, double x, {required bool isStart, required bool active}) {
    final lineColor  = active ? Colors.white : color;
    final fillColor  = active ? Colors.white : color;
    final linePaint  = Paint()..color = lineColor..strokeWidth = 2;
    final fillPaint  = Paint()..color = fillColor..style = PaintingStyle.fill;

    canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);

    // Small tab at the top
    const tabW = 10.0;
    const tabH = 14.0;
    final left  = isStart ? x : x - tabW;
    final right = isStart ? x + tabW : x;
    final path = Path()
      ..moveTo(left, 0)
      ..lineTo(right, 0)
      ..lineTo(right, tabH)
      ..lineTo(x, tabH + 4)
      ..lineTo(left, tabH)
      ..close();
    canvas.drawPath(path, fillPaint);
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.peaks    != peaks    ||
      old.trimStart != trimStart ||
      old.trimEnd   != trimEnd   ||
      old.color     != color     ||
      old.dragging  != dragging;
}

// ---------------------------------------------------------------------------
// Slider row
// ---------------------------------------------------------------------------

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
