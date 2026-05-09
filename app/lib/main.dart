import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bug_report/bug_report_config.dart';
import 'bug_report/crash_capture.dart';
import 'bug_report/log_buffer.dart';
import 'bug_report/musicbox_digest.dart';
import 'bug_report/ui/bug_report_sheet.dart';
import 'providers/engine_provider.dart';
import 'providers/project_provider.dart';
import 'services/export_service.dart';
import 'ui/ai/ai_page.dart';
import 'ui/effects/effects_page.dart';
import 'ui/pads/pad_page.dart';
import 'ui/sampler/sampler_page.dart';
import 'ui/sequencer/sequencer_page.dart';
import 'ui/settings/settings_page.dart';
import 'ui/synth/synth_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Tee debugPrint output into the in-memory log buffer used by bug reports.
  final originalDebugPrint = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) LogBuffer.instance.log(message);
    originalDebugPrint(message, wrapWidth: wrapWidth);
  };

  await CrashCapture.init();

  // Build the bug-report config once, before runApp, so the override is
  // ready when the first widget reads it.
  final prefs = await SharedPreferences.getInstance();

  // Forward declaration so the container's overrides can close over it.
  late final ProviderContainer container;

  final bugReportConfig = BugReportConfig(
    appName: 'Musicbox',
    appVersion: () async {
      try {
        final info = await PackageInfo.fromPlatform();
        return '${info.version}+${info.buildNumber}';
      } catch (_) {
        return 'unknown';
      }
    },
    webUrl: prefs.getString('bug_report_web_url'),
    appContexts: [
      AppContext(
        name: 'project-digest',
        label: 'Project digest',
        build: () async =>
            buildProjectDigest(container.read(projectProvider).value),
      ),
      AppContext(
        name: 'project-snapshot',
        label: 'Project JSON snapshot',
        sizeLimitBytes: 32 * 1024,
        build: () async {
          final p = container.read(projectProvider).value;
          return p == null ? '' : jsonEncode(p.toJson());
        },
      ),
    ],
  );

  container = ProviderContainer(
    overrides: [
      bugReportConfigProvider.overrideWithValue(bugReportConfig),
    ],
  );

  runZonedGuarded(
    () => runApp(
      UncontrolledProviderScope(
        container: container,
        child: const MusicboxApp(),
      ),
    ),
    (error, stack) => CrashCapture.recordError(error, stack),
  );
}

class MusicboxApp extends StatelessWidget {
  const MusicboxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'musicbox',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF0D0D0D),
        colorScheme: const ColorScheme.dark(
          primary: Colors.greenAccent,
          surface: Color(0xFF111111),
        ),
      ),
      home: const _RootPage(),
    );
  }
}

// ---------------------------------------------------------------------------
// Root — bottom navigation with 5 tabs
// ---------------------------------------------------------------------------

class _RootPage extends ConsumerStatefulWidget {
  const _RootPage();

  @override
  ConsumerState<_RootPage> createState() => _RootPageState();
}

class _RootPageState extends ConsumerState<_RootPage> {
  int _tab = 0;

  static const _pages = [
    SequencerPage(),
    SynthPage(),
    SamplerPage(),
    EffectsPage(),
    PadPage(),
    AiPage(),
  ];

  static const _navItems = [
    BottomNavigationBarItem(icon: Icon(Icons.grid_on),       label: 'SEQ'),
    BottomNavigationBarItem(icon: Icon(Icons.piano),         label: 'SYNTH'),
    BottomNavigationBarItem(icon: Icon(Icons.album),         label: 'SAMPLER'),
    BottomNavigationBarItem(icon: Icon(Icons.tune),          label: 'FX'),
    BottomNavigationBarItem(icon: Icon(Icons.apps),          label: 'PADS'),
    BottomNavigationBarItem(icon: Icon(Icons.auto_awesome),  label: 'AI'),
  ];

  Future<void> _exportDialog() async {
    int bars = 4;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Export WAV', style: TextStyle(color: Colors.white)),
        content: StatefulBuilder(
          builder: (ctx, setState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('How many bars?',
                style: TextStyle(color: Colors.white54, fontSize: 13)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [4, 8, 16, 32].map((n) {
                  final sel = n == bars;
                  return GestureDetector(
                    onTap: () => setState(() => bars = n),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 100),
                      margin: const EdgeInsets.symmetric(horizontal: 5),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: sel ? Colors.greenAccent : Colors.white12,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text('$n',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: sel ? Colors.black : Colors.white54,
                        )),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white38))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Export', style: TextStyle(color: Colors.greenAccent))),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Rendering…'), duration: Duration(seconds: 30)));

    final engine  = ref.read(engineProvider);
    final success = await ExportService.instance.export(engine, bars: bars);

    messenger.hideCurrentSnackBar();
    if (mounted) {
      messenger.showSnackBar(SnackBar(
        content: Text(success ? 'Export shared!' : 'Export failed.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final projectAsync = ref.watch(projectProvider);
    final projectName  = projectAsync.value?.name ?? 'musicbox';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0D),
        elevation: 0,
        title: Text(
          projectName.toLowerCase(),
          style: const TextStyle(
            fontSize: 16, letterSpacing: 3,
            fontWeight: FontWeight.w300, color: Colors.white70,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report_outlined, color: Colors.white54),
            tooltip: 'Bug report',
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => const BugReportSheet(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.file_upload_outlined, color: Colors.white54),
            tooltip: 'Export WAV',
            onPressed: _exportDialog,
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white54),
            tooltip: 'Settings',
            onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const SettingsPage())),
          ),
        ],
      ),
      body: IndexedStack(index: _tab, children: _pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab,
        onTap: (i) => setState(() => _tab = i),
        backgroundColor: const Color(0xFF111111),
        selectedItemColor: Colors.greenAccent,
        unselectedItemColor: Colors.white24,
        selectedLabelStyle: const TextStyle(
          fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1),
        unselectedLabelStyle: const TextStyle(fontSize: 9, letterSpacing: 1),
        type: BottomNavigationBarType.fixed,
        items: _navItems,
      ),
    );
  }
}
