import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Persists uncaught Dart exceptions and Rust panics to a file, so the next
/// app launch can surface them inside a bug report.
///
/// File layout under the app documents directory:
///   * `bug_report_pending_crash.txt` — appended to on every crash; consumed
///     (read + deleted) the next time the user opens the bug-report sheet.
///   * `panic.log` — written by the Rust panic hook (see `engine/src/lib.rs`).
///     [init] migrates this into the pending crash file on app start.
class CrashCapture {
  static const _pendingFileName = 'bug_report_pending_crash.txt';
  static const _rustPanicFileName = 'panic.log';

  static File? _pendingFile;
  static String? _appDataDir;

  /// Path passed to the Rust engine so its panic hook knows where to write.
  static String? get appDataDir => _appDataDir;

  /// Wire up `FlutterError.onError`, the current isolate's error listener,
  /// and migrate any Rust panic file into the pending-crash file.
  ///
  /// Safe to call multiple times.
  static Future<void> init() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      _appDataDir = dir.path;
      _pendingFile = File('${dir.path}/$_pendingFileName');

      // Pull in any Rust-side panic from the previous run.
      final rustPanic = File('${dir.path}/$_rustPanicFileName');
      if (await rustPanic.exists()) {
        try {
          final body = await rustPanic.readAsString();
          await _appendToPending(
            'rust panic (previous run)',
            body,
            StackTrace.empty,
          );
        } finally {
          try { await rustPanic.delete(); } catch (_) {}
        }
      }
    } catch (e) {
      // If we can't even open the docs dir, fall through silently — the
      // bug-report module just won't have crash context.
      debugPrint('CrashCapture.init failed: $e');
    }

    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      recordError(details.exception, details.stack ?? StackTrace.current);
    };

    Isolate.current.addErrorListener(RawReceivePort((dynamic pair) {
      final list = pair as List<dynamic>;
      final err = list.isNotEmpty ? list[0] : 'unknown';
      final st = list.length > 1 ? list[1] : null;
      recordError(
        err,
        st is String ? StackTrace.fromString(st) : StackTrace.current,
      );
    }).sendPort);
  }

  /// Records an error to the pending-crash file. Call from
  /// `runZonedGuarded`'s onError handler too.
  static void recordError(Object error, StackTrace stack) {
    // Fire-and-forget; we don't want a crash inside the crash handler.
    unawaited(_appendToPending('dart error', error.toString(), stack));
  }

  /// Returns the current pending crash text and deletes the file.
  /// Returns `null` if there's nothing pending.
  static Future<String?> consumePendingCrash() async {
    final f = _pendingFile;
    if (f == null) return null;
    try {
      if (!await f.exists()) return null;
      final text = await f.readAsString();
      try { await f.delete(); } catch (_) {}
      return text.isEmpty ? null : text;
    } catch (e) {
      debugPrint('CrashCapture.consumePendingCrash failed: $e');
      return null;
    }
  }

  /// Like [consumePendingCrash] but leaves the file in place. The bug-report
  /// sheet uses this for the preview; the real consume happens at copy time.
  static Future<String?> peekPendingCrash() async {
    final f = _pendingFile;
    if (f == null) return null;
    try {
      if (!await f.exists()) return null;
      final text = await f.readAsString();
      return text.isEmpty ? null : text;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _appendToPending(
    String kind,
    String message,
    StackTrace stack,
  ) async {
    final f = _pendingFile;
    if (f == null) return;
    try {
      final ts = DateTime.now().toUtc().toIso8601String();
      final entry = '[$ts] $kind\n$message\n$stack\n---\n';
      await f.writeAsString(entry, mode: FileMode.append, flush: true);
    } catch (e) {
      debugPrint('CrashCapture._appendToPending failed: $e');
    }
  }
}
