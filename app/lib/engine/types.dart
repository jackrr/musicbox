/// Oscillator waveform type.
///
/// Values map to Rust `OscType` enum (repr u8 index).
enum OscType { sine, saw, square, triangle, noise }

/// Voice parameter IDs — must match the Rust `VoiceParam` enum (repr u8).
enum VoiceParam {
  oscType,   // 0..4 via OscType index
  attack,    // seconds (0.001..10)
  decay,     // seconds
  sustain,   // 0..1
  release,   // seconds
  cutoff,    // 0..1 normalised (20 Hz..20 kHz log)
  resonance, // 0..1 normalised (Q 0.5..20)
  volume,    // 0..1
}
