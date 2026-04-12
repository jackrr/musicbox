use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc,
};

/// Wraps a live cpal output stream.
///
/// Dropping this struct stops and releases the audio stream.
pub struct AudioStream {
    _stream: cpal::Stream,
}

impl AudioStream {
    pub fn new(is_playing: Arc<AtomicBool>) -> Result<Self, Box<dyn std::error::Error>> {
        let host = cpal::default_host();

        let device = host
            .default_output_device()
            .ok_or("no default audio output device found")?;

        let supported = device.default_output_config()?;
        let sample_rate = supported.sample_rate().0 as f64;
        let channels = supported.channels() as usize;

        let stream = match supported.sample_format() {
            cpal::SampleFormat::F32 => {
                build_stream::<f32>(&device, &supported.into(), sample_rate, channels, is_playing)?
            }
            cpal::SampleFormat::I16 => {
                build_stream::<i16>(&device, &supported.into(), sample_rate, channels, is_playing)?
            }
            cpal::SampleFormat::U16 => {
                build_stream::<u16>(&device, &supported.into(), sample_rate, channels, is_playing)?
            }
            fmt => return Err(format!("unsupported sample format: {fmt:?}").into()),
        };

        stream.play()?;

        Ok(Self { _stream: stream })
    }
}

/// Build a typed output stream that renders a 440 Hz sine wave when playing.
fn build_stream<T>(
    device: &cpal::Device,
    config: &cpal::StreamConfig,
    sample_rate: f64,
    channels: usize,
    is_playing: Arc<AtomicBool>,
) -> Result<cpal::Stream, Box<dyn std::error::Error>>
where
    T: cpal::SizedSample + cpal::FromSample<f32>,
{
    // Phase accumulator for the test tone (440 Hz).
    let mut phase: f64 = 0.0;
    let phase_inc = 440.0 / sample_rate;

    let stream = device.build_output_stream(
        config,
        move |output: &mut [T], _info: &cpal::OutputCallbackInfo| {
            for frame in output.chunks_mut(channels) {
                let sample: f32 = if is_playing.load(Ordering::Relaxed) {
                    let s = (phase * std::f64::consts::TAU).sin() as f32 * 0.25;
                    phase = (phase + phase_inc).fract();
                    s
                } else {
                    0.0
                };
                let value = T::from_sample(sample);
                for out in frame.iter_mut() {
                    *out = value;
                }
            }
        },
        |err| eprintln!("[musicbox] stream error: {err}"),
        None, // no timeout
    )?;

    Ok(stream)
}
