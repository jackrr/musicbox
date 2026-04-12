import 'dart:ffi';

import 'bindings.dart';

/// High-level interface to the Rust audio engine.
///
/// Lifecycle:
///   1. Call [init] once (e.g. in a Riverpod provider).
///   2. Call [start] / [stop] to toggle audio output.
///   3. Call [dispose] when the app is shutting down.
class AudioEngine {
  static final _bindings = EngineBindings();

  Pointer<Void> _ptr = nullptr;
  bool _initialized = false;

  /// Initialise the engine and open the audio device.
  ///
  /// Throws [StateError] if the native engine fails to initialise.
  void init() {
    if (_initialized) return;
    _ptr = _bindings.create();
    if (_ptr == nullptr) {
      throw StateError(
        'musicbox_engine_create returned null — check device permissions.',
      );
    }
    _initialized = true;
  }

  /// Release the engine and close the audio stream.
  void dispose() {
    if (!_initialized) return;
    _bindings.destroy(_ptr);
    _ptr = nullptr;
    _initialized = false;
  }

  /// Start audio output (begins producing sound).
  void start() {
    _requireInitialized();
    _bindings.start(_ptr);
  }

  /// Stop audio output (stream stays open, outputs silence).
  void stop() {
    _requireInitialized();
    _bindings.stop(_ptr);
  }

  void _requireInitialized() {
    if (!_initialized) {
      throw StateError('AudioEngine.init() has not been called.');
    }
  }
}
