import 'dart:ffi';

import 'bindings.dart';
import 'types.dart';

export 'types.dart';

/// High-level interface to the Rust audio engine.
///
/// Lifecycle:
///   1. Call [init] once (typically inside a Riverpod provider).
///   2. Use [noteOn] / [noteOff] / [setVoiceParam] to drive synthesis.
///   3. Call [dispose] on shutdown.
class AudioEngine {
  static final _bindings = EngineBindings();

  Pointer<Void> _ptr = nullptr;
  bool _initialized = false;

  void init() {
    if (_initialized) return;
    _ptr = _bindings.create();
    if (_ptr == nullptr) {
      throw StateError(
        'musicbox_engine_create returned null — check audio permissions.',
      );
    }
    _initialized = true;
  }

  void dispose() {
    if (!_initialized) return;
    _bindings.destroy(_ptr);
    _ptr = nullptr;
    _initialized = false;
  }

  // --- Synthesis control -------------------------------------------------------

  /// Trigger a note. [velocity] is 0–127.
  void noteOn(int trackId, int pitch, int velocity) =>
      _send(0, trackId, pitch, velocity.clamp(0, 127), 0.0);

  /// Release a note.
  void noteOff(int trackId, int pitch) =>
      _send(1, trackId, pitch, 0, 0.0);

  /// Set a voice parameter on [trackId].
  void setVoiceParam(int trackId, VoiceParam param, double value) =>
      _send(2, trackId, param.index, 0, value);

  // --- Private -----------------------------------------------------------------

  bool _send(int kind, int trackId, int paramA, int paramB, double value) {
    _requireInitialized();
    return _bindings.sendCommand(_ptr, kind, trackId, paramA, paramB, value);
  }

  void _requireInitialized() {
    if (!_initialized) throw StateError('AudioEngine.init() not called.');
  }
}
