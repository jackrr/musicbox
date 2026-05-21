import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../bug_report/bug_report_config.dart';
import '../../providers/ai_provider.dart';
import '../../providers/project_provider.dart';
import '../../services/ai_service.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  // Anthropic
  final _anthropicKeyCtrl = TextEditingController();
  bool _obscureAnthropicKey = true;

  // OpenAI-compat
  final _openaiUrlCtrl   = TextEditingController();
  final _openaiKeyCtrl   = TextEditingController();
  final _openaiModelCtrl = TextEditingController();
  bool _obscureOpenaiKey = true;

  // Shared
  String _providerType = 'anthropic';
  bool   _saving       = false;
  String? _aiStatus;

  // Bug report
  final _bugReportUrlCtrl = TextEditingController();
  String? _bugReportStatus;

  @override
  void initState() {
    super.initState();
    _loadAiConfig();
    _loadBugReportUrl();
  }

  @override
  void dispose() {
    _anthropicKeyCtrl.dispose();
    _openaiUrlCtrl.dispose();
    _openaiKeyCtrl.dispose();
    _openaiModelCtrl.dispose();
    _bugReportUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAiConfig() async {
    final type = await AiService.instance.getProviderType();
    final k    = await AiService.instance.getApiKey();
    final oai  = await AiService.instance.getOpenAICompatConfig();
    if (!mounted) return;
    setState(() {
      _providerType = type;
      if (k != null) _anthropicKeyCtrl.text = k;
      if (oai != null) {
        _openaiUrlCtrl.text   = oai.baseUrl;
        _openaiKeyCtrl.text   = oai.apiKey;
        _openaiModelCtrl.text = oai.model;
      }
    });
  }

  Future<void> _loadBugReportUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final url   = prefs.getString('bug_report_web_url');
    if (url != null && mounted) _bugReportUrlCtrl.text = url;
  }

  Future<void> _saveBugReportUrl() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('bug_report_web_url', _bugReportUrlCtrl.text.trim());
    setState(() => _bugReportStatus = 'Saved.');
  }

  Future<void> _saveAiConfig() async {
    setState(() { _saving = true; _aiStatus = null; });
    try {
      await AiService.instance.saveProviderType(_providerType);
      if (_providerType == 'openai_compat') {
        await AiService.instance.saveOpenAICompatConfig(OpenAICompatConfig(
          baseUrl: _openaiUrlCtrl.text.trim(),
          apiKey:  _openaiKeyCtrl.text.trim(),
          model:   _openaiModelCtrl.text.trim(),
        ));
      } else {
        final key = _anthropicKeyCtrl.text.trim();
        if (key.isNotEmpty) await AiService.instance.saveApiKey(key);
      }
      ref.invalidate(hasApiKeyProvider);
      setState(() => _aiStatus = 'Saved.');
    } finally {
      setState(() => _saving = false);
    }
  }

  Future<void> _clearAiConfig() async {
    await AiService.instance.clearApiKey();
    await AiService.instance.clearOpenAICompatConfig();
    _anthropicKeyCtrl.clear();
    _openaiUrlCtrl.clear();
    _openaiKeyCtrl.clear();
    _openaiModelCtrl.clear();
    ref.invalidate(hasApiKeyProvider);
    setState(() => _aiStatus = 'Cleared.');
  }

  Future<void> _newProject() async {
    await ref.read(projectProvider.notifier).newProject();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Settings',
            style: TextStyle(fontSize: 16, letterSpacing: 2, fontWeight: FontWeight.w300)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // AI provider section
            const _SectionHeader('AI PROVIDER'),
            const SizedBox(height: 12),

            // Provider selector
            Row(
              children: [
                _ProviderChip(
                  label: 'Anthropic',
                  selected: _providerType == 'anthropic',
                  onTap: () => setState(() { _providerType = 'anthropic'; _aiStatus = null; }),
                ),
                const SizedBox(width: 8),
                _ProviderChip(
                  label: 'OpenAI-compat',
                  selected: _providerType == 'openai_compat',
                  onTap: () => setState(() { _providerType = 'openai_compat'; _aiStatus = null; }),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (_providerType == 'anthropic') ...[
              const Text(
                'API key stored securely in device keychain. '
                'Only sent to api.anthropic.com.',
                style: TextStyle(fontSize: 12, color: Colors.white38, height: 1.5),
              ),
              const SizedBox(height: 10),
              _obscurableField(
                controller: _anthropicKeyCtrl,
                hint: 'sk-ant-…',
                obscured: _obscureAnthropicKey,
                onToggle: () => setState(() => _obscureAnthropicKey = !_obscureAnthropicKey),
              ),
            ] else ...[
              const Text(
                'Connect to any OpenAI-compatible API (Ollama, vLLM, etc.). '
                'Credentials stored securely in device keychain.',
                style: TextStyle(fontSize: 12, color: Colors.white38, height: 1.5),
              ),
              const SizedBox(height: 10),
              _labelledField(_openaiUrlCtrl,   'Base URL',   'http://…:11434'),
              const SizedBox(height: 8),
              _obscurableField(
                controller: _openaiKeyCtrl,
                hint: 'Bearer token',
                obscured: _obscureOpenaiKey,
                onToggle: () => setState(() => _obscureOpenaiKey = !_obscureOpenaiKey),
              ),
              const SizedBox(height: 8),
              _labelledField(_openaiModelCtrl, 'Model',      'llama3.2'),
            ],

            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    label: _saving ? 'Saving…' : 'Save',
                    color: Colors.greenAccent,
                    onTap: _saving ? null : _saveAiConfig,
                  ),
                ),
                const SizedBox(width: 10),
                _ActionButton(
                  label: 'Clear',
                  color: Colors.redAccent,
                  onTap: _clearAiConfig,
                ),
              ],
            ),
            if (_aiStatus != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_aiStatus!,
                    style: const TextStyle(fontSize: 12, color: Colors.greenAccent)),
              ),

            const SizedBox(height: 32),

            // Project section
            const _SectionHeader('PROJECT'),
            const SizedBox(height: 12),
            _ActionButton(
              label: 'New Project',
              key: const ValueKey('settings.newProject'),
              color: Colors.white54,
              onTap: () => showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  backgroundColor: const Color(0xFF1A1A1A),
                  title: const Text('New Project',
                      style: TextStyle(color: Colors.white)),
                  content: const Text(
                    'Current project will be saved. Start a new blank project?',
                    style: TextStyle(color: Colors.white54)),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel',
                            style: TextStyle(color: Colors.white38))),
                    TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _newProject();
                        },
                        child: const Text('Create',
                            style: TextStyle(color: Colors.greenAccent))),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Bug report section
            const _SectionHeader('BUG REPORT'),
            const SizedBox(height: 8),
            const Text(
              'URL opened from the snackbar after copying a bug report. '
              'Optional — paste a URL only if you have somewhere to send reports.',
              style: TextStyle(fontSize: 12, color: Colors.white38, height: 1.5),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bugReportUrlCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'https://…',
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true,
                fillColor: Colors.white10,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => _saveBugReportUrl(),
            ),
            const SizedBox(height: 8),
            _ActionButton(
              label: 'Save URL',
              color: Colors.white54,
              onTap: _saveBugReportUrl,
            ),
            if (_bugReportStatus != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_bugReportStatus!,
                    style: const TextStyle(fontSize: 12, color: Colors.greenAccent)),
              ),
            Builder(builder: (ctx) {
              try {
                ref.watch(bugReportConfigProvider);
              } catch (_) {}
              return const SizedBox.shrink();
            }),
          ],
        ),
      ),
    );
  }

  Widget _labelledField(
    TextEditingController ctrl,
    String label,
    String hint,
  ) =>
      TextField(
        controller: ctrl,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white24),
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white38, fontSize: 12),
          filled: true,
          fillColor: Colors.white10,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
        ),
      );

  Widget _obscurableField({
    required TextEditingController controller,
    required String hint,
    required bool obscured,
    required VoidCallback onToggle,
  }) =>
      TextField(
        controller: controller,
        obscureText: obscured,
        style: const TextStyle(
            color: Colors.white, fontSize: 13, fontFamily: 'monospace'),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white24),
          filled: true,
          fillColor: Colors.white10,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          suffixIcon: IconButton(
            icon: Icon(
                obscured ? Icons.visibility : Icons.visibility_off,
                color: Colors.white38,
                size: 20),
            onPressed: onToggle,
          ),
        ),
      );
}

class _ProviderChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ProviderChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? Colors.greenAccent.withAlpha(30) : Colors.white10,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? Colors.greenAccent : Colors.white24,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: selected ? Colors.greenAccent : Colors.white38,
            ),
          ),
        ),
      );
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Colors.white38,
          letterSpacing: 2,
        ),
      );
}

class _ActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _ActionButton({
    super.key,
    required this.label,
    required this.color,
    this.onTap,
  });

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
