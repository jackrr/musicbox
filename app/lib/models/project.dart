import '../engine/types.dart';

const int kNumTracks = 8;
const int kMaxSteps  = 64;

// ---------------------------------------------------------------------------
// Voice params snapshot
// ---------------------------------------------------------------------------

class VoiceParamsData {
  final OscType oscType;
  final double attack;
  final double decay;
  final double sustain;
  final double release;
  final double volume;

  const VoiceParamsData({
    this.oscType = OscType.sine,
    this.attack  = 0.01,
    this.decay   = 0.1,
    this.sustain = 0.7,
    this.release = 0.4,
    this.volume  = 0.8,
  });

  VoiceParamsData copyWith({
    OscType? oscType, double? attack, double? decay,
    double? sustain, double? release, double? volume,
  }) => VoiceParamsData(
    oscType: oscType ?? this.oscType,
    attack:  attack  ?? this.attack,
    decay:   decay   ?? this.decay,
    sustain: sustain ?? this.sustain,
    release: release ?? this.release,
    volume:  volume  ?? this.volume,
  );

  Map<String, dynamic> toJson() => {
    'oscType': oscType.index,
    'attack':  attack,
    'decay':   decay,
    'sustain': sustain,
    'release': release,
    'volume':  volume,
  };

  factory VoiceParamsData.fromJson(Map<String, dynamic> j) => VoiceParamsData(
    oscType: OscType.values[j['oscType'] as int],
    attack:  (j['attack']  as num).toDouble(),
    decay:   (j['decay']   as num).toDouble(),
    sustain: (j['sustain'] as num).toDouble(),
    release: (j['release'] as num).toDouble(),
    volume:  (j['volume']  as num? ?? 0.8).toDouble(),
  );
}

// ---------------------------------------------------------------------------
// Effects params snapshot
// ---------------------------------------------------------------------------

class TrackEffectsData {
  final double reverbSend;
  final double delaySend;
  final double delayTime;
  final double delayFeedback;
  final double distDrive;
  final int    filterMode;      // 0=off, 1=LP, 2=HP
  final double filterCutoff;
  final double filterResonance;

  const TrackEffectsData({
    this.reverbSend     = 0.0,
    this.delaySend      = 0.0,
    this.delayTime      = 0.5,
    this.delayFeedback  = 0.4,
    this.distDrive      = 0.0,
    this.filterMode     = 0,
    this.filterCutoff   = 0.5,
    this.filterResonance = 0.0,
  });

  TrackEffectsData copyWith({
    double? reverbSend, double? delaySend, double? delayTime,
    double? delayFeedback, double? distDrive,
    int? filterMode, double? filterCutoff, double? filterResonance,
  }) => TrackEffectsData(
    reverbSend:     reverbSend     ?? this.reverbSend,
    delaySend:      delaySend      ?? this.delaySend,
    delayTime:      delayTime      ?? this.delayTime,
    delayFeedback:  delayFeedback  ?? this.delayFeedback,
    distDrive:      distDrive      ?? this.distDrive,
    filterMode:     filterMode     ?? this.filterMode,
    filterCutoff:   filterCutoff   ?? this.filterCutoff,
    filterResonance: filterResonance ?? this.filterResonance,
  );

  Map<String, dynamic> toJson() => {
    'reverbSend': reverbSend, 'delaySend': delaySend,
    'delayTime': delayTime, 'delayFeedback': delayFeedback,
    'distDrive': distDrive,
    'filterMode': filterMode,
    'filterCutoff': filterCutoff,
    'filterResonance': filterResonance,
  };

  factory TrackEffectsData.fromJson(Map<String, dynamic> j) => TrackEffectsData(
    reverbSend:     (j['reverbSend']     as num).toDouble(),
    delaySend:      (j['delaySend']      as num).toDouble(),
    delayTime:      (j['delayTime']      as num).toDouble(),
    delayFeedback:  (j['delayFeedback']  as num).toDouble(),
    distDrive:      (j['distDrive']      as num).toDouble(),
    filterMode:     (j['filterMode']     as int?  ?? 0),
    filterCutoff:   (j['filterCutoff']   as num?  ?? 0.5).toDouble(),
    filterResonance: (j['filterResonance'] as num? ?? 0.0).toDouble(),
  );
}

// ---------------------------------------------------------------------------
// Sample params snapshot
// ---------------------------------------------------------------------------

class SampleParamsData {
  final double trimStart;    // 0..1
  final double trimEnd;      // 0..1
  final int    basePitch;    // MIDI 0–127
  final double playbackRate; // 0.25..4.0

  const SampleParamsData({
    this.trimStart    = 0.0,
    this.trimEnd      = 1.0,
    this.basePitch    = 60,
    this.playbackRate = 1.0,
  });

