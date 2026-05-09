import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../bug_report_config.dart';
import '../report_builder.dart';

/// Bottom-sheet UI that captures a description, lets the user toggle which
/// `<app-context>` blocks to include, previews the assembled `<bug-report>`
/// blob, and copies it to the clipboard.
class BugReportSheet extends ConsumerStatefulWidget {
  const BugReportSheet({super.key});

  @override
  ConsumerState<BugReportSheet> createState() => _BugReportSheetState();
}

class _BugReportSheetState extends ConsumerState<BugReportSheet> {
  final _descCtrl = TextEditingController();
  bool _includeLogs = true;
  bool _loading = true;
  List<ContextStat> _stats = const [];
  final Set<String> _enabled = <String>{};
  String _preview = '';

  @override
  void initState() {
    super.initState();
    _measure();
    _descCtrl.addListener(_refreshPreview);
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _measure() async {
    final config = ref.read(bugReportConfigProvider);
    final stats = await ReportBuilder.measureContexts(config);
    if (!mounted) return;
    setState(() {
      _stats = stats;
      _enabled
        ..clear()
        ..addAll(stats.where((s) => s.defaultEnabled).map((s) => s.name));
      _loading = false;
    });
    _refreshPreview();
  }

  Future<void> _refreshPreview() async {
    final config = ref.read(bugReportConfigProvider);
    // Build a non-consuming preview: peek-only crash text; LogBuffer is
    // read-only too. We rebuild below at copy-time which actually consumes
    // the pending crash file.
    final previewBlob = await _buildPreview(config);
    if (!mounted) return;
    setState(() => _preview = previewBlob);
  }

  Future<String> _buildPreview(BugReportConfig config) async {
    // Use measureContexts cache — avoid re-running expensive builders.
    // ReportBuilder.build re-runs builders, so for the live preview we
    // approximate by reusing cached raw content.
    final buf = StringBuffer();
    buf.writeln('<bug-report version="${ReportBuilder.version}">');
    buf.writeln('<description>');
    buf.writeln(_escape(_descCtrl.text.trim()));
    buf.writeln('</description>');
    buf.writeln('<device>');
    final ver = await config.appVersion();
    buf.writeln(_escape(
        '${Platform.operatingSystem} ${Platform.operatingSystemVersion} · ${config.appName} $ver'));
    buf.writeln('</device>');
    if (_includeLogs) {
      buf.writeln('<recent-logs lines="(preview)">…</recent-logs>');
    }
    for (final s in _stats) {
      if (!_enabled.contains(s.name)) continue;
      if (s.oversize) {
        buf.writeln(
            '<app-context name="${s.name}" truncated="true" size="${s.actualSize}">elided</app-context>');
      } else {
        buf.writeln('<app-context name="${s.name}">');
        buf.writeln(_escape(s.rawContent));
        buf.writeln('</app-context>');
      }
    }
    buf.write('</bug-report>');
    return buf.toString();
  }

  String _escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  Future<void> _copy() async {
    final config = ref.read(bugReportConfigProvider);
    final blob = await ReportBuilder.build(
      config: config,
      description: _descCtrl.text,
      includeLogs: _includeLogs,
      enabledContexts: _enabled,
    );
    await Clipboard.setData(ClipboardData(text: blob));
    final sizeKb = (blob.length / 1024).toStringAsFixed(1);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 6),
        content: Row(
          children: [
            Expanded(child: Text('Copied ($sizeKb KB).')),
            if (config.webUrl != null && config.webUrl!.isNotEmpty)
              TextButton(
                onPressed: () async {
                  final uri = Uri.tryParse(config.webUrl!);
                  if (uri != null) {
                    await launchUrl(uri,
                        mode: LaunchMode.externalApplication);
                  }
                },
                child: const Text(
                  'Open →',
                  style: TextStyle(color: Colors.greenAccent),
                ),
              ),
          ],
        ),
      ),
    );
    Navigator.of(context).pop();
  }

  Future<void> _shareOversize() async {
    final oversize = _stats.where((s) => s.oversize).toList();
    if (oversize.isEmpty) return;
    final tmp = await getTemporaryDirectory();
    final files = <XFile>[];
    for (final s in oversize) {
      final f = File('${tmp.path}/${s.name}.txt');
      await f.writeAsString(s.rawContent);
      files.add(XFile(f.path));
    }
    await Share.shareXFiles(files,
        subject: 'Bug report attachments');
  }

  String _fmtBytes(int n) {
    if (n < 1024) return '${n}B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)}KB';
    return '${(n / 1024 / 1024).toStringAsFixed(1)}MB';
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final hasOversize = _stats.any((s) => s.oversize);

    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF111111),
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        constraints: BoxConstraints(maxHeight: mq.size.height * 0.92),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              const Text('Bug Report',
                  style: TextStyle(
                      fontSize: 14,
                      letterSpacing: 2,
                      color: Colors.white70,
                      fontWeight: FontWeight.w300)),
              const Divider(color: Colors.white12, height: 16),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 4),
                  child: _loading
                      ? const Padding(
                          padding: EdgeInsets.all(40),
                          child: Center(
                              child: CircularProgressIndicator(
                                  color: Colors.greenAccent)),
                        )
                      : _buildBody(),
                ),
              ),
              const Divider(color: Colors.white12, height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: _Btn(
                        label: 'Copy to clipboard',
                        color: Colors.greenAccent,
                        onTap: _loading || _descCtrl.text.trim().isEmpty
                            ? null
                            : _copy,
                      ),
                    ),
                    if (hasOversize) ...[
                      const SizedBox(width: 8),
                      _Btn(
                        label: 'Save attachment…',
                        color: Colors.white54,
                        onTap: _shareOversize,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('DESCRIPTION',
            style: TextStyle(
                fontSize: 10,
                letterSpacing: 2,
                color: Colors.white38,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        TextField(
          controller: _descCtrl,
          minLines: 3,
          maxLines: 6,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'What happened? What did you expect?',
            hintStyle: const TextStyle(color: Colors.white24),
            filled: true,
            fillColor: Colors.white10,
            contentPadding: const EdgeInsets.all(12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
          ),
          onChanged: (_) => _refreshPreview(),
        ),
        const SizedBox(height: 18),
        const Text('INCLUDE',
            style: TextStyle(
                fontSize: 10,
                letterSpacing: 2,
                color: Colors.white38,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          activeColor: Colors.greenAccent,
          title: const Text('Recent logs',
              style: TextStyle(color: Colors.white, fontSize: 13)),
          subtitle: const Text('last 120 lines + any pending crash',
              style: TextStyle(color: Colors.white38, fontSize: 11)),
          value: _includeLogs,
          onChanged: (v) {
            setState(() => _includeLogs = v);
            _refreshPreview();
          },
        ),
        for (final s in _stats)
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            activeColor: Colors.greenAccent,
            title: Text(s.label,
                style: const TextStyle(color: Colors.white, fontSize: 13)),
            subtitle: Text(
              s.error != null
                  ? 'error: ${s.error}'
                  : (s.oversize
                      ? '${_fmtBytes(s.actualSize)} (over ${_fmtBytes(s.sizeLimitBytes!)} limit — will be elided)'
                      : _fmtBytes(s.actualSize)),
              style: TextStyle(
                  color: s.oversize ? Colors.orangeAccent : Colors.white38,
                  fontSize: 11),
            ),
            value: _enabled.contains(s.name),
            onChanged: s.error != null
                ? null
                : (v) {
                    setState(() {
                      if (v) {
                        _enabled.add(s.name);
                      } else {
                        _enabled.remove(s.name);
                      }
                    });
                    _refreshPreview();
                  },
          ),
        const SizedBox(height: 18),
        const Text('PREVIEW',
            style: TextStyle(
                fontSize: 10,
                letterSpacing: 2,
                color: Colors.white38,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white12),
          ),
          child: SelectableText(
            _preview,
            style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: Colors.white70,
                height: 1.4),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _Btn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback? onTap;
  const _Btn({required this.label, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: onTap != null ? color.withAlpha(30) : Colors.white10,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: onTap != null ? color : Colors.white10),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: onTap != null ? color : Colors.white24,
            ),
          ),
        ),
      );
}
