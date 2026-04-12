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
  final double cutoff;
  final double resonance;
  final double volume;

  const VoiceParamsData({
    this.oscType   = OscType.sine,
    this.attack    = 0.01,
    this.decay     = 0.1,
    this.sustain   = 0.7,
    this.release   = 0.4,
    this.cutoff    = 1.0,
    this.resonance = 0.0,
    this.volume    = 0.8,
  });

  VoiceParamsData copyWith({
    OscType? oscType, double? attack, double? decay, double? sustain,
    double? release, double? cutoff, double? resonance, double? volume,
  }) => VoiceParamsData(
    oscType:   oscType   ?? this.oscType,
    attack:    attack    ?? this.attack,
    decay:     decay     ?? this.decay,
    sustain:   sustain   ?? this.sustain,
    release:   release   ?? this.release,
    cutoff:    cutoff    ?? this.cutoff,
    resonance: resonance ?? this.resonance,
    volume:    volume    ?? this.volume,
  );

  Map<String, dynamic> toJson() => {
    'oscType':   oscType.index,
    'attack':    attack,
    'decay':     decay,
    'sustain':   sustain,
    'release':   release,
    'cutoff':    cutoff,
    'resonance': resonance,
    'volume':    volume,
  };

  factory VoiceParamsData.fromJson(Map<String, dynamic> j) => VoiceParamsData(
    oscType:   OscType.values[j['oscType'] as int],
    attack:    (j['attack']    as num).toDouble(),
    decay:     (j['decay']     as num).toDouble(),
    sustain:   (j['sustain']   as num).toDouble(),
    release:   (j['release']   as num).toDouble(),
    cutoff:    (j['cutoff']    as num).toDouble(),
    resonance: (j['resonance'] as num).toDouble(),
    volume:    (j['volume']    as num).toDouble(),
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

  const TrackEffectsData({
    this.reverbSend    = 0.0,
    this.delaySend     = 0.0,
    this.delayTime     = 0.5,
    this.delayFeedback = 0.4,
    this.distDrive     = 0.0,
  });

  TrackEffectsData copyWith({
    double? reverbSend, double? delaySend, double? delayTime,
    double? delayFeedback, double? distDrive,
  }) => TrackEffectsData(
    reverbSend:    reverbSend    ?? this.reverbSend,
    delaySend:     delaySend     ?? this.delaySend,
    delayTime:     delayTime     ?? this.delayTime,
    delayFeedback: delayFeedback ?? this.delayFeedback,
    distDrive:     distDrive     ?? this.distDrive,
  );

  Map<String, dynamic> toJson() => {
    'reverbSend': reverbSend, 'delaySend': delaySend,
    'delayTime': delayTime, 'delayFeedback': delayFeedback,
    'distDrive': distDrive,
  };

  factory TrackEffectsData.fromJson(Map<String, dynamic> j) => TrackEffectsData(
    reverbSend:    (j['reverbSend']    as num).toDouble(),
    delaySend:     (j['delaySend']     as num).toDouble(),
    delayTime:     (j['delayTime']     as num).toDouble(),
    delayFeedback: (j['delayFeedback'] as num).toDouble(),
    distDrive:     (j['distDrive']     as num).toDouble(),
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
  final List<StepData> steps; // length == numSteps (padded to kMaxSteps)

  const TrackConfig({
    this.mode       = TrackMode.synth,
    this.samplePath,
    this.voiceParams = const VoiceParamsData(),
    this.effects     = const TrackEffectsData(),
    required this.steps,
  });

  factory TrackConfig.empty() => TrackConfig(
    steps: List.filled(kMaxSteps, StepData.empty),
  );

  TrackConfig copyWith({
    TrackMode? mode, String? samplePath, VoiceParamsData? voiceParams,
    TrackEffectsData? effects, List<StepData>? steps,
  }) => TrackConfig(
    mode:        mode        ?? this.mode,
    samplePath:  samplePath  ?? this.samplePath,
    voiceParams: voiceParams ?? this.voiceParams,
    effects:     effects     ?? this.effects,
    steps:       steps       ?? this.steps,
  );

  Map<String, dynamic> toJson() => {
    'mode':        mode.index,
    'samplePath':  samplePath,
    'voiceParams': voiceParams.toJson(),
    'effects':     effects.toJson(),
    'steps':       steps.map((s) => s.toJson()).toList(),
  };

  factory TrackConfig.fromJson(Map<String, dynamic> j) => TrackConfig(
    mode:        TrackMode.values[j['mode'] as int],
    samplePath:  j['samplePath'] as String?,
    voiceParams: VoiceParamsData.fromJson(j['voiceParams'] as Map<String, dynamic>),
    effects:     TrackEffectsData.fromJson(j['effects'] as Map<String, dynamic>),
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
  final DateTime createdAt;
  final DateTime updatedAt;

  const Project({
    required this.id,
    required this.name,
    this.bpm      = 120.0,
    this.numSteps = 16,
    required this.tracks,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Project.create({String name = 'New Project'}) {
    final now = DateTime.now();
    return Project(
      id:        now.millisecondsSinceEpoch.toString(),
      name:      name,
      tracks:    List.generate(kNumTracks, (_) => TrackConfig.empty()),
      createdAt: now,
      updatedAt: now,
    );
  }

  Project copyWith({
    String? name, double? bpm, int? numSteps,
    List<TrackConfig>? tracks, DateTime? updatedAt,
  }) => Project(
    id:        id,
    name:      name      ?? this.name,
    bpm:       bpm       ?? this.bpm,
    numSteps:  numSteps  ?? this.numSteps,
    tracks:    tracks    ?? this.tracks,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toJson() => {
    'id':        id,
    'name':      name,
    'bpm':       bpm,
    'numSteps':  numSteps,
    'tracks':    tracks.map((t) => t.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory Project.fromJson(Map<String, dynamic> j) => Project(
    id:        j['id']   as String,
    name:      j['name'] as String,
    bpm:       (j['bpm'] as num).toDouble(),
    numSteps:  j['numSteps'] as int,
    tracks:    (j['tracks'] as List)
        .map((t) => TrackConfig.fromJson(t as Map<String, dynamic>))
        .toList(),
    createdAt: DateTime.parse(j['createdAt'] as String),
    updatedAt: DateTime.parse(j['updatedAt'] as String),
  );
}
