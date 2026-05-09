import '../models/project.dart';

/// Build a ~10-line, human-readable summary of the current [Project].
///
/// This is the *only* file in the bug-report module that knows about
/// musicbox-specific types. To port the module to a different Flutter app,
/// replace this file with one that stringifies that app's domain model.
String buildProjectDigest(Project? p) {
  if (p == null) return 'no project loaded';

  final lines = <String>[
    'project: ${p.name}',
    'bpm: ${p.bpm.toStringAsFixed(1)}  steps: ${p.numSteps}',
    'reverb: room=${p.reverbRoom.toStringAsFixed(2)} damp=${p.reverbDamp.toStringAsFixed(2)}',
    'pad layouts: ${p.padLayouts.length} (active=${p.activePadLayout})',
    'tracks:',
  ];

  for (var i = 0; i < p.tracks.length; i++) {
    final t = p.tracks[i];
    final activeSteps =
        t.steps.take(p.numSteps).where((s) => s.active).length;
    final detail = t.mode == TrackMode.sampler
        ? 'sampler ${t.samplePath == null ? "(no sample)" : "✓"}'
        : 'synth ${t.voiceParams.oscType.name}';
    final fx = <String>[
      if (t.effects.reverbSend > 0.01) 'rev=${_p2(t.effects.reverbSend)}',
      if (t.effects.delaySend  > 0.01) 'dly=${_p2(t.effects.delaySend)}',
      if (t.effects.distDrive  > 0.01) 'dist=${_p2(t.effects.distDrive)}',
      if (t.effects.filterMode != 0)
        'flt=${t.effects.filterMode == 1 ? "LP" : "HP"}',
    ];
    lines.add(
      '  $i: $detail  vol=${_p2(t.voiceParams.volume)}  '
      'steps=$activeSteps${fx.isEmpty ? "" : "  ${fx.join(" ")}"}',
    );
  }

  return lines.join('\n');
}

String _p2(double v) => v.toStringAsFixed(2);
