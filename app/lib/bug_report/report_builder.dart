import 'dart:io';

import 'bug_report_config.dart';
import 'crash_capture.dart';
import 'log_buffer.dart';

/// Produced section, ready for emission.
class _Section {
  final String name;
  final String content; // possibly elided
  final Map<String, String> attrs;
  final int actualSize;
  final bool truncated;
  _Section({
    required this.name,
    required this.content,
    required this.attrs,
    required this.actualSize,
    required this.truncated,
  });
}

/// Builds the `<bug-report>` XML blob that gets copied to the clipboard.
///
/// The output is plain text — there are no XML namespaces or schemas. The
/// server-side parser is forgiving (regex-based per-tag extraction); we just
/// need well-formed content and proper escaping inside the body of each tag.
class ReportBuilder {
  /// Spec version. Bump if you change the section layout.
  static const String version = '1';

  static Future<String> build({
    required BugReportConfig config,
    required String description,
    required bool includeLogs,
    required Set<String> enabledContexts,
    int recentLogLines = 120,
  }) async {
    final buf = StringBuffer();
    buf.writeln('<bug-report version="$version">');

    // <description>
    buf.writeln('<description>');
    buf.writeln(_escape(description.trim()));
    buf.writeln('</description>');

    // <device>
    buf.writeln('<device>');
    buf.writeln(_escape(await _deviceLine(config)));
    buf.writeln('</device>');

    // <recent-logs> — includes pending crash text at the top, if any.
    if (includeLogs) {
      final crashText = await CrashCapture.consumePendingCrash();
      final lines = LogBuffer.instance.snapshot();
      final tail = lines.length <= recentLogLines
          ? lines
          : lines.sublist(lines.length - recentLogLines);
      final body = StringBuffer();
      if (crashText != null) {
        body.writeln('=== pending crash from previous run ===');
        body.writeln(crashText.trim());
        body.writeln('=== logs ===');
      }
      for (final l in tail) {
        body.writeln(l);
      }
      buf.writeln('<recent-logs lines="${tail.length}">');
      buf.writeln(_escape(body.toString().trimRight()));
      buf.writeln('</recent-logs>');
    }

    // <app-context> blocks
    for (final ctx in config.appContexts) {
      if (!enabledContexts.contains(ctx.name)) continue;
      final section = await _buildContext(ctx);
      final attrs = StringBuffer('name="${_escapeAttr(section.name)}"');
      section.attrs.forEach((k, v) {
        attrs.write(' $k="${_escapeAttr(v)}"');
      });
      buf.writeln('<app-context $attrs>');
      buf.writeln(_escape(section.content));
      buf.writeln('</app-context>');
    }

    buf.write('</bug-report>');
    return buf.toString();
  }

  /// Pre-render every section so the UI can show sizes / truncation state.
  ///
  /// Returns one entry per `config.appContexts`, in order, with:
  /// `actualSize` (bytes of UTF-8), `truncated` (whether sizeLimit was hit).
  static Future<List<ContextStat>> measureContexts(
      BugReportConfig config) async {
    final out = <ContextStat>[];
    for (final ctx in config.appContexts) {
      try {
        final raw = await ctx.build();
        final size = utf8Length(raw);
        final over =
            ctx.sizeLimitBytes != null && size > ctx.sizeLimitBytes!;
        out.add(ContextStat(
          name: ctx.name,
          label: ctx.label ?? ctx.name,
          actualSize: size,
          sizeLimitBytes: ctx.sizeLimitBytes,
          oversize: over,
          defaultEnabled: ctx.defaultEnabled && !over,
          rawContent: raw,
        ));
      } catch (e) {
        out.add(ContextStat(
          name: ctx.name,
          label: ctx.label ?? ctx.name,
          actualSize: 0,
          sizeLimitBytes: ctx.sizeLimitBytes,
          oversize: false,
          defaultEnabled: false,
          rawContent: '',
          error: e.toString(),
        ));
      }
    }
    return out;
  }

  static Future<_Section> _buildContext(AppContext ctx) async {
    final raw = await ctx.build();
    final size = utf8Length(raw);
    final limit = ctx.sizeLimitBytes;
    if (limit != null && size > limit) {
      return _Section(
        name: ctx.name,
        content: 'elided',
        attrs: {'truncated': 'true', 'size': '$size'},
        actualSize: size,
        truncated: true,
      );
    }
    return _Section(
      name: ctx.name,
      content: raw,
      attrs: const {},
      actualSize: size,
      truncated: false,
    );
  }

  static Future<String> _deviceLine(BugReportConfig config) async {
    final os = Platform.operatingSystem; // 'android', 'ios', etc.
    final osv = Platform.operatingSystemVersion;
    final ver = await config.appVersion();
    return '$os $osv · ${config.appName} $ver';
  }

  /// XML-escape body text. We accept multi-line content verbatim apart from
  /// the five canonical replacements.
  static String _escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  static String _escapeAttr(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  /// UTF-8 byte length of [s].
  static int utf8Length(String s) {
    // Manual count avoids the dart:convert allocation.
    int n = 0;
    for (final c in s.runes) {
      if (c < 0x80) {
        n += 1;
      } else if (c < 0x800) {
        n += 2;
      } else if (c < 0x10000) {
        n += 3;
      } else {
        n += 4;
      }
    }
    return n;
  }
}

/// Per-section stat record used by the sheet UI.
class ContextStat {
  final String name;
  final String label;
  final int actualSize;
  final int? sizeLimitBytes;
  final bool oversize;
  final bool defaultEnabled;
  final String rawContent;
  final String? error;
  const ContextStat({
    required this.name,
    required this.label,
    required this.actualSize,
    required this.sizeLimitBytes,
    required this.oversize,
    required this.defaultEnabled,
    required this.rawContent,
    this.error,
  });
}
