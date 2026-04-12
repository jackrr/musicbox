mod audio;
mod commands;
mod synth;

use audio::AudioStream;
use commands::FfiCommand;

/// Queue capacity: 1 024 unread commands before Dart is told to back off.
const QUEUE_CAPACITY: usize = 1024;

/// Opaque engine handle passed across the FFI boundary.
///
/// Dart holds a raw pointer to this; Rust exclusively owns the memory.
pub struct Engine {
    _stream:    AudioStream,
    command_tx: rtrb::Producer<FfiCommand>,
}

impl Engine {
    fn new() -> Result<Self, String> {
        let (tx, rx) = rtrb::RingBuffer::<FfiCommand>::new(QUEUE_CAPACITY);
        let stream   = AudioStream::new(rx).map_err(|e| e.to_string())?;
        Ok(Self { _stream: stream, command_tx: tx })
    }
}

// ---------------------------------------------------------------------------
// C ABI exports
// ---------------------------------------------------------------------------

/// Create a new engine. Returns null on failure.
#[no_mangle]
pub extern "C" fn musicbox_engine_create() -> *mut Engine {
    match Engine::new() {
        Ok(e)  => Box::into_raw(Box::new(e)),
        Err(e) => { eprintln!("[musicbox] engine_create failed: {e}"); std::ptr::null_mut() }
    }
}

/// Free the engine and stop audio.
///
/// # Safety
/// `ptr` must be a valid pointer from `musicbox_engine_create` and
/// must not be used after this call.
#[no_mangle]
pub unsafe extern "C" fn musicbox_engine_destroy(ptr: *mut Engine) {
    if !ptr.is_null() { drop(Box::from_raw(ptr)); }
}

/// Send a command to the audio thread.
///
/// Returns `true` on success, `false` if the ring buffer is full (back-pressure).
///
/// # Safety
/// `ptr` must be a valid non-null Engine pointer.
#[no_mangle]
pub unsafe extern "C" fn musicbox_engine_send_command(
    ptr:      *mut Engine,
    kind:     u8,
    track_id: u8,
    param_a:  u8,
    param_b:  u8,
    value:    f32,
) -> bool {
    if ptr.is_null() { return false; }
    let cmd = FfiCommand { kind, track_id, param_a, param_b, value };
    (*ptr).command_tx.push(cmd).is_ok()
}

/// No-op stubs kept for API stability (transport will be revisited in Phase 3).
#[no_mangle]
pub unsafe extern "C" fn musicbox_engine_start(_ptr: *mut Engine) {}

#[no_mangle]
pub unsafe extern "C" fn musicbox_engine_stop(_ptr: *mut Engine) {}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn create_and_destroy() {
        let ptr = musicbox_engine_create();
        if !ptr.is_null() {
            unsafe { musicbox_engine_destroy(ptr) };
        }
    }

    #[test]
    fn send_command_null_safe() {
        // Should not crash or panic on a null pointer.
        let ok = unsafe { musicbox_engine_send_command(std::ptr::null_mut(), 0, 0, 60, 100, 0.0) };
        assert!(!ok);
    }
}
