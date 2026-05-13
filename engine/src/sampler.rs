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
            // Reject samples that are too small for interpolation
            if data.len() < 2 {
                t.data = None;
                t.playing = false;
                return;
            }
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

        // Guard against empty or single-sample data
        if data.len() < 2 {
            t.playing = false;
            return;
        }

        // End position respects trim_end. We subtract 1 to ensure we never try to
        // interpolate at the last position (which would access data[len]).
        let end_pos = ((t.trim_end as f64) * data.len() as f64).ceil() as usize;
        let end_pos = end_pos.min(data.len()).saturating_sub(1);

        for f in 0..n {
            let pos = t.read_head as usize;
            
            // Stop if we've reached the end or if interpolation would go out of bounds
            if pos >= end_pos || pos + 1 >= data.len() {
                t.playing = false;
                break;
            }

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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_render_track_full_sample() {
        // Regression test: playing a sample with trim_end=1.0 should not panic
        let mut sampler = Sampler::new(44100.0);
        
        // Create a small test sample (10 samples at 1.0)
        let sample_data = vec![1.0; 10];
        sampler.set_sample(0, Arc::new(sample_data), 44100.0);
        
        // Trigger playback
        sampler.note_on(0, 60, 1.0);
        
        // Render without panicking
        let mut buf = vec![0.0; 256];
        sampler.render_track(0, &mut buf, 256);
        
        // Should have written some data
        assert!(buf.iter().any(|&x| x != 0.0));
    }

    #[test]
    fn test_render_track_with_trim_end() {
        let mut sampler = Sampler::new(44100.0);
        
        let sample_data = vec![1.0; 100];
        sampler.set_sample(0, Arc::new(sample_data), 44100.0);
        
        // Set trim_end to 0.5 (play first half)
        sampler.set_sample_param(0, SampleParam::TrimEnd, 0.5);
        
        sampler.note_on(0, 60, 1.0);
        
        let mut buf = vec![0.0; 256];
        sampler.render_track(0, &mut buf, 256);
        
        // Should have rendered without panic
        assert!(buf.iter().any(|&x| x != 0.0));
    }

    #[test]
    fn test_empty_sample_rejected() {
        let mut sampler = Sampler::new(44100.0);
        
        // Try to set an empty sample
        sampler.set_sample(0, Arc::new(vec![]), 44100.0);
        
        // Should not have a sample
        assert!(!sampler.has_sample(0));
    }

    #[test]
    fn test_single_element_sample_rejected() {
        let mut sampler = Sampler::new(44100.0);
        
        // Try to set a single-element sample
        sampler.set_sample(0, Arc::new(vec![1.0]), 44100.0);
        
        // Should not have a sample (needs at least 2 for interpolation)
        assert!(!sampler.has_sample(0));
    }

    #[test]
    fn test_two_element_sample_accepted() {
        let mut sampler = Sampler::new(44100.0);
        
        // Two elements should be accepted
        sampler.set_sample(0, Arc::new(vec![1.0, 1.0]), 44100.0);
        
        assert!(sampler.has_sample(0));
        
        // Should be able to play without panicking
        sampler.note_on(0, 60, 1.0);
        let mut buf = vec![0.0; 256];
        sampler.render_track(0, &mut buf, 256);
    }

    #[test]
    fn test_note_off_stops_playback() {
        let mut sampler = Sampler::new(44100.0);
        
        sampler.set_sample(0, Arc::new(vec![1.0; 100]), 44100.0);
        sampler.note_on(0, 60, 1.0);
        
        let mut buf = vec![0.0; 16];
        sampler.render_track(0, &mut buf, 16);
        let sum_playing = buf.iter().sum::<f32>();
        assert!(sum_playing > 0.0);
        
        // Stop playback
        sampler.note_off(0);
        
        buf.fill(0.0);
        sampler.render_track(0, &mut buf, 16);
        let sum_stopped = buf.iter().sum::<f32>();
        assert_eq!(sum_stopped, 0.0);
    }

    #[test]
    fn test_pitch_shifting() {
        let mut sampler = Sampler::new(44100.0);
        
        let sample_data = vec![1.0; 1000];
        sampler.set_sample(0, Arc::new(sample_data), 44100.0);
        
        // Play at base pitch (60)
        sampler.note_on(0, 60, 1.0);
        let mut buf1 = vec![0.0; 64];
        sampler.render_track(0, &mut buf1, 64);
        
        // Play an octave higher (72) - should play faster
        sampler.note_on(0, 72, 1.0);
        let mut buf2 = vec![0.0; 64];
        sampler.render_track(0, &mut buf2, 64);
        
        // Both should produce output
        assert!(buf1.iter().any(|&x| x != 0.0));
        assert!(buf2.iter().any(|&x| x != 0.0));
    }
}