  SampleParamsData copyWith({
    double? trimStart, double? trimEnd, int? basePitch, double? playbackRate,
  }) => SampleParamsData(
    trimStart:    trimStart    ?? this.trimStart,
    trimEnd:      trimEnd      ?? this.trimEnd,
    basePitch:    basePitch    ?? this.basePitch,
    playbackRate: playbackRate ?? this.playbackRate,
  );

  Map<String, dynamic> toJson() => {
    'trimStart': trimStart, 'trimEnd': trimEnd,
    'basePitch': basePitch, 'playbackRate': playbackRate,
  };

  factory SampleParamsData.fromJson(Map<String, dynamic> j) => SampleParamsData(
    trimStart:    (j['trimStart']    as num? ?? 0.0).toDouble(),
    trimEnd:      (j['trimEnd']      as num? ?? 1.0).toDouble(),
    basePitch:    (j['basePitch']    as int? ?? 60),
    playbackRate: (j['playbackRate'] as num? ?? 1.0).toDouble(),
  );
}

// ---------------------------------------------------------------------------
// Pad layout model
// ---------------------------------------------------------------------------

class PadCell {
  final int trackId;
  final String label;
  final int colorValue; // Color.value (ARGB)
  final int colSpan;    // 1..gridColumns
  final int rowSpan;    // 1..N

  const PadCell({
    required this.trackId,
    required this.label,
    required this.colorValue,
    this.colSpan = 1,
    this.rowSpan = 1,
  });

  PadCell copyWith({
    int? trackId, String? label, int? colorValue,
    int? colSpan, int? rowSpan,
  }) => PadCell(
    trackId:    trackId    ?? this.trackId,
    label:      label      ?? this.label,
    colorValue: colorValue ?? this.colorValue,
    colSpan:    colSpan    ?? this.colSpan,
    rowSpan:    rowSpan    ?? this.rowSpan,
  );

  Map<String, dynamic> toJson() => {
    'trackId': trackId, 'label': label, 'colorValue': colorValue,
    'colSpan': colSpan, 'rowSpan': rowSpan,
  };

  factory PadCell.fromJson(Map<String, dynamic> j) => PadCell(
    trackId:    j['trackId']    as int,
    label:      j['label']      as String,
    colorValue: j['colorValue'] as int,
    colSpan:    j['colSpan']    as int? ?? 1,
    rowSpan:    j['rowSpan']    as int? ?? 1,
  );
}

class PadLayout {
  final String name;
  final List<PadCell> cells;

  const PadLayout({required this.name, required this.cells});

  PadLayout copyWith({String? name, List<PadCell>? cells}) => PadLayout(
    name:  name  ?? this.name,
    cells: cells ?? this.cells,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'cells': cells.map((c) => c.toJson()).toList(),
  };

  factory PadLayout.fromJson(Map<String, dynamic> j) => PadLayout(
    name:  j['name'] as String,
    cells: (j['cells'] as List)
        .map((c) => PadCell.fromJson(c as Map<String, dynamic>))
        .toList(),
  );

  static const List<int> _defaultColors = [
    0xFF69F0AE, // greenAccent
    0xFF4FC3F7, // lightBlue
    0xFFFFB74D, // orange
    0xFFCE93D8, // purple
    0xFFEF9A9A, // pink
    0xFFA5D6A7, // lightGreen
    0xFFFFF176, // yellow
    0xFFB0BEC5, // grey-blue
  ];

  factory PadLayout.defaultLayout() => PadLayout(
    name: 'Default',
    cells: List.generate(8, (i) => PadCell(
      trackId:    i,
      label:      'T${i + 1}',
      colorValue: _defaultColors[i],
    )),
  );
}

// ---------------------------------------------------------------------------
// Track config
// ---------------------------------------------------------------------------

enum TrackMode { synth, sampler }

class TrackConfig {
  final TrackMode mode;
  final String? samplePath;
  final VoiceParamsData voiceParams;
  final TrackEffectsData effects;
  final SampleParamsData sampleParams;
  final List<StepData> steps; // length == numSteps (padded to kMaxSteps)

  const TrackConfig({
    this.mode        = TrackMode.synth,
    this.samplePath,
    this.voiceParams  = const VoiceParamsData(),
    this.effects      = const TrackEffectsData(),
    this.sampleParams = const SampleParamsData(),
    required this.steps,
  });

  factory TrackConfig.empty() => TrackConfig(
    steps: List.filled(kMaxSteps, StepData.empty),
  );

  TrackConfig copyWith({
    TrackMode? mode, String? samplePath, VoiceParamsData? voiceParams,
    TrackEffectsData? effects, SampleParamsData? sampleParams,
    List<StepData>? steps,
  }) => TrackConfig(
    mode:         mode         ?? this.mode,
    samplePath:   samplePath   ?? this.samplePath,
    voiceParams:  voiceParams  ?? this.voiceParams,
    effects:      effects      ?? this.effects,
    sampleParams: sampleParams ?? this.sampleParams,
    steps:        steps        ?? this.steps,
  );

