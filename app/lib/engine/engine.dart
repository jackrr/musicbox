import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'bindings.dart';
import 'types.dart';

export 'types.dart';

/// High-level interface to the Rust audio engine.
///
/// Lifecycle:
///   1. Call [init] once (typically inside a Riverpod provider).
///   2. Use the typed command methods to drive synthesis/sequencer.
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
          'musicbox_engine_create returned null — check audio permissions.');
    }
    _initialized = true;
  }

  void dispose() {
    if (!_initialized) return;
    _bindings.destroy(_ptr);
    _ptr = nullptr;
    _initialized = false;
  }

  // --- Synthesis ---------------------------------------------------------------

  void noteOn(int trackId, int pitch, int velocity) =>
      _send(0, trackId, pitch, velocity.clamp(0, 127), 0.0);

  void noteOff(int trackId, int pitch) =>
      _send(1, trackId, pitch, 0, 0.0);

  void setVoiceParam(int trackId, VoiceParam param, double value) =>
      _send(2, trackId, param.index, 0, value);

  // --- Sequencer ---------------------------------------------------------------

  void setBpm(double bpm) =>
      _send(3, 0, 0, 0, bpm);

  void setTransport(TransportState state) =>
      _send(4, 0, state.index, 0, 0.0);

  /// Set a step. Pass [active]=false to clear it.
  void setStep(int trackId, int stepIdx, {
    bool active = true,
    int pitch = 60,
    double velocity = 0.8,
  }) {
    _send(5, trackId, stepIdx, pitch, active ? velocity : 0.0);
  }

  void setEffect(int trackId, EffectParam param, double value) =>
      _send(6, trackId, param.index, 0, value);

  void setNumSteps(int n) =>
      _send(7, 0, n, 0, 0.0);

  void setSampleParam(int trackId, SampleParam param, double value) =>
      _send(8, trackId, param.index, 0, value);

  // --- Playhead ----------------------------------------------------------------

  /// Current sequencer step (0..numSteps-1), or -1 when stopped.
  int getPlayhead() {
    _requireInitialized();
    return _bindings.getPlayhead(_ptr);
  }

  // --- Sampler -----------------------------------------------------------------

  /// Returns true if a sample is currently loaded in the engine for [trackId].
  bool hasSample(int trackId) {
    _requireInitialized();
    return _bindings.hasSample(_ptr, trackId);
  }

  /// Fetch downsampled waveform peaks for [trackId].
  /// Returns a [Float32List] of length [numPeaks]*2 with alternating (min, max) pairs,
  /// or null if no sample is loaded for that track.
  Float32List? getSamplePeaks(int trackId, {int numPeaks = 600}) {
    _requireInitialized();
    final outPtr = malloc.allocate<Float>(numPeaks * 2);
    try {
      final count = _bindings.getSamplePeaks(_ptr, trackId, outPtr, numPeaks);
      if (count == 0) return null;
      final result = Float32List(count * 2);
      for (var i = 0; i < count * 2; i++) {
        result[i] = outPtr[i];
      }
      return result;
    } finally {
      malloc.free(outPtr);
    }
  }

  /// Load a WAV file at [path] into [trackId]. Returns false on failure.
  bool loadSample(int trackId, String path) {
    _requireInitialized();
    final bytes = utf8.encode(path);
    final ptr = malloc.allocate<Uint8>(bytes.length);
    try {
      ptr.asTypedList(bytes.length).setAll(0, bytes);
      return _bindings.loadSample(_ptr, trackId, ptr, bytes.length);
    } finally {
      malloc.free(ptr);
    }
  }

  // --- Recording ---------------------------------------------------------------

  /// Start microphone input recording. Returns false if the input device could
  /// not be opened (e.g., permission denied or no microphone available).
  bool startRecording() {
    _requireInitialized();
    return _bindings.startRecording(_ptr);
  }

  /// Stop recording and write the captured audio to a WAV file at [path].
  /// Returns true on success.
  bool stopRecording(String path) {
    _requireInitialized();
    final bytes = utf8.encode(path);
    final ptr = malloc.allocate<Uint8>(bytes.length);
    try {
      ptr.asTypedList(bytes.length).setAll(0, bytes);
      return _bindings.stopRecording(_ptr, ptr, bytes.length);
    } finally {
      malloc.free(ptr);
    }
  }

  // --- Export ------------------------------------------------------------------

  /// Render [bars] bars to a WAV file at [path]. Blocks — call from an isolate.
  Future<bool> exportWav(String path, int bars) async {
    _requireInitialized();
    // Capture what we need before spawning the isolate
    final ptrAddr = _ptr.address;
    final result = await Isolate.run(() {
      final ptr = Pointer<Void>.fromAddress(ptrAddr);
      final bytes = utf8.encode(path);
      final pathPtr = malloc.allocate<Uint8>(bytes.length);
      try {
        pathPtr.asTypedList(bytes.length).setAll(0, bytes);
        return EngineBindings().exportWav(ptr, pathPtr, bytes.length, bars);
      } finally {
        malloc.free(pathPtr);
      }
    });
    return result;
  }

  /// Export progress 0–100 (poll while exportWav is running).
  int exportProgress() {
    _requireInitialized();
    return _bindings.exportProgress(_ptr);
  }

  // --- Private -----------------------------------------------------------------

  bool _send(int kind, int trackId, int paramA, int paramB, double value) {
    _requireInitialized();
    return _bindings.sendCommand(_ptr, kind, trackId, paramA, paramB, value);
  }

  void _requireInitialized() {
    if (!_initialized) throw StateError('AudioEngine.init() not called.');
  }
}
