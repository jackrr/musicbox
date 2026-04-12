import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/ai_provider.dart';
import '../../providers/project_provider.dart';

class AiPage extends ConsumerStatefulWidget {
  const AiPage({super.key});

  @override
  ConsumerState<AiPage> createState() => _AiPageState();
}

class _AiPageState extends ConsumerState<AiPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _textCtrl  = TextEditingController();
  final _scrollCtrl = ScrollController();

  int _selectedTrack = 0;

  static const _tabLabels = ['CHAT', 'PATTERN', 'SOUND', 'MIX'];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;
    _textCtrl.clear();

    final notifier = ref.read(aiProvider.notifier);
    switch (_tabs.index) {
      case 0:
        await notifier.sendChat(text);
      case 1:
        await notifier.generatePattern(_selectedTrack, text);
      case 2:
        await notifier.suggestSoundDesign(_selectedTrack, text);
      case 3:
        await notifier.getMixSuggestions(text);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final aiState   = ref.watch(aiProvider);
    final hasKey    = ref.watch(hasApiKeyProvider).value ?? false;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(
        child: Column(
          children: [
            // Mode tabs
            TabBar(
              controller: _tabs,
              labelColor: Colors.greenAccent,
              unselectedLabelColor: Colors.white38,
              indicatorColor: Colors.greenAccent,
              labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
              tabs: _tabLabels.map((l) => Tab(text: l)).toList(),
            ),

            // Track selector (for Pattern + Sound tabs)
            AnimatedBuilder(
              animation: _tabs,
              builder: (context, child) {
                if (_tabs.index != 1 && _tabs.index != 2) return const SizedBox.shrink();
                return _buildTrackSelector();
              },
            ),

            // No key banner
            if (!hasKey)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                color: Colors.orange.withAlpha(40),
                child: const Text(
                  'No API key — go to Settings to add your Anthropic API key.',
                  style: TextStyle(fontSize: 12, color: Colors.orange),
                  textAlign: TextAlign.center,
                ),
              ),

            // Messages
            Expanded(
              child: ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.all(12),
                itemCount: aiState.messages.length,
                itemBuilder: (_, i) => _MessageBubble(msg: aiState.messages[i]),
              ),
            ),

            if (aiState.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  aiState.error!,
                  style: const TextStyle(fontSize: 11, color: Colors.redAccent),
                ),
              ),

            // Input row
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textCtrl,
                      enabled: hasKey && !aiState.isStreaming,
                      onSubmitted: (_) => _send(),
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: hasKey ? 'Ask Claude...' : 'Add API key in Settings',
                        hintStyle: const TextStyle(color: Colors.white24),
                        filled: true,
                        fillColor: Colors.white10,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: (hasKey && !aiState.isStreaming) ? _send : null,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: (hasKey && !aiState.isStreaming)
                            ? Colors.greenAccent
                            : Colors.white10,
                        shape: BoxShape.circle,
                      ),
                      child: aiState.isStreaming
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.send, size: 20,
                              color: Colors.black),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrackSelector() {
    final project = ref.watch(projectProvider).value;
    if (project == null) return const SizedBox.shrink();
    return SizedBox(
      height: 36,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        itemCount: project.tracks.length,
        itemBuilder: (_, i) {
          final sel = i == _selectedTrack;
          return GestureDetector(
            onTap: () => setState(() => _selectedTrack = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: sel ? Colors.greenAccent : Colors.white10,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'T${i + 1}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: sel ? Colors.black : Colors.white54,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final AiMessage msg;
  const _MessageBubble({required this.msg});

  @override
  Widget build(BuildContext context) => Align(
    alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.8,
      ),
      decoration: BoxDecoration(
        color: msg.isUser ? Colors.greenAccent.withAlpha(30) : Colors.white10,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: msg.isUser ? Colors.greenAccent.withAlpha(80) : Colors.white12,
        ),
      ),
      child: Text(
        msg.text,
        style: const TextStyle(fontSize: 14, color: Colors.white, height: 1.4),
      ),
    ),
  );
}
