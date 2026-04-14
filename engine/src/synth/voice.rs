use crate::commands::VoiceParam;

// ---------------------------------------------------------------------------
// Per-track parameters (snapshot taken at NoteOn time)
// ---------------------------------------------------------------------------

#[derive(Clone, Copy, Debug)]
pub struct TrackParams {
    pub osc_type: OscType,
    pub attack:   f32, // seconds
    pub decay:    f32, // seconds
    pub sustain:  f32, // 0..1
    pub release:  f32, // seconds
    pub volume:   f32, // 0..1
}

impl Default for TrackParams {
    fn default() -> Self {
        Self {
            osc_type: OscType::Sine,
            attack:   0.01,
            decay:    0.15,
            sustain:  0.7,
            release:  0.4,
            volume:   0.75,
        }
    }
}

impl TrackParams {
    pub fn apply(&mut self, param: VoiceParam, value: f32) {
        match param {
            VoiceParam::OscType => self.osc_type = OscType::from_f32(value),
            VoiceParam::Attack  => self.attack    = value.max(0.001),
            VoiceParam::Decay   => self.decay     = value.max(0.001),
            VoiceParam::Sustain => self.sustain   = value.clamp(0.0, 1.0),
            VoiceParam::Release => self.release   = value.max(0.001),
            VoiceParam::Volume  => self.volume    = value.clamp(0.0, 1.0),
        }
    }
}

// ---------------------------------------------------------------------------
// Oscillator type
// ---------------------------------------------------------------------------

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum OscType { #[default] Sine, Saw, Square, Triangle, Noise }

impl OscType {
    pub fn from_f32(v: f32) -> Self {
        match v as u8 {
            0 => Self::Sine,
            1 => Self::Saw,
            2 => Self::Square,
            3 => Self::Triangle,
            _ => Self::Noise,
        }
    }
}

// ---------------------------------------------------------------------------
// ADSR envelope
// ---------------------------------------------------------------------------

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Stage { Idle, Attack, Decay, Sustain, Release }

// ---------------------------------------------------------------------------
// Voice
// ---------------------------------------------------------------------------

pub struct Voice {
    // Identity
    pub active:   bool,
    pub track_id: u8,
    pub pitch:    u8,
    pub age:      u64, // monotonically increasing — used for steal-oldest

    // Oscillator
    osc_type: OscType,
    phase:    f64,  // 0..1
    freq:     f64,  // Hz

    // XorShift32 noise RNG (per-voice, so steals don't share state)
    rng: u32,

    // ADSR
    stage:       Stage,
    env_level:   f32,  // current amplitude 0..1
    env_time:    f64,  // seconds elapsed in current stage
    attack:      f32,
    decay:       f32,
    sustain:     f32,
    release:     f32,
    release_lvl: f32,  // level at which release began

    volume:      f32,
    sample_rate: f64,
}

impl Voice {
    pub fn new(sample_rate: f64) -> Self {
        Self {
            active: false, track_id: 0, pitch: 60, age: 0,
            osc_type: OscType::Sine, phase: 0.0, freq: 440.0,
            rng: 0x12345678,
            stage: Stage::Idle, env_level: 0.0, env_time: 0.0,
            attack: 0.01, decay: 0.15, sustain: 0.7, release: 0.4,
            release_lvl: 0.0,
            volume: 0.75,
            sample_rate,
        }
    }

    pub fn note_on(&mut self, track_id: u8, pitch: u8, velocity: f32, params: &TrackParams, age: u64) {
        self.active    = true;
        self.track_id  = track_id;
        self.pitch     = pitch;
        self.age       = age;
        self.osc_type  = params.osc_type;
        self.freq      = midi_to_hz(pitch);
        self.phase     = 0.0;
        // Seed noise RNG uniquely per pitch so consecutive notes differ
        self.rng       = 0x12345678u32.wrapping_add(pitch as u32 * 1_234_567_891);

        self.attack    = params.attack;
        self.decay     = params.decay;
        self.sustain   = params.sustain;
        self.release   = params.release;
        // Scale volume by velocity
        self.volume    = params.volume * velocity;

        self.stage     = Stage::Attack;
        self.env_time  = 0.0;
        self.env_level = 0.0;
    }

    pub fn note_off(&mut self) {
        if self.stage != Stage::Idle {
            self.release_lvl = self.env_level;
            self.stage       = Stage::Release;
            self.env_time    = 0.0;
        }
    }

    /// Accumulate `n` rendered samples into `buf` (mono, pre-zeroed by caller).
    ///
    /// Returns `false` when the voice has fully decayed and can be freed.
    pub fn render(&mut self, buf: &mut [f32], n: usize) -> bool {
        let dt        = 1.0 / self.sample_rate;
        let phase_inc = self.freq / self.sample_rate;

        for s in buf[..n].iter_mut() {
            let env = self.tick_env(dt);
            let osc = self.tick_osc();
            *s += osc * env * self.volume;
            self.phase = (self.phase + phase_inc).fract();
        }

        self.active = self.stage != Stage::Idle;
        self.active
    }

    // --- private helpers ---

    #[inline]
    fn tick_env(&mut self, dt: f64) -> f32 {
        match self.stage {
            Stage::Idle => 0.0,

            Stage::Attack => {
                self.env_time += dt;
                let t = (self.env_time / self.attack as f64) as f32;
                if t >= 1.0 {
                    self.env_level = 1.0;
                    self.stage     = Stage::Decay;
                    self.env_time  = 0.0;
                    1.0
                } else {
                    self.env_level = t;
                    t
                }
            }

            Stage::Decay => {
                self.env_time += dt;
                let t = (self.env_time / self.decay as f64) as f32;
                if t >= 1.0 {
                    self.env_level = self.sustain;
                    self.stage     = Stage::Sustain;
                    self.sustain
                } else {
                    let l = 1.0 - t * (1.0 - self.sustain);
                    self.env_level = l;
                    l
                }
            }

            Stage::Sustain => self.sustain,

            Stage::Release => {
                self.env_time += dt;
                let t = (self.env_time / self.release as f64) as f32;
                if t >= 1.0 {
                    self.env_level = 0.0;
                    self.stage     = Stage::Idle;
                    0.0
                } else {
                    let l = self.release_lvl * (1.0 - t);
                    self.env_level = l;
                    l
                }
            }
        }
    }

    #[inline]
    fn tick_osc(&mut self) -> f32 {
        let p = self.phase;
        match self.osc_type {
            OscType::Sine     => (p * std::f64::consts::TAU).sin() as f32,
            OscType::Saw      => (2.0 * p - 1.0) as f32,
            OscType::Square   => if p < 0.5 { 1.0 } else { -1.0 },
            OscType::Triangle => {
                let q = p * 4.0;
                (if q < 1.0 { q } else if q < 3.0 { 2.0 - q } else { q - 4.0 }) as f32
            }
            OscType::Noise => {
                // XorShift32
                self.rng ^= self.rng << 13;
                self.rng ^= self.rng >> 17;
                self.rng ^= self.rng << 5;
                (self.rng as f32 / u32::MAX as f32) * 2.0 - 1.0
            }
        }
    }
}

#[inline]
fn midi_to_hz(pitch: u8) -> f64 {
    440.0 * 2.0_f64.powf((pitch as f64 - 69.0) / 12.0)
}
