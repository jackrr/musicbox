import 'dart:async';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../engine/engine.dart';

class ExportService {
  static ExportService? _instance;
  ExportService._();
  static ExportService get instance => _instance ??= ExportService._();

  /// Returns 0..100 progress (poll during [export]).
  int lastProgress = 0;

  Future<bool> export(AudioEngine engine, {int bars = 4}) async {
    final dir  = await getTemporaryDirectory();
    final path = '${dir.path}/musicbox_export_${DateTime.now().millisecondsSinceEpoch}.wav';

    // Poll progress in background while export runs
    lastProgress = 0;
    final timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      lastProgress = engine.exportProgress();
    });

    final ok = await engine.exportWav(path, bars);
    timer.cancel();
    lastProgress = 100;

    if (!ok) return false;

    await Share.shareXFiles(
      [XFile(path, mimeType: 'audio/wav')],
      subject: 'musicbox export',
    );

    return true;
  }
}
