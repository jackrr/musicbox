mod audio;
mod commands;
mod effects;
mod export;
mod sampler;
mod sequencer;
mod synth;

// ---------------------------------------------------------------------------
// Android: initialise the JNI/NDK context that cpal's oboe backend requires.
// Called automatically by the Android runtime when the .so is loaded.
// ---------------------------------------------------------------------------

#[cfg(target_os = "android")]
#[allow(non_snake_case)]
#[no_mangle]
pub unsafe extern "C" fn JNI_OnLoad(
    vm: jni::JavaVM,
    _: *mut std::ffi::c_void,
) -> jni::sys::jint {
    // Provide the JavaVM to cpal's oboe/AAudio backend via ndk-context.
    // The activity pointer can be null here; oboe only needs it for audio
    // focus which we don't use.
    ndk_context::initialize_android_context(
        vm.get_java_vm_pointer().cast(),
        std::ptr::null_mut(),
    );
    jni::sys::JNI_VERSION_1_6
}

use std::sync::{
    atomic::{AtomicI32, AtomicU32, Ordering},
    mpsc, Arc,
};

use audio::AudioStream;
use commands::FfiCommand;
use export::{ExportState, render_wav};
use sampler::{load_wav, SampleMsg};
use sequencer::{Step, MAX_STEPS, NUM_TRACKS};
use synth::voice::TrackParams;

const QUEUE_CAPACITY: usize = 2048;

// ---------------------------------------------------------------------------
// Engine — opaque handle passed across FFI
// ---------------------------------------------------------------------------

pub struct Engine {
    _stream:   AudioStream,
    cmd_tx:    rtrb::Producer<FfiCommand>,
    sample_tx: mpsc::Sender<SampleMsg>,
    playhead:  Arc<AtomicI32>,

    // Mirror of sequencer + synth state for offline export
    bpm:          f32,
    num_steps:    usize,
    patterns:     Box<[[Step; MAX_STEPS]; NUM_TRACKS]>,
    track_params: Box<[TrackParams; NUM_TRACKS]>,

    // Export progress 0..=100 (101 = failed)
    export_progress: Arc<AtomicU32>,
}

impl Engine {
    fn new() -> Result<Self, String> {
        let (cmd_tx, cmd_rx) = rtrb::RingBuffer::new(QUEUE_CAPACITY);
        let (sample_tx, sample_rx) = mpsc::channel::<SampleMsg>();

        let (stream, playhead) =
            AudioStream::new(cmd_rx, sample_rx).map_err(|e| e.to_string())?;

        Ok(Self {
            _stream: stream,
            cmd_tx,
            sample_tx,
            playhead,
            bpm: 120.0,
            num_steps: 16,
            patterns: Box::new([[Step::default(); MAX_STEPS]; NUM_TRACKS]),
            track_params: Box::new(std::array::from_fn(|_| TrackParams::default())),
            export_progress: Arc::new(AtomicU32::new(0)),
        })
    }

    fn send(&mut self, cmd: FfiCommand) -> bool {
        self.cmd_tx.push(cmd).is_ok()
    }
}

// ---------------------------------------------------------------------------
// C ABI exports
// ---------------------------------------------------------------------------

#[no_mangle]
pub extern "C" fn musicbox_engine_create() -> *mut Engine {
    match Engine::new() {
        Ok(e)  => Box::into_raw(Box::new(e)),
        Err(e) => { eprintln!("[musicbox] create failed: {e}"); std::ptr::null_mut() }
    }
}

/// # Safety
/// `ptr` must be a valid Engine pointer from `musicbox_engine_create`.
#[no_mangle]
pub unsafe extern "C" fn musicbox_engine_destroy(ptr: *mut Engine) {
    if !ptr.is_null() { drop(Box::from_raw(ptr)); }
}

