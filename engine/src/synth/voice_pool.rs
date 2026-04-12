use crate::commands::Command;
use crate::synth::voice::{TrackParams, Voice};

pub const NUM_VOICES: usize = 16;
pub const NUM_TRACKS: usize = 8;

/// Maximum frames per audio callback. Pre-allocate scratch to avoid
/// heap allocation inside the real-time audio thread.
const MAX_FRAMES: usize = 8192;

pub struct VoicePool {
    voices:       [Voice; NUM_VOICES],
    track_params: [TrackParams; NUM_TRACKS],
    voice_age:    u64,
    /// Mono mix scratch — pre-allocated, reused every callback.
    scratch:      Box<[f32; MAX_FRAMES]>,
}

impl VoicePool {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            voices:       std::array::from_fn(|_| Voice::new(sample_rate)),
            track_params: std::array::from_fn(|_| TrackParams::default()),
            voice_age:    0,
            scratch:      Box::new([0.0f32; MAX_FRAMES]),
        }
    }

    /// Handle a decoded command from the Dart side.
    ///
    /// Called from the audio thread — must not allocate.
    pub fn handle(&mut self, cmd: Command) {
        match cmd {
            Command::NoteOn  { track_id, pitch, velocity } => self.note_on(track_id, pitch, velocity),
            Command::NoteOff { track_id, pitch }           => self.note_off(track_id, pitch),
            Command::SetVoiceParam { track_id, param, value } => {
                if let Some(tp) = self.track_params.get_mut(track_id as usize) {
                    tp.apply(param, value);
                }
            }
        }
    }

    /// Render all active voices into `output` (interleaved, pre-zeroed by caller).
    ///
    /// Applies a tanh soft-clip on the stereo sum to prevent hard clipping
    /// when many voices play simultaneously.
    pub fn render(&mut self, output: &mut [f32], n_frames: usize, channels: usize) {
        let frames = n_frames.min(MAX_FRAMES);
        let scratch = &mut self.scratch[..frames];
        scratch.fill(0.0);

        for voice in self.voices.iter_mut() {
            if voice.active {
                voice.render(scratch, frames);
            }
        }

        // Scatter mono scratch → interleaved output with soft-clip
        for (f, &mono) in scratch.iter().enumerate() {
            let clipped = soft_clip(mono);
            for ch in 0..channels {
                let idx = f * channels + ch;
                if idx < output.len() {
                    output[idx] = clipped;
                }
            }
        }
    }

    // --- private ---

    fn note_on(&mut self, track_id: u8, pitch: u8, velocity: f32) {
        let ti = (track_id as usize).min(NUM_TRACKS - 1);
        let params = self.track_params[ti];
        self.voice_age += 1;
        let age = self.voice_age;

        // Resolve to a single index before borrowing mutably — satisfies borrow checker.
        let idx = self.voices.iter().position(|v| !v.active).unwrap_or_else(|| {
            // Steal-oldest: find the index of the voice with the lowest age.
            self.voices
                .iter()
                .enumerate()
                .min_by_key(|(_, v)| v.age)
                .map(|(i, _)| i)
                .unwrap_or(0)
        });

        self.voices[idx].note_on(track_id, pitch, velocity, &params, age);
    }

    fn note_off(&mut self, track_id: u8, pitch: u8) {
        for voice in &mut self.voices {
            if voice.active && voice.track_id == track_id && voice.pitch == pitch {
                voice.note_off();
            }
        }
    }
}

/// Tanh soft-clipper: keeps output in (-1, 1) without hard-clipping.
#[inline]
fn soft_clip(x: f32) -> f32 {
    x.tanh()
}
