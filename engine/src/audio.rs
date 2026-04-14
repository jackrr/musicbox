use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use std::sync::mpsc;

use crate::commands::{Command, EffectParam, FfiCommand};
use crate::effects::EffectsChain;
use crate::sampler::{SampleMsg, Sampler};
use crate::sequencer::{Sequencer, NUM_TRACKS};
use crate::synth::VoicePool;

pub const MAX_FRAMES: usize = 8192;

/// All real-time audio state. Owned by the audio callback closure.
struct AudioState {
    pool:        VoicePool,
    sampler:     Sampler,
    sequencer:   Sequencer,
    effects:     EffectsChain,
    channels:    usize,
    /// Pre-allocated per-track mono buffers (no heap alloc in hot path).
    track_bufs:  Vec<Vec<f32>>,
}

impl AudioState {
    fn new(sample_rate: f64, channels: usize) -> Self {
        Self {
            pool:       VoicePool::new(sample_rate),
            sampler:    Sampler::new(sample_rate),
            sequencer:  Sequencer::new(sample_rate),
            effects:    EffectsChain::new(sample_rate),
            channels,
            track_bufs: (0..NUM_TRACKS).map(|_| vec![0.0f32; MAX_FRAMES]).collect(),
        }
    }

    fn handle(&mut self, cmd: Command) {
        use Command::*;
        match cmd {
            NoteOn { track_id, pitch, velocity } => {
                if self.sampler.has_sample(track_id) {
                    self.sampler.note_on(track_id, pitch, velocity);
                } else {
                    self.pool.note_on(track_id, pitch, velocity);
                }
            }
            NoteOff { track_id, pitch } => {
                self.sampler.note_off(track_id);
                self.pool.note_off(track_id, pitch);
            }
            SetVoiceParam { track_id, param, value } => {
                self.pool.handle(SetVoiceParam { track_id, param, value });
            }
            SetBPM(bpm) => {
                self.sequencer.set_bpm(bpm);
                let beats = self.effects.track_fx[0].delay_time_beats;
                self.effects.set_bpm(bpm, beats);
            }
            SetTransport(state) => {
                if matches!(state, crate::commands::TransportState::Stop) {
                    self.sequencer.drain_notes(&mut self.pool, &mut self.sampler);
                }
                self.sequencer.set_transport(state);
            }
            SetStep { track_id, step_idx, pitch, velocity } => {
                self.sequencer.set_step(track_id, step_idx, pitch, velocity);
            }
            SetEffect { track_id, param, value } => {
                match param {
                    EffectParam::ReverbRoom => {
                        self.effects.reverb.set_room(value, self.effects.reverb.damping);
                    }
                    EffectParam::ReverbDamp => {
                        self.effects.reverb.set_room(self.effects.reverb.room_size, value);
                    }
                    _ => {
                        if let Some(fx) = self.effects.track_fx.get_mut(track_id as usize) {
                            match param {
                                EffectParam::ReverbSend    => fx.reverb_send      = value.clamp(0.0, 1.0),
                                EffectParam::DelaySend     => fx.delay_send       = value.clamp(0.0, 1.0),
                                EffectParam::DelayTime     => {
                                    fx.delay_time_beats = value.clamp(0.0625, 4.0);
                                    self.effects.set_bpm(self.sequencer.bpm(), value);
                                }
                                EffectParam::DelayFeedback => fx.delay_feedback   = value.clamp(0.0, 0.95),
                                EffectParam::DistDrive     => fx.dist_drive       = value.clamp(0.0, 1.0),
                                EffectParam::FilterType    => {
                                    fx.filter_mode = value as u8;
                                    self.effects.update_filter(track_id);
                                }
                                EffectParam::FilterCutoff  => {
                                    fx.filter_cutoff = value.clamp(0.0, 1.0);
                                    self.effects.update_filter(track_id);
                                }
                                EffectParam::FilterResonance => {
                                    fx.filter_resonance = value.clamp(0.0, 1.0);
                                    self.effects.update_filter(track_id);
                                }
                                // Already handled above
                                EffectParam::ReverbRoom | EffectParam::ReverbDamp => {}
                            }
                        }
                    }
                }
            }
            SetNumSteps(n) => self.sequencer.set_num_steps(n),
        }
    }

