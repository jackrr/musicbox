use crate::sequencer::{Sequencer, Step, NUM_TRACKS, MAX_STEPS};
use crate::synth::{VoicePool, voice::TrackParams};
use crate::sampler::Sampler;

const EXPORT_RATE: f64 = 44100.0;
const CHUNK: usize = 512;

/// Snapshot of engine state needed to reproduce a mix offline.
pub struct ExportState {
    pub bpm:          f32,
    pub num_steps:    usize,
    pub patterns:     Box<[[Step; MAX_STEPS]; NUM_TRACKS]>,
    pub track_params: [TrackParams; NUM_TRACKS],
}

/// Render `bars` bars of audio to a 16-bit stereo WAV file.
pub fn render_wav(
    path: &str,
    bars: u32,
    state: &ExportState,
    progress: &std::sync::atomic::AtomicU32, // 0..=100
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    use std::sync::atomic::Ordering;

    let total_steps   = bars as usize * state.num_steps;
    let step_samples  = EXPORT_RATE * 60.0 / (state.bpm as f64 * 4.0);
    let total_samples = (total_steps as f64 * step_samples).ceil() as usize;

    let mut pool      = VoicePool::new(EXPORT_RATE);
    let mut sampler   = Sampler::new(EXPORT_RATE);
    let mut seq       = Sequencer::new(EXPORT_RATE);

    // Restore state
    seq.set_bpm(state.bpm);
    seq.set_num_steps(state.num_steps);
    *seq.patterns = *state.patterns.clone();
    seq.set_transport(crate::commands::TransportState::Play);

    for (ti, tp) in state.track_params.iter().enumerate() {
        use crate::commands::VoiceParam::*;
        for (p, v) in [
            (OscType,   tp.osc_type as u8 as f32),
            (Attack,    tp.attack),
            (Decay,     tp.decay),
            (Sustain,   tp.sustain),
            (Release,   tp.release),
            (Cutoff,    tp.cutoff),
            (Resonance, tp.resonance),
            (Volume,    tp.volume),
        ] {
            pool.handle(crate::commands::Command::SetVoiceParam {
                track_id: ti as u8, param: p, value: v,
            });
        }
    }

    let spec = hound::WavSpec {
        channels: 2, sample_rate: EXPORT_RATE as u32,
        bits_per_sample: 16, sample_format: hound::SampleFormat::Int,
    };
    let mut writer = hound::WavWriter::create(path, spec)?;
    let mut buf    = vec![0.0f32; CHUNK * 2];

    let mut rendered = 0usize;
    while rendered < total_samples {
        let n = CHUNK.min(total_samples - rendered);
        buf[..n * 2].fill(0.0);
        seq.advance(n, &mut pool, &mut sampler);
        pool.render(&mut buf[..n * 2], n, 2);
        sampler.render(&mut buf[..n * 2], n, 2);

        for &s in &buf[..n * 2] {
            writer.write_sample((s.clamp(-1.0, 1.0) * i16::MAX as f32) as i16)?;
        }

        rendered += n;
        let pct = (rendered as u64 * 100 / total_samples as u64) as u32;
        progress.store(pct, Ordering::Relaxed);
    }

    writer.finalize()?;
    Ok(())
}
