use crate::sequencer::NUM_TRACKS;
use crate::synth::filter::BiquadCoeffs;

/// Per-track effect parameters.
#[derive(Clone, Copy, Debug)]
pub struct TrackEffects {
    pub reverb_send:      f32, // 0..1
    pub delay_send:       f32, // 0..1
    pub delay_time_beats: f32, // fraction of a beat (0.25 = 16th note)
    pub delay_feedback:   f32, // 0..1
    pub dist_drive:       f32, // 0..1 — 0=off, 1=max drive
    pub filter_mode:      u8,  // 0=off, 1=low-pass, 2=high-pass
    pub filter_cutoff:    f32, // 0..1 normalised (20 Hz..20 kHz log)
    pub filter_resonance: f32, // 0..1 normalised (Q 0.5..20)
}

impl Default for TrackEffects {
    fn default() -> Self {
        Self {
            reverb_send: 0.0, delay_send: 0.0, delay_time_beats: 0.5,
            delay_feedback: 0.4, dist_drive: 0.0,
            filter_mode: 0, filter_cutoff: 0.5, filter_resonance: 0.0,
        }
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
    combs:     [CombFilter; 8],
    allpasses: [AllpassFilter; 4],
    pub room_size: f32,
    pub damping:   f32,
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
    buf:           Box<[f32; MAX_DELAY_SAMPLES]>,
    write:         usize,
    delay_samples: usize,
    feedback:      f32,
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
// Per-track filter state
// ---------------------------------------------------------------------------

#[derive(Clone, Copy)]
struct TrackFilter {
    coeffs: BiquadCoeffs,
    x1: f32, x2: f32, y1: f32, y2: f32,
}

impl TrackFilter {
    fn new() -> Self {
        Self { coeffs: BiquadCoeffs::default(), x1: 0.0, x2: 0.0, y1: 0.0, y2: 0.0 }
    }
    #[inline]
    fn tick(&mut self, x: f32) -> f32 {
        self.coeffs.tick(x, &mut self.x1, &mut self.x2, &mut self.y1, &mut self.y2)
    }
    fn reset(&mut self) {
        self.x1 = 0.0; self.x2 = 0.0; self.y1 = 0.0; self.y2 = 0.0;
    }
}

// ---------------------------------------------------------------------------
// Effects chain — one reverb + one delay shared across all tracks.
// Each track has per-track dist, filter, and send levels.
// ---------------------------------------------------------------------------

pub struct EffectsChain {
    pub track_fx:     [TrackEffects; NUM_TRACKS],
    pub reverb:       Reverb,
    delay:            Delay,
    track_filters:    [TrackFilter; NUM_TRACKS],
    sample_rate:      f64,
}

impl EffectsChain {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            track_fx:      std::array::from_fn(|_| TrackEffects::default()),
            reverb:        Reverb::new(),
            delay:         Delay::new(),
            track_filters: std::array::from_fn(|_| TrackFilter::new()),
            sample_rate,
        }
    }

    pub fn set_bpm(&mut self, bpm: f32, beats: f32) {
        let samples = (self.sample_rate * 60.0 / bpm as f64 * beats as f64) as usize;
        self.delay.set_time_samples(samples);
    }

    pub fn set_delay_feedback(&mut self, fb: f32) {
        self.delay.set_feedback(fb);
    }

    /// Recompute filter coefficients for a track after its params change.
    pub fn update_filter(&mut self, track_id: u8) {
        let t = track_id as usize;
        if t >= NUM_TRACKS { return; }
        let fx = &self.track_fx[t];
        let coeffs = match fx.filter_mode {
            1 => BiquadCoeffs::low_pass(fx.filter_cutoff, fx.filter_resonance, self.sample_rate),
            2 => BiquadCoeffs::high_pass(fx.filter_cutoff, fx.filter_resonance, self.sample_rate),
            _ => BiquadCoeffs::default(),
        };
        self.track_filters[t].coeffs = coeffs;
        self.track_filters[t].reset();
    }

    /// Process per-track mono buffers into the interleaved stereo output.
    ///
    /// Each track's dry signal is:
    ///   1. Soft-clipped with drive if dist_drive > 0
    ///   2. Filtered (LP or HP) if filter_mode != 0
    ///   3. Sent to reverb and delay buses via individual send levels
    ///
    /// Final output = sum(track dry) + reverb wet + delay wet, soft-clipped.
    pub fn process_tracks(
        &mut self,
        track_bufs: &[Vec<f32>],
        n_frames:   usize,
        channels:   usize,
        output:     &mut [f32],
    ) {
        for f in 0..n_frames {
            let mut dry_sum     = 0.0f32;
            let mut reverb_send = 0.0f32;
            let mut delay_send  = 0.0f32;

            for t in 0..NUM_TRACKS {
                let fx  = &self.track_fx[t];
                let raw = if f < track_bufs[t].len() { track_bufs[t][f] } else { 0.0 };

                // 1. Distortion
                let driven = if fx.dist_drive > 0.0 {
                    (raw * (1.0 + fx.dist_drive * 9.0)).tanh()
                } else {
                    raw
                };

                // 2. Per-track filter
                let filtered = if fx.filter_mode != 0 {
                    self.track_filters[t].tick(driven)
                } else {
                    driven
                };

                dry_sum     += filtered;
                reverb_send += filtered * fx.reverb_send;
                delay_send  += filtered * fx.delay_send;
            }

            let rev = self.reverb.tick(reverb_send);
            let del = self.delay.tick(delay_send);
            let out = soft_clip(dry_sum + rev + del);

            for ch in 0..channels {
                let i = f * channels + ch;
                if i < output.len() { output[i] = out; }
            }
        }
    }
}

#[inline]
fn soft_clip(x: f32) -> f32 { x.tanh() }
