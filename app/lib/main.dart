import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/engine_provider.dart';

void main() {
  runApp(const ProviderScope(child: MusicboxApp()));
}

class MusicboxApp extends StatelessWidget {
  const MusicboxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'musicbox',
      theme: ThemeData.dark(useMaterial3: true),
      home: const ToneTestPage(),
    );
  }
}

/// Phase 1 test screen — verifies the Dart → Rust → speaker path.
class ToneTestPage extends ConsumerWidget {
  const ToneTestPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPlaying = ref.watch(isPlayingProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          'musicbox',
          style: TextStyle(letterSpacing: 2, fontWeight: FontWeight.w300),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isPlaying
                    ? Colors.greenAccent.withAlpha(200)
                    : Colors.white12,
                boxShadow: isPlaying
                    ? [
                        BoxShadow(
                          color: Colors.greenAccent.withAlpha(100),
                          blurRadius: 24,
                          spreadRadius: 4,
                        ),
                      ]
                    : [],
              ),
            ),
            const SizedBox(height: 32),
            Text(
              isPlaying ? '440 Hz' : 'stopped',
              style: TextStyle(
                color: isPlaying ? Colors.greenAccent : Colors.white38,
                fontSize: 14,
                letterSpacing: 3,
              ),
            ),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: SizedBox(
        width: 120,
        height: 120,
        child: FloatingActionButton(
          onPressed: () => _toggle(ref),
          backgroundColor: isPlaying ? Colors.greenAccent : Colors.white24,
          foregroundColor: Colors.black,
          child: Icon(
            isPlaying ? Icons.stop_rounded : Icons.play_arrow_rounded,
            size: 56,
          ),
        ),
      ),
    );
  }

  void _toggle(WidgetRef ref) {
    final engine = ref.read(engineProvider);
    final notifier = ref.read(isPlayingProvider.notifier);
    final playing = ref.read(isPlayingProvider);
    if (playing) {
      engine.stop();
      notifier.state = false;
    } else {
      engine.start();
      notifier.state = true;
    }
  }
}
