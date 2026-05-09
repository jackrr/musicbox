import 'package:flutter_test/flutter_test.dart';
import 'package:musicbox/bug_report/bug_report_config.dart';
import 'package:musicbox/bug_report/log_buffer.dart';
import 'package:musicbox/bug_report/report_builder.dart';

void main() {
  group('LogBuffer', () {
    setUp(() => LogBuffer.instance.clear());

    test('appends with timestamp prefix', () {
      LogBuffer.instance.log('hello world');
      final s = LogBuffer.instance.snapshot();
      expect(s.length, 1);
      expect(s.first, matches(r'^\[.+\] hello world$'));
    });

    test('respects capacity', () {
      for (var i = 0; i < LogBuffer.capacity + 50; i++) {
        LogBuffer.instance.log('line $i');
      }
      expect(LogBuffer.instance.snapshot().length, LogBuffer.capacity);
      expect(LogBuffer.instance.snapshot().first, contains('line 50'));
    });

    test('splits multi-line messages', () {
      LogBuffer.instance.log('a\nb\nc');
      expect(LogBuffer.instance.snapshot().length, 3);
    });
  });

  group('ReportBuilder.utf8Length', () {
    test('ascii', () {
      expect(ReportBuilder.utf8Length('hello'), 5);
    });
    test('unicode', () {
      // "ä" = 2 bytes, "🐞" = 4 bytes
      expect(ReportBuilder.utf8Length('ä🐞'), 6);
    });
  });

  group('ReportBuilder.build', () {
    test('emits required sections and escapes content', () async {
      final config = BugReportConfig(
        appName: 'TestApp',
        appVersion: () async => '1.2.3',
        appContexts: [
          AppContext(
            name: 'tiny',
            build: () async => 'value with <angle> & amp',
          ),
          AppContext(
            name: 'huge',
            sizeLimitBytes: 10,
            build: () async => 'this is way more than ten bytes of content',
          ),
        ],
      );

      final blob = await ReportBuilder.build(
        config: config,
        description: 'My <bug> & friends',
        includeLogs: false,
        enabledContexts: {'tiny', 'huge'},
      );

      expect(blob, startsWith('<bug-report version="1">'));
      expect(blob, endsWith('</bug-report>'));
      expect(blob, contains('<description>'));
      expect(blob, contains('My &lt;bug&gt; &amp; friends'));
      expect(blob, contains('<device>'));
      expect(blob, contains('TestApp 1.2.3'));
      expect(blob, contains('<app-context name="tiny">'));
      expect(blob, contains('value with &lt;angle&gt; &amp; amp'));
      // Oversize sections become a single self-describing element.
      expect(
        blob,
        contains(
          '<app-context name="huge" truncated="true" size="42">\nelided\n</app-context>',
        ),
      );
    });

    test('omits disabled contexts and logs', () async {
      final config = BugReportConfig(
        appName: 'TestApp',
        appVersion: () async => '0.1.0',
        appContexts: [
          AppContext(
            name: 'a',
            build: () async => 'aaa',
          ),
        ],
      );
      final blob = await ReportBuilder.build(
        config: config,
        description: 'd',
        includeLogs: false,
        enabledContexts: const <String>{},
      );
      expect(blob, isNot(contains('<app-context')));
      expect(blob, isNot(contains('<recent-logs')));
    });

    test('measureContexts auto-disables oversize by default', () async {
      final config = BugReportConfig(
        appName: 'X',
        appVersion: () async => '0',
        appContexts: [
          AppContext(name: 'small', build: () async => 'hi'),
          AppContext(
            name: 'big',
            sizeLimitBytes: 5,
            build: () async => 'hello world',
          ),
        ],
      );
      final stats = await ReportBuilder.measureContexts(config);
      expect(stats.length, 2);
      expect(stats[0].defaultEnabled, true);
      expect(stats[0].oversize, false);
      expect(stats[1].defaultEnabled, false);
      expect(stats[1].oversize, true);
    });
  });
}
