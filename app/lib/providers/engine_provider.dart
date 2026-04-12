import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/engine.dart';

/// The single [AudioEngine] instance for the app's lifetime.
///
/// Initialised lazily on first access; disposed when [ProviderScope] is torn down.
final engineProvider = Provider<AudioEngine>((ref) {
  final engine = AudioEngine();
  engine.init();
  ref.onDispose(engine.dispose);
  return engine;
});

/// Whether the engine is currently producing audio output.
final isPlayingProvider = StateProvider<bool>((ref) => false);