  Map<String, dynamic> toJson() => {
    'mode':         mode.index,
    'samplePath':   samplePath,
    'voiceParams':  voiceParams.toJson(),
    'effects':      effects.toJson(),
    'sampleParams': sampleParams.toJson(),
    'steps':        steps.map((s) => s.toJson()).toList(),
  };

  factory TrackConfig.fromJson(Map<String, dynamic> j) => TrackConfig(
    mode:        TrackMode.values[j['mode'] as int],
    samplePath:  j['samplePath'] as String?,
    voiceParams: VoiceParamsData.fromJson(j['voiceParams'] as Map<String, dynamic>),
    effects:     TrackEffectsData.fromJson(j['effects'] as Map<String, dynamic>),
    sampleParams: j.containsKey('sampleParams')
        ? SampleParamsData.fromJson(j['sampleParams'] as Map<String, dynamic>)
        : const SampleParamsData(),
    steps:       (j['steps'] as List)
        .map((s) => StepData.fromJson(s as Map<String, dynamic>))
        .toList(),
  );
}

// ---------------------------------------------------------------------------
// Project
// ---------------------------------------------------------------------------

class Project {
  final String id;
  final String name;
  final double bpm;
  final int numSteps;
  final List<TrackConfig> tracks; // length kNumTracks
  final double reverbRoom;  // global reverb room size 0..1
  final double reverbDamp;  // global reverb damping 0..1
  final List<PadLayout> padLayouts;
  final int activePadLayout;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Project({
    required this.id,
    required this.name,
    this.bpm       = 120.0,
    this.numSteps  = 16,
    required this.tracks,
    this.reverbRoom = 0.5,
    this.reverbDamp = 0.5,
    required this.padLayouts,
    this.activePadLayout = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Project.create({String name = 'New Project'}) {
    final now = DateTime.now();
    return Project(
      id:         now.millisecondsSinceEpoch.toString(),
      name:       name,
      tracks:     List.generate(kNumTracks, (_) => TrackConfig.empty()),
      padLayouts: [PadLayout.defaultLayout()],
      createdAt:  now,
      updatedAt:  now,
    );
  }

  Project copyWith({
    String? name, double? bpm, int? numSteps,
    List<TrackConfig>? tracks,
    double? reverbRoom, double? reverbDamp,
    List<PadLayout>? padLayouts, int? activePadLayout,
    DateTime? updatedAt,
  }) => Project(
    id:               id,
    name:             name             ?? this.name,
    bpm:              bpm              ?? this.bpm,
    numSteps:         numSteps         ?? this.numSteps,
    tracks:           tracks           ?? this.tracks,
    reverbRoom:       reverbRoom       ?? this.reverbRoom,
    reverbDamp:       reverbDamp       ?? this.reverbDamp,
    padLayouts:       padLayouts       ?? this.padLayouts,
    activePadLayout:  activePadLayout  ?? this.activePadLayout,
    createdAt:        createdAt,
    updatedAt:        updatedAt        ?? this.updatedAt,
  );

  Map<String, dynamic> toJson() => {
    'id':              id,
    'name':            name,
    'bpm':             bpm,
    'numSteps':        numSteps,
    'tracks':          tracks.map((t) => t.toJson()).toList(),
    'reverbRoom':      reverbRoom,
    'reverbDamp':      reverbDamp,
    'padLayouts':      padLayouts.map((l) => l.toJson()).toList(),
    'activePadLayout': activePadLayout,
    'createdAt':       createdAt.toIso8601String(),
    'updatedAt':       updatedAt.toIso8601String(),
  };

  factory Project.fromJson(Map<String, dynamic> j) => Project(
    id:        j['id']   as String,
    name:      j['name'] as String,
    bpm:       (j['bpm'] as num).toDouble(),
    numSteps:  j['numSteps'] as int,
    tracks:    (j['tracks'] as List)
        .map((t) => TrackConfig.fromJson(t as Map<String, dynamic>))
        .toList(),
    reverbRoom: (j['reverbRoom'] as num? ?? 0.5).toDouble(),
    reverbDamp: (j['reverbDamp'] as num? ?? 0.5).toDouble(),
    padLayouts: j.containsKey('padLayouts')
        ? (j['padLayouts'] as List)
            .map((l) => PadLayout.fromJson(l as Map<String, dynamic>))
            .toList()
        : [PadLayout.defaultLayout()],
    activePadLayout: j['activePadLayout'] as int? ?? 0,
    createdAt: DateTime.parse(j['createdAt'] as String),
    updatedAt: DateTime.parse(j['updatedAt'] as String),
  );
}
