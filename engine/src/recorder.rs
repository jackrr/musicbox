use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use std::sync::{Arc, Mutex};

// Cap recording at 60 s of mono audio to prevent unlimited memory growth.
const MAX_RECORD_SAMPLES: usize = 60 * 48_000;

pub struct Recorder {
    _stream:     cpal::Stream,
    buf:         Arc<Mutex<Vec<f32>>>,
    sample_rate: u32,
}

impl Recorder {
    /// Open the default input device and start recording.
    /// Returns `None` if no input device is available or the stream cannot start.
    pub fn start() -> Option<Self> {
        let host   = cpal::default_host();
        let device = host.default_input_device()?;
        let config = device.default_input_config().ok()?;
        let sample_rate = config.sample_rate().0;
        let channels = config.channels() as usize;

        let buf: Arc<Mutex<Vec<f32>>> = Arc::new(Mutex::new(Vec::new()));
        let buf_cb = Arc::clone(&buf);

        let stream = match config.sample_format() {
            cpal::SampleFormat::F32 => {
                let buf_f = buf_cb;
                device.build_input_stream(
                    &config.into(),
                    move |data: &[f32], _| record_mono(data, channels, &buf_f),
                    |e| eprintln!("[musicbox] input error: {e}"),
                    None,
                ).ok()?
            }
            cpal::SampleFormat::I16 => {
                device.build_input_stream(
                    &config.into(),
                    move |data: &[i16], _| {
                        let f32_data: Vec<f32> = data.iter()
                            .map(|&s| s as f32 / i16::MAX as f32)
                            .collect();
                        record_mono(&f32_data, channels, &buf_cb);
                    },
                    |e| eprintln!("[musicbox] input error: {e}"),
                    None,
                ).ok()?
            }
            _ => {
                // Fall back: treat all other formats as f32
                let buf_f = buf_cb;
                device.build_input_stream(
                    &config.into(),
                    move |data: &[f32], _| record_mono(data, channels, &buf_f),
                    |e| eprintln!("[musicbox] input error: {e}"),
                    None,
                ).ok()?
            }
        };

        stream.play().ok()?;
        Some(Self { _stream: stream, buf, sample_rate })
    }

    /// Stop recording and save to a WAV file at `path`.
    pub fn stop_and_save(self, path: &str) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        // Dropping self._stream stops the input callback.
        drop(self._stream);

        let data = self.buf.lock().unwrap();
        let spec = hound::WavSpec {
            channels:        1,
            sample_rate:     self.sample_rate,
            bits_per_sample: 16,
            sample_format:   hound::SampleFormat::Int,
        };
        let mut writer = hound::WavWriter::create(path, spec)?;
        for &s in data.iter() {
            writer.write_sample((s.clamp(-1.0, 1.0) * i16::MAX as f32) as i16)?;
        }
        writer.finalize()?;
        Ok(())
    }

    pub fn sample_rate(&self) -> u32 { self.sample_rate }
}

fn record_mono(data: &[f32], channels: usize, buf: &Arc<Mutex<Vec<f32>>>) {
    if let Ok(mut b) = buf.try_lock() {
        if b.len() >= MAX_RECORD_SAMPLES { return; }
        let ch = channels.max(1);
        for chunk in data.chunks(ch) {
            let mono = chunk.iter().sum::<f32>() / ch as f32;
            b.push(mono);
            if b.len() >= MAX_RECORD_SAMPLES { break; }
        }
    }
}
