import 'dart:collection';

/// Bounded ring buffer of log lines, fed by an override of [debugPrint].
///
/// Each entry is prefixed with an ISO-8601 timestamp at insertion time.
/// Newest line at the tail; [snapshot] returns oldest-first.
class LogBuffer {
  static final instance = LogBuffer._();
  LogBuffer._();

  /// Maximum number of retained lines.
  static const int capacity = 500;

  final ListQueue<String> _lines = ListQueue<String>();

  /// Append [line] to the buffer. The line is prefixed with `[<iso-ts>]`.
  /// Multi-line messages are split so each underlying line has its own
  /// timestamp.
  void log(String line) {
    final ts = DateTime.now().toUtc().toIso8601String();
    for (final part in line.split('\n')) {
      if (part.isEmpty) continue;
      _lines.addLast('[$ts] $part');
      while (_lines.length > capacity) {
        _lines.removeFirst();
      }
    }
  }

  /// Immutable oldest-first view.
  List<String> snapshot() => List.unmodifiable(_lines);

  /// Drop everything (used in tests).
  void clear() => _lines.clear();
}
