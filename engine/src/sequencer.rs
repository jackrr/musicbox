use std::sync::{Arc, atomic::{AtomicI32, Ordering}};
use crate::synth::VoicePool;
use crate::sampler::Sampler;
use crate::commands::TransportState;

pub const NUM_TRACKS: usize = 8;
pub const MAX_STEPS: usize = 64;

#[derive(Clone, Copy, Default, Debug)]
pub struct Step {
    pub active:   bool,
    pub pitch:    u8,
    pub velocity: u8, // 0..127
}

pub struct Sequencer {
    playing:      bool,
    pos_samples:  f64,
    step_samples: f64,
    bpm:          f32,
    num_steps:    usize,
    sample_rate:  f64,
    pub patterns: Box<[[Step; MAX_STEPS]; NUM_TRACKS]>,
    active_notes: [Option<u8>; NUM_TRACKS],
    prev_step:    usize,
    pub playhead: Arc<AtomicI32>, // -1 stopped, else 0..num_steps-1
}

impl Sequencer {
    pub fn new(sample_rate: f64) -> Self {
        let bpm = 120.0f32;
        let num_steps = 16;
        Self {
            playing: false,
            pos_samples: 0.0,
            step_samples: step_duration(sample_rate, bpm),
            bpm,
            num_steps,
            sample_rate,
            patterns: Box::new([[Step::default(); MAX_STEPS]; NUM_TRACKS]),
            active_notes: [None; NUM_TRACKS],
            prev_step: usize::MAX,
            playhead: Arc::new(AtomicI32::new(-1)),
        }
    }

    pub fn bpm(&self) -> f32 { self.bpm }
    pub fn num_steps(&self) -> usize { self.num_steps }

    pub fn set_bpm(&mut self, bpm: f32) {
        self.bpm = bpm.clamp(20.0, 300.0);
        self.step_samples = step_duration(self.sample_rate, self.bpm);
    }

    pub fn set_num_steps(&mut self, n: usize) {
        self.num_steps = n.clamp(1, MAX_STEPS);
    }

    pub fn set_transport(&mut self, state: TransportState) {
        match state {
            TransportState::Play  => { self.playing = true; }
            TransportState::Stop  => {
                self.playing = false;
                self.playhead.store(-1, Ordering::Relaxed);
            }
            TransportState::Reset => {
                self.pos_samples = 0.0;
                self.prev_step   = usize::MAX;
                if !self.playing { self.playhead.store(-1, Ordering::Relaxed); }
            }
        }
    }

    pub fn set_step(&mut self, track_id: u8, step_idx: u8, pitch: u8, velocity: f32) {
        let (ti, si) = (track_id as usize, step_idx as usize);
        if ti < NUM_TRACKS && si < MAX_STEPS {
            if velocity <= 0.0 {
                self.patterns[ti][si].active = false;
            } else {
                self.patterns[ti][si] = Step {
                    active: true, pitch,
                    velocity: (velocity * 127.0).clamp(0.0, 127.0) as u8,
                };
            }
        }
    }

    /// Advance clock by `n_frames`, firing NoteOn/Off into the voice pool and sampler.
    pub fn advance(&mut self, n_frames: usize, pool: &mut VoicePool, sampler: &mut Sampler) {
        if !self.playing { return; }

        let end_pos  = self.pos_samples + n_frames as f64;
        let new_step = (end_pos / self.step_samples) as usize % self.num_steps;

        if new_step != self.prev_step {
            // Gate-off previous notes
            for track_id in 0..NUM_TRACKS {
                if let Some(pitch) = self.active_notes[track_id].take() {
                    if sampler.has_sample(track_id as u8) {
                        sampler.note_off(track_id as u8);
                    } else {
                        pool.note_off(track_id as u8, pitch);
                    }
                }
            }

            // NoteOn for active steps
            for track_id in 0..NUM_TRACKS {
                let step = self.patterns[track_id][new_step];
                if step.active {
                    let vel = step.velocity as f32 / 127.0;
                    if sampler.has_sample(track_id as u8) {
                        sampler.note_on(track_id as u8, step.pitch, vel);
                    } else {
                        pool.note_on(track_id as u8, step.pitch, vel);
                    }
                    self.active_notes[track_id] = Some(step.pitch);
                }
            }

            self.playhead.store(new_step as i32, Ordering::Relaxed);
            self.prev_step = new_step;
        }

        self.pos_samples = end_pos;
    }
}

/// Duration of one 16th-note step in samples.
pub fn step_duration(sample_rate: f64, bpm: f32) -> f64 {
    sample_rate * 60.0 / (bpm as f64 * 4.0)
}