/// Send a command to the audio thread.
/// Returns false if the ring buffer is full.
///
/// # Safety
#[no_mangle]
pub unsafe extern "C" fn musicbox_engine_send_command(
    ptr: *mut Engine, kind: u8, track_id: u8, param_a: u8, param_b: u8, value: f32,
) -> bool {
    if ptr.is_null() { return false; }
    let cmd = FfiCommand { kind, track_id, param_a, param_b, value };

    // Keep mirror in sync for certain command types
    let e = &mut *ptr;
    match kind {
        3 => { e.bpm = value; }
        5 => { // SetStep
            let (ti, si) = (track_id as usize, param_a as usize);
            if ti < NUM_TRACKS && si < MAX_STEPS {
                if value <= 0.0 {
                    e.patterns[ti][si].active = false;
                } else {
                    e.patterns[ti][si] = Step { active: true, pitch: param_b, velocity: (value * 127.0) as u8 };
                }
            }
        }
        7 => { e.num_steps = param_a as usize; }
        2 => { // SetVoiceParam
            if let Some(tp) = e.track_params.get_mut(track_id as usize) {
                match param_a {
                    0 => tp.osc_type  = synth::voice::OscType::from_f32(value),
                    1 => tp.attack    = value,
                    2 => tp.decay     = value,
                    3 => tp.sustain   = value,
                    4 => tp.release   = value,
                    5 => tp.cutoff    = value,
                    6 => tp.resonance = value,
                    7 => tp.volume    = value,
                    _ => {}
                }
            }
        }
        _ => {}
    }

    e.send(cmd)
}

/// Current sequencer step (0..num_steps-1), or -1 when stopped.
///
/// # Safety
#[no_mangle]
pub unsafe extern "C" fn musicbox_engine_get_playhead(ptr: *const Engine) -> i32 {
    if ptr.is_null() { return -1; }
    (*ptr).playhead.load(Ordering::Relaxed)
}

/// Load a WAV file into a sampler track (called from Dart's thread, not audio thread).
///
/// # Safety
#[no_mangle]
pub unsafe extern "C" fn musicbox_engine_load_sample(
    ptr: *mut Engine, track_id: u8, path_ptr: *const u8, path_len: usize,
) -> bool {
    if ptr.is_null() || path_ptr.is_null() { return false; }
    let path = match std::str::from_utf8(std::slice::from_raw_parts(path_ptr, path_len)) {
        Ok(s) => s, Err(_) => return false,
    };
    match load_wav(path) {
        Ok((data, rate)) => {
            let _ = (*ptr).sample_tx.send(SampleMsg {
                track_id, data: std::sync::Arc::new(data), source_rate: rate as f32,
            });
            true
        }
        Err(e) => { eprintln!("[musicbox] load_sample: {e}"); false }
    }
}

/// Render `bars` bars to a WAV file at `path`. Blocking — call from a Dart isolate.
/// Poll `musicbox_engine_export_progress` for progress 0..=100.
///
/// # Safety
#[no_mangle]
pub unsafe extern "C" fn musicbox_engine_export_wav(
    ptr: *mut Engine, path_ptr: *const u8, path_len: usize, bars: u32,
) -> bool {
    if ptr.is_null() || path_ptr.is_null() { return false; }
    let path = match std::str::from_utf8(std::slice::from_raw_parts(path_ptr, path_len)) {
        Ok(s) => s, Err(_) => return false,
    };
    let e = &*ptr;
    let state = ExportState {
        bpm: e.bpm, num_steps: e.num_steps,
        patterns: e.patterns.clone(),
        track_params: *e.track_params,
    };
    let progress = Arc::clone(&e.export_progress);
    progress.store(0, Ordering::Relaxed);
    match render_wav(path, bars, &state, &progress) {
        Ok(()) => true,
        Err(err) => { eprintln!("[musicbox] export: {err}"); false }
    }
}

/// Export progress 0..=100 (poll while `engine_export_wav` is running on another thread).
///
/// # Safety
#[no_mangle]
pub unsafe extern "C" fn musicbox_engine_export_progress(ptr: *const Engine) -> u32 {
    if ptr.is_null() { return 0; }
    (*ptr).export_progress.load(Ordering::Relaxed)
}

/// No-op stubs (transport handled via send_command kind=4).
#[no_mangle]
pub unsafe extern "C" fn musicbox_engine_start(_: *mut Engine) {}
#[no_mangle]
pub unsafe extern "C" fn musicbox_engine_stop(_: *mut Engine) {}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn create_and_destroy() {
        let ptr = musicbox_engine_create();
        if !ptr.is_null() { unsafe { musicbox_engine_destroy(ptr) }; }
    }

    #[test]
    fn null_safe_commands() {
        let r = unsafe { musicbox_engine_send_command(std::ptr::null_mut(), 0, 0, 60, 100, 0.0) };
        assert!(!r);
        let ph = unsafe { musicbox_engine_get_playhead(std::ptr::null()) };
        assert_eq!(ph, -1);
    }
}
