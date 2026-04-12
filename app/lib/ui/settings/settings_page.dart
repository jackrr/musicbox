import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/ai_provider.dart';
import '../../providers/project_provider.dart';
import '../../services/ai_service.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _keyCtrl = TextEditingController();
  bool _obscured = true;
  bool _saving   = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _loadKey();
  }

  Future<void> _loadKey() async {
    final k = await AiService.instance.getApiKey();
    if (k != null) _keyCtrl.text = k;
  }

  Future<void> _saveKey() async {
    final key = _keyCtrl.text.trim();
    if (key.isEmpty) return;
    setState(() { _saving = true; _status = null; });
    await AiService.instance.saveApiKey(key);
    ref.invalidate(hasApiKeyProvider);
    setState(() { _saving = false; _status = 'API key saved.'; });
  }

  Future<void> _clearKey() async {
    await AiService.instance.clearApiKey();
    _keyCtrl.clear();
    ref.invalidate(hasApiKeyProvider);
    setState(() => _status = 'API key cleared.');
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
            // API Key section
            const _SectionHeader('ANTHROPIC API KEY'),
            const SizedBox(height: 8),
            const Text(
              'Used for AI Assist features. Stored securely in device keychain. '
              'Never sent to any server other than api.anthropic.com.',
              style: TextStyle(fontSize: 12, color: Colors.white38, height: 1.5),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _keyCtrl,
              obscureText: _obscured,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'monospace'),
              decoration: InputDecoration(
                hintText: 'sk-ant-...',
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true,
                fillColor: Colors.white10,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: IconButton(
                  icon: Icon(_obscured ? Icons.visibility : Icons.visibility_off,
                      color: Colors.white38, size: 20),
                  onPressed: () => setState(() => _obscured = !_obscured),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    label: _saving ? 'Saving...' : 'Save Key',
                    color: Colors.greenAccent,
                    onTap: _saving ? null : _saveKey,
                  ),
                ),
                const SizedBox(width: 10),
                _ActionButton(
                  label: 'Clear',
                  color: Colors.redAccent,
                  onTap: _clearKey,
                ),
              ],
            ),
            if (_status != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_status!,
                  style: const TextStyle(fontSize: 12, color: Colors.greenAccent)),
              ),

            const SizedBox(height: 32),

            // Project section
            const _SectionHeader('PROJECT'),
            const SizedBox(height: 12),
            _ActionButton(
              label: 'New Project',
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
                      child: const Text('Cancel', style: TextStyle(color: Colors.white38))),
                    TextButton(
                      onPressed: () { Navigator.pop(context); _newProject(); },
                      child: const Text('Create', style: TextStyle(color: Colors.greenAccent))),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 10, fontWeight: FontWeight.bold,
      color: Colors.white38, letterSpacing: 2,
    ),
  );
}

class _ActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _ActionButton({required this.label, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: onTap != null ? color.withAlpha(30) : Colors.white10,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: onTap != null ? color : Colors.white10),
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
