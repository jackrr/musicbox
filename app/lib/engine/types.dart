/// Oscillator waveform type.
///
/// Values map to Rust `OscType` enum (repr u8 index).
enum OscType { sine, saw, square, triangle, noise }

/// Voice parameter IDs — must match the Rust `VoiceParam` enum (repr u8).
enum VoiceParam {
  oscType,  // 0..4 via OscType index
  attack,   // seconds (0.001..10)
  decay,    // seconds
  sustain,  // 0..1
  release,  // seconds
  volume,   // 0..1
}

/// Transport state — must match Rust decode (param_a: 0=stop, 1=play, 2=reset).
enum TransportState { stop, play, reset }

/// Effect parameter IDs — must match Rust `EffectParam` enum (repr u8).
enum EffectParam {
  reverbSend,      // 0 — per-track: 0..1
  delayTime,       // 1 — per-track: beats (0.0625..4)
  delayFeedback,   // 2 — per-track: 0..0.95
  delaySend,       // 3 — per-track: 0..1
  distDrive,       // 4 — per-track: 0..1
  reverbRoom,      // 5 — global: 0..1
  reverbDamp,      // 6 — global: 0..1
  filterType,      // 7 — per-track: 0=off, 1=LP, 2=HP
  filterCutoff,    // 8 — per-track: 0..1 normalised
  filterResonance, // 9 — per-track: 0..1 normalised
}

/// Sample parameter IDs — must match Rust `SampleParam` enum (repr u8).
enum SampleParam {
  trimStart,    // 0 — normalised 0..1 start position in sample
  trimEnd,      // 1 — normalised 0..1 end position (1.0 = full length)
  basePitch,    // 2 — MIDI root note 0..127 (as double)
  playbackRate, // 3 — speed multiplier 0.25..4.0
}

/// Single step in the sequencer pattern.
class StepData {
  final bool active;
  final int pitch;       // MIDI 0–127
  final double velocity; // 0..1

  const StepData({
    required this.active,
    this.pitch = 60,
    this.velocity = 0.8,
  });

  StepData copyWith({bool? active, int? pitch, double? velocity}) => StepData(
        active: active ?? this.active,
        pitch: pitch ?? this.pitch,
        velocity: velocity ?? this.velocity,
      );

  Map<String, dynamic> toJson() =>
      {'active': active, 'pitch': pitch, 'velocity': velocity};

  factory StepData.fromJson(Map<String, dynamic> j) => StepData(
        active: j['active'] as bool,
        pitch: j['pitch'] as int,
        velocity: (j['velocity'] as num).toDouble(),
      );

  static StepData get empty => const StepData(active: false, pitch: 60, velocity: 0.8);
}
