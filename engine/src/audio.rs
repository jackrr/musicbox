use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};

use crate::commands::FfiCommand;
use crate::synth::VoicePool;

/// Maximum frames per callback × channels.
/// Pre-allocated once; no heap use inside the audio callback.
const MAX_OUTPUT_SAMPLES: usize = 8192 * 2;

/// Wraps a live cpal output stream. Dropping stops audio.
pub struct AudioStream {
    _stream: cpal::Stream,
}

impl AudioStream {
    pub fn new(command_rx: rtrb::Consumer<FfiCommand>) -> Result<Self, Box<dyn std::error::Error>> {
        let host   = cpal::default_host();
        let device = host
            .default_output_device()
            .ok_or("no default audio output device")?;

        let supported = device.default_output_config()?;
        let sample_rate = supported.sample_rate().0 as f64;
        let channels    = supported.channels() as usize;

        let voice_pool = VoicePool::new(sample_rate);

        let stream = match supported.sample_format() {
            cpal::SampleFormat::F32 => {
                build_stream::<f32>(&device, &supported.into(), channels, voice_pool, command_rx)?
            }
            cpal::SampleFormat::I16 => {
                build_stream::<i16>(&device, &supported.into(), channels, voice_pool, command_rx)?
            }
            cpal::SampleFormat::U16 => {
                build_stream::<u16>(&device, &supported.into(), channels, voice_pool, command_rx)?
            }
            fmt => return Err(format!("unsupported sample format: {fmt:?}").into()),
        };

        stream.play()?;
        Ok(Self { _stream: stream })
    }
}

fn build_stream<T>(
    device: &cpal::Device,
    config: &cpal::StreamConfig,
    channels: usize,
    mut voice_pool: VoicePool,
    mut command_rx: rtrb::Consumer<FfiCommand>,
) -> Result<cpal::Stream, Box<dyn std::error::Error>>
where
    T: cpal::SizedSample + cpal::FromSample<f32>,
{
    // Pre-allocate f32 output buffer — reused every callback, zero heap in hot path.
    let mut f32_buf = vec![0.0f32; MAX_OUTPUT_SAMPLES];

    let stream = device.build_output_stream(
        config,
        move |output: &mut [T], _: &cpal::OutputCallbackInfo| {
            let n_frames = output.len() / channels;

            // Drain pending commands (rtrb pop never allocates).
            while let Ok(cmd) = command_rx.pop() {
                if let Some(decoded) = cmd.decode() {
                    voice_pool.handle(decoded);
                }
            }

            // Render voices → f32_buf, then convert to device sample type.
            let buf = &mut f32_buf[..output.len()];
            buf.fill(0.0);
            voice_pool.render(buf, n_frames, channels);

            for (out, &s) in output.iter_mut().zip(buf.iter()) {
                *out = T::from_sample(s);
            }
        },
        |err| eprintln!("[musicbox] audio error: {err}"),
        None,
    )?;

    Ok(stream)
}
