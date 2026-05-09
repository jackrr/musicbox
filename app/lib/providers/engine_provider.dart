import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bug_report/crash_capture.dart';
import '../engine/engine.dart';

/// The single [AudioEngine] instance for the app's lifetime.
///
/// Initialised lazily on first access; disposed when [ProviderScope] is torn down.
final engineProvider = Provider<AudioEngine>((ref) {
  final engine = AudioEngine();
  // Install the Rust panic hook *before* creating the audio stream so any
  // panic during init is captured.
  final crashDir = CrashCapture.appDataDir;
  if (crashDir != null) {
    try { engine.installPanicHook(crashDir); } catch (_) {}
  }
  engine.init();
  ref.onDispose(engine.dispose);
  return engine;
});

/// Whether the engine is currently producing audio output.
final isPlayingProvider = StateProvider<bool>((ref) => false);
