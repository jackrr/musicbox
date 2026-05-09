import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One named section that gets emitted as a `<app-context name="…">` block
/// inside the `<bug-report>` blob.
///
/// To reuse this module in a different app, supply a different list of
/// [AppContext]s — nothing else needs to change.
class AppContext {
  /// `name="…"` attribute on the `<app-context>` tag.
  final String name;

  /// Producer for the section content. Called lazily when the bug-report
  /// sheet opens or when "Copy" is pressed (whichever needs the latest size).
  final Future<String> Function() build;

  /// Whether the toggle is on by default in the sheet.
  final bool defaultEnabled;

  /// Optional cap. If the produced content exceeds this, the sheet shows
  /// the actual size next to the toggle and the section is emitted as
  /// `<app-context name="…" truncated="true" size="N">elided</app-context>`.
  /// The user may override and include the full content via the
  /// "Save attachment to file" path.
  final int? sizeLimitBytes;

  /// Short human-readable label for the toggle row (defaults to [name]).
  final String? label;

  const AppContext({
    required this.name,
    required this.build,
    this.defaultEnabled = true,
    this.sizeLimitBytes,
    this.label,
  });
}

/// Static, project-supplied configuration for the bug-report module.
///
/// Override [bugReportConfigProvider] in your `ProviderScope` at app start.
class BugReportConfig {
  /// Used in the device line: `… · app <appName>/<appVersion>`.
  final String appName;

  /// Producer for the version string (e.g. `0.4.2+17`).
  final Future<String> Function() appVersion;

  /// Ordered list of sections that the user can toggle on/off.
  final List<AppContext> appContexts;

  /// Optional URL the snackbar links to after copy. Set via Settings.
  /// `null` = no link.
  final String? webUrl;

  const BugReportConfig({
    required this.appName,
    required this.appVersion,
    this.appContexts = const [],
    this.webUrl,
  });

  BugReportConfig copyWith({String? webUrl}) => BugReportConfig(
        appName: appName,
        appVersion: appVersion,
        appContexts: appContexts,
        webUrl: webUrl ?? this.webUrl,
      );
}

/// Override this in `ProviderScope` at app startup.
final bugReportConfigProvider = Provider<BugReportConfig>((ref) {
  throw UnimplementedError(
    'bugReportConfigProvider must be overridden in ProviderScope.overrides',
  );
});
