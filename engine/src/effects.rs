use crate::sequencer::NUM_TRACKS;

/// Per-track effect parameters.
#[derive(Clone, Copy, Debug)]
pub struct TrackEffects {
    pub reverb_send:      f32, // 0..1
    pub delay_send:       f32, // 0..1
    pub delay_time_beats: f32, // fraction of a beat (0.25 = 16th note)
    pub delay_feedback:   f32, // 0..1
    pub dist_drive:       f32, // 0..1
}

impl Default for TrackEffects {
    fn default() -> Self {
        Self { reverb_send: 0.0, delay_send: 0.0, delay_time_beats: 0.5,
               delay_feedback: 0.4, dist_drive: 0.0 }
    }
}

// ---------------------------------------------------------------------------
// Freeverb-style reverb (simplified single-channel version)
// ---------------------------------------------------------------------------

const COMB_SIZES: [usize; 8] = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617];
const ALLPASS_SIZES: [usize; 4] = [556, 441, 341, 225];

struct CombFilter { buf: Vec<f32>, idx: usize, feedback: f32, damp1: f32, damp2: f32, filt: f32 }
struct AllpassFilter { buf: Vec<f32>, idx: usize }

impl CombFilter {
    fn new(size: usize) -> Self {
        Self { buf: vec![0.0; size], idx: 0, feedback: 0.84, damp1: 0.2, damp2: 0.8, filt: 0.0 }
    }
    fn set_params(&mut self, room: f32, damp: f32) {
        self.feedback = 0.7 + room * 0.28;
        self.damp1    = damp * 0.4;
        self.damp2    = 1.0 - self.damp1;
    }
    #[inline]
    fn tick(&mut self, input: f32) -> f32 {
        let out = self.buf[self.idx];
        self.filt = out * self.damp2 + self.filt * self.damp1;
        self.buf[self.idx] = input + self.filt * self.feedback;
        self.idx = (self.idx + 1) % self.buf.len();
        out
    }
}

impl AllpassFilter {
    fn new(size: usize) -> Self { Self { buf: vec![0.0; size], idx: 0 } }
    #[inline]
    fn tick(&mut self, input: f32) -> f32 {
        let buf_out = self.buf[self.idx];
        let output  = -input + buf_out;
        self.buf[self.idx] = input + buf_out * 0.5;
        self.idx = (self.idx + 1) % self.buf.len();
        output
    }
}

pub struct Reverb {
    combs:    [CombFilter; 8],
    allpasses: [AllpassFilter; 4],
    room_size: f32,
    damping:   f32,
}

impl Reverb {
    pub fn new() -> Self {
        let mut r = Self {
            combs: COMB_SIZES.map(CombFilter::new),
            allpasses: ALLPASS_SIZES.map(AllpassFilter::new),
            room_size: 0.5,
            damping:   0.5,
        };
        r.update_params();
        r
    }

    pub fn set_room(&mut self, room: f32, damp: f32) {
        self.room_size = room.clamp(0.0, 1.0);
        self.damping   = damp.clamp(0.0, 1.0);
        self.update_params();
    }

    fn update_params(&mut self) {
        for c in &mut self.combs { c.set_params(self.room_size, self.damping); }
    }

    /// Process one sample of mono reverb.
    #[inline]
    pub fn tick(&mut self, input: f32) -> f32 {
        let scaled = input * 0.015;
        let mut out = 0.0f32;
        for c in &mut self.combs { out += c.tick(scaled); }
        for a in &mut self.allpasses { out = a.tick(out); }
        out
    }
}

// ---------------------------------------------------------------------------
// Tempo-synced feedback delay (mono)
// ---------------------------------------------------------------------------

const MAX_DELAY_SAMPLES: usize = 96000; // 2 s at 48 kHz

pub struct Delay {
    buf:      Box<[f32; MAX_DELAY_SAMPLES]>,
    write:    usize,
    delay_samples: usize,
    feedback: f32,
}

impl Delay {
    pub fn new() -> Self {
        Self {
            buf: Box::new([0.0; MAX_DELAY_SAMPLES]),
            write: 0,
            delay_samples: 22050, // ~500 ms default
            feedback: 0.4,
        }
    }

    pub fn set_time_samples(&mut self, samples: usize) {
        self.delay_samples = samples.min(MAX_DELAY_SAMPLES - 1).max(1);
    }

    pub fn set_feedback(&mut self, fb: f32) { self.feedback = fb.clamp(0.0, 0.95); }

    #[inline]
    pub fn tick(&mut self, input: f32) -> f32 {
        let read = (self.write + MAX_DELAY_SAMPLES - self.delay_samples) % MAX_DELAY_SAMPLES;
        let out  = self.buf[read];
        self.buf[self.write] = input + out * self.feedback;
        self.write = (self.write + 1) % MAX_DELAY_SAMPLES;
        out
    }
}

// ---------------------------------------------------------------------------
// Effects chain — one reverb + one delay shared across all tracks.
// Tracks send to reverb/delay via send levels.
// ---------------------------------------------------------------------------

pub struct EffectsChain {
    pub track_fx: [TrackEffects; NUM_TRACKS],
    reverb: Reverb,
    delay:  Delay,
    sample_rate: f64,
}

impl EffectsChain {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            track_fx: std::array::from_fn(|_| TrackEffects::default()),
            reverb: Reverb::new(),
            delay:  Delay::new(),
            sample_rate,
        }
    }

    pub fn set_bpm(&mut self, bpm: f32, beats: f32) {
        let samples = (self.sample_rate * 60.0 / bpm as f64 * beats as f64) as usize;
        self.delay.set_time_samples(samples);
    }

    /// Process the interleaved stereo output buffer in place.
    /// For each frame, accumulate reverb and delay sends from track dry signals
    /// (approximated from the mixed output — a send-style effect).
    pub fn process(&mut self, output: &mut [f32], n_frames: usize, channels: usize,
                   track_sends: &[(f32, f32, f32)]) // (reverb_send, delay_send, dist_drive) per track
    {
        // We apply effects to the stereo mix. For a more accurate send model,
        // you'd need per-track dry buffers, which we'll add in a future pass.
        // For now: one reverb and one delay on the master bus.

        // Compute average sends across all active tracks
        let mut rev_sum = 0.0f32;
        let mut del_sum = 0.0f32;
        for (r, d, _) in track_sends.iter() { rev_sum += r; del_sum += d; }
        let n = track_sends.len().max(1) as f32;
        let rev_wet = (rev_sum / n).min(1.0);
        let del_wet = (del_sum / n).min(1.0);

        for f in 0..n_frames {
            let mono = if channels == 1 {
                output[f]
            } else {
                (output[f * channels] + output[f * channels + 1]) * 0.5
            };

            let rev = self.reverb.tick(mono) * rev_wet;
            let del = self.delay.tick(mono)  * del_wet;

            for ch in 0..channels {
                let i = f * channels + ch;
                if i < output.len() {
                    output[i] = soft_clip(output[i] + rev + del);
                }
            }
        }
    }
}

#[inline]
fn soft_clip(x: f32) -> f32 { x.tanh() }