    fn process(
        &mut self,
        cmd_rx:    &mut rtrb::Consumer<FfiCommand>,
        sample_rx: &mut mpsc::Receiver<SampleMsg>,
        output:    &mut [f32],
        n_frames:  usize,
    ) {
        // 1. Drain commands (never allocates)
        while let Ok(raw) = cmd_rx.pop() {
            if let Some(cmd) = raw.decode() { self.handle(cmd); }
        }

        // 2. Install newly-loaded samples (rare, try_recv is lock-free in practice)
        while let Ok(msg) = sample_rx.try_recv() {
            self.sampler.set_sample(msg.track_id, msg.data, msg.source_rate);
        }

        // 3. Advance sequencer clock (fires NoteOn/Off into pool & sampler)
        self.sequencer.advance(n_frames, &mut self.pool, &mut self.sampler);

        // 4. Render each track into its own pre-allocated mono buffer
        let frames = n_frames.min(MAX_FRAMES);
        for t in 0..NUM_TRACKS {
            let buf = &mut self.track_bufs[t];
            buf[..frames].fill(0.0);
            self.pool.render_track(t as u8, &mut buf[..frames], frames);
            self.sampler.render_track(t as u8, &mut buf[..frames], frames);
        }

        // 5. Mix tracks through effects chain into output
        self.effects.process_tracks(&self.track_bufs, frames, self.channels, output);
    }
}

// ---------------------------------------------------------------------------

pub struct AudioStream {
    _stream: cpal::Stream,
}

impl AudioStream {
    pub fn new(
        cmd_rx:    rtrb::Consumer<FfiCommand>,
        sample_rx: mpsc::Receiver<SampleMsg>,
    ) -> Result<(Self, std::sync::Arc<std::sync::atomic::AtomicI32>), Box<dyn std::error::Error>> {
        let host    = cpal::default_host();
        let device  = host.default_output_device().ok_or("no audio output device")?;
        let sup     = device.default_output_config()?;
        let rate    = sup.sample_rate().0 as f64;
        let channels = sup.channels() as usize;

        let state    = AudioState::new(rate, channels);
        let playhead = std::sync::Arc::clone(&state.sequencer.playhead);

        let stream = match sup.sample_format() {
            cpal::SampleFormat::F32 => build_stream::<f32>(&device, &sup.into(), state, cmd_rx, sample_rx)?,
            cpal::SampleFormat::I16 => build_stream::<i16>(&device, &sup.into(), state, cmd_rx, sample_rx)?,
            cpal::SampleFormat::U16 => build_stream::<u16>(&device, &sup.into(), state, cmd_rx, sample_rx)?,
            fmt => return Err(format!("unsupported sample format: {fmt:?}").into()),
        };

        stream.play()?;
        Ok((Self { _stream: stream }, playhead))
    }
}

fn build_stream<T: cpal::SizedSample + cpal::FromSample<f32>>(
    device:    &cpal::Device,
    config:    &cpal::StreamConfig,
    mut state: AudioState,
    mut cmd_rx:    rtrb::Consumer<FfiCommand>,
    mut sample_rx: mpsc::Receiver<SampleMsg>,
) -> Result<cpal::Stream, Box<dyn std::error::Error>> {
    let channels = config.channels as usize;
    let mut f32_out = vec![0.0f32; MAX_FRAMES * channels];

    let stream = device.build_output_stream(
        config,
        move |output: &mut [T], _: &cpal::OutputCallbackInfo| {
            let n_frames = output.len() / channels;
            let f_buf    = &mut f32_out[..output.len()];
            f_buf.fill(0.0);
            state.process(&mut cmd_rx, &mut sample_rx, f_buf, n_frames);
            for (out, &s) in output.iter_mut().zip(f_buf.iter()) {
                *out = T::from_sample(s);
            }
        },
        |err| eprintln!("[musicbox] audio error: {err}"),
        None,
    )?;
    Ok(stream)
}
