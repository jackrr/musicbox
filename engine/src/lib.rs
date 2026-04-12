use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc,
};

mod audio;

use audio::AudioStream;

/// Opaque engine handle passed across the FFI boundary.
///
/// Dart holds a raw pointer to this; Rust owns the memory.
pub struct Engine {
    _stream: AudioStream,
    is_playing: Arc<AtomicBool>,
}

impl Engine {
    fn new() -> Result<Self, String> {
        let is_playing = Arc::new(AtomicBool::new(false));
        let stream = AudioStream::new(Arc::clone(&is_playing)).map_err(|e| e.to_string())?;
        Ok(Self {
            _stream: stream,
            is_playing,
        })
    }
}

// ---------------------------------------------------------------------------
// C ABI exports
// ---------------------------------------------------------------------------

/// Create a new engine. Returns null on failure.
#[no_mangle]
pub extern "C" fn musicbox_engine_create() -> *mut Engine {
    match Engine::new() {
        Ok(engine) => Box::into_raw(Box::new(engine)),
        Err(e) => {
            eprintln!("[musicbox] engine_create failed: {e}");
            std::ptr::null_mut()
        }
    }
}

/// Destroy the engine and free all resources.
///
/// # Safety
/// `ptr` must be a valid pointer returned by `musicbox_engine_create`
/// and must not be used after this call.
#[no_mangle]
pub unsafe extern "C" fn musicbox_engine_destroy(ptr: *mut Engine) {
    if !ptr.is_null() {
        drop(Box::from_raw(ptr));
    }
}

/// Begin audio output.
///
/// # Safety
/// `ptr` must be a valid non-null Engine pointer.
#[no_mangle]
pub unsafe extern "C" fn musicbox_engine_start(ptr: *mut Engine) {
    if !ptr.is_null() {
        (*ptr).is_playing.store(true, Ordering::Relaxed);
    }
}

/// Silence audio output (stream stays active).
///
/// # Safety
/// `ptr` must be a valid non-null Engine pointer.
#[no_mangle]
pub unsafe extern "C" fn musicbox_engine_stop(ptr: *mut Engine) {
    if !ptr.is_null() {
        (*ptr).is_playing.store(false, Ordering::Relaxed);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn engine_create_destroy() {
        // Smoke test: create and immediately destroy without panicking.
        // Audio device may not be available in CI, so we allow failure.
        let ptr = musicbox_engine_create();
        if !ptr.is_null() {
            unsafe { musicbox_engine_destroy(ptr) };
        }
    }
}
