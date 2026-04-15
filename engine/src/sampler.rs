use std::sync::Arc;
use crate::commands::SampleParam;
use crate::sequencer::NUM_TRACKS;

/// Message sent from the FFI thread to the audio thread carrying decoded sample data.
pub struct SampleMsg {
    pub track_id:    u8,
    pub data:        Arc<Vec<f32>>, // mono, native float
    pub source_rate: f32,
}

// ---------------------------------------------------------------------------

struct SampleTrack {
    data:         Option<Arc<Vec<f32>>>,
    source_rate:  f32,
    read_head:    f64,
    rate_ratio:   f64, // combined pitch × playback_rate × (source_rate / device_rate)
    playing:      bool,
    // --- editable params ---
    base_pitch:   u8,  // root note; pitch offset is relative to this
    trim_start:   f32, // 0..1 normalised start position in sample
    trim_end:     f32, // 0..1 normalised end position (1.0 = full length)
    playback_rate: f32, // speed multiplier 0.25..4.0 (pitch-independent)
}

impl SampleTrack {
    fn new() -> Self {
        Self {
            data: None, source_rate: 44100.0, read_head: 0.0,
            rate_ratio: 1.0, playing: false,
            base_pitch: 60, trim_start: 0.0, trim_end: 1.0, playback_rate: 1.0,
        }
    }
}

pub struct Sampler {
    tracks: [SampleTrack; NUM_TRACKS],
    device_rate: f64,
}

impl Sampler {
    pub fn new(device_rate: f64) -> Self {
        Self {
            tracks: std::array::from_fn(|_| SampleTrack::new()),
            device_rate,
        }
    }

    pub fn set_sample(&mut self, track_id: u8, data: Arc<Vec<f32>>, source_rate: f32) {
        if let Some(t) = self.tracks.get_mut(track_id as usize) {
            t.source_rate = source_rate;
            t.data = Some(data);
            t.playing = false;
        }
    }

    pub fn has_sample(&self, track_id: u8) -> bool {
        self.tracks.get(track_id as usize).map(|t| t.data.is_some()).unwrap_or(false)
    }

    pub fn note_on(&mut self, track_id: u8, pitch: u8, _velocity: f32) {
        if let Some(t) = self.tracks.get_mut(track_id as usize) {
            if let Some(data) = &t.data {
                let pitch_ratio = 2.0_f64.powf((pitch as f64 - t.base_pitch as f64) / 12.0);
                t.rate_ratio = pitch_ratio * t.playback_rate as f64
                    * t.source_rate as f64 / self.device_rate;
                // Seek to trim start
                t.read_head = (t.trim_start as f64 * data.len() as f64).floor();
                t.playing = true;
            }
        }
    }

    pub fn note_off(&mut self, track_id: u8) {
        if let Some(t) = self.tracks.get_mut(track_id as usize) {
            t.playing = false;
        }
    }

    /// Accumulate one track's sampler output into `buf` (mono, pre-zeroed by caller).
    pub fn render_track(&mut self, track_id: u8, buf: &mut [f32], n: usize) {
        let t = match self.tracks.get_mut(track_id as usize) {
            Some(t) => t,
            None => return,
        };
        if !t.playing { return; }
        let data = match &t.data { Some(d) => Arc::clone(d), None => return };

        // End position respects trim_end
        let end_pos = ((t.trim_end as f64) * data.len() as f64).ceil() as usize;
        let end_pos = end_pos.min(data.len());

        for f in 0..n {
            let pos = t.read_head as usize;
            if pos + 1 >= end_pos { t.playing = false; break; }

            // Linear interpolation
            let frac   = t.read_head.fract() as f32;
            let sample = data[pos] * (1.0 - frac) + data[pos + 1] * frac;
            if f < buf.len() { buf[f] += sample * 0.6; }
            t.read_head += t.rate_ratio;
        }
    }

    /// Update a sample parameter (trim, root note, playback rate).
    pub fn set_sample_param(&mut self, track_id: u8, param: SampleParam, value: f32) {
        if let Some(t) = self.tracks.get_mut(track_id as usize) {
            match param {
                SampleParam::TrimStart    => t.trim_start    = value.clamp(0.0, 0.99),
                SampleParam::TrimEnd      => t.trim_end      = value.clamp(0.01, 1.0),
                SampleParam::BasePitch    => t.base_pitch    = value.clamp(0.0, 127.0) as u8,
                SampleParam::PlaybackRate => t.playback_rate = value.clamp(0.25, 4.0),
            }
        }
    }
}

// ---------------------------------------------------------------------------
// WAV loading helper (called from FFI thread, not audio thread)
// ---------------------------------------------------------------------------

pub fn load_wav(path: &str) -> Result<(Vec<f32>, u32), Box<dyn std::error::Error + Send + Sync>> {
    let mut reader = hound::WavReader::open(path)?;
    let spec = reader.spec();

    let raw: Vec<f32> = match spec.sample_format {
        hound::SampleFormat::Float => {
            reader.samples::<f32>().collect::<Result<_, _>>()?
        }
        hound::SampleFormat::Int => {
            let scale = 1.0 / (1i64 << (spec.bits_per_sample - 1)) as f32;
            match spec.bits_per_sample {
                8  => reader.samples::<i8>() .map(|s| s.map(|v| v as f32 * scale)).collect::<Result<_,_>>()?,
                16 => reader.samples::<i16>().map(|s| s.map(|v| v as f32 * scale)).collect::<Result<_,_>>()?,
                24 | 32 => reader.samples::<i32>().map(|s| s.map(|v| v as f32 * scale)).collect::<Result<_,_>>()?,
                _ => return Err("unsupported bit depth".into()),
            }
        }
    };

    // Down-mix to mono
    let channels = spec.channels as usize;
    let mono: Vec<f32> = if channels > 1 {
        raw.chunks(channels)
           .map(|ch| ch.iter().sum::<f32>() / ch.len() as f32)
           .collect()
    } else {
        raw
    };

    Ok((mono, spec.sample_rate))
}
