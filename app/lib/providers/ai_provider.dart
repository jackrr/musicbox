import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/types.dart';
import '../models/project.dart';
import '../services/ai_service.dart';
import 'engine_provider.dart';
import 'project_provider.dart';
import 'sequencer_provider.dart';

// ---------------------------------------------------------------------------
// API key availability
// ---------------------------------------------------------------------------

final hasApiKeyProvider = FutureProvider<bool>((_) => AiService.instance.hasApiKey());

// ---------------------------------------------------------------------------
// AI chat state
// ---------------------------------------------------------------------------

class AiMessage {
  final bool isUser;
  final String text;
  const AiMessage({required this.isUser, required this.text});
}

class AiState {
  final List<AiMessage> messages;
  final bool isStreaming;
  final String? error;

  const AiState({
    this.messages   = const [],
    this.isStreaming = false,
    this.error,
  });

  AiState copyWith({
    List<AiMessage>? messages,
    bool? isStreaming,
    String? error,
  }) => AiState(
    messages:    messages    ?? this.messages,
    isStreaming:  isStreaming ?? this.isStreaming,
    error:        error,
  );
}

class AiNotifier extends StateNotifier<AiState> {
  final Ref _ref;
  AiNotifier(this._ref) : super(const AiState());

  Map<String, dynamic> _buildContext() {
    final project = _ref.read(projectProvider).value;
    final seq     = _ref.read(sequencerProvider);
    if (project == null) return {};
    return {
      'bpm':      seq.bpm,
      'numSteps': seq.numSteps,
      'tracks': List.generate(kNumTracks, (ti) {
        final t = project.tracks[ti];
        return {
          'id':   ti,
          'mode': t.mode.name,
          'steps': t.steps.take(seq.numSteps).map((s) => {
            'active':   s.active,
            'pitch':    s.pitch,
            'velocity': s.velocity,
          }).toList(),
          'voiceParams': t.voiceParams.toJson(),
          'effects':     t.effects.toJson(),
        };
      }),
    };
  }

  Future<void> sendChat(String userText) async {
    _appendUser(userText);
    await _stream(
      systemPrompt: 'You are a helpful music production assistant. '
          'The user is working on a beat in the musicbox app. '
          'Answer concisely.',
      userText: userText,
    );
  }

  Future<void> generatePattern(int trackId, String userText) async {
    _appendUser(userText);
    const sys = '''
You are a step sequencer pattern generator.
Return ONLY a JSON object with this exact structure, no explanation:
{
  "steps": [
    {"active": true/false, "pitch": 0-127, "velocity": 0.0-1.0},
    ...
  ]
}
The array must have exactly the same number of steps as numSteps in the context.
Pitches: kick=36, snare=38, closed hat=42, open hat=46, clap=39.
''';
    _appendUser('[generating pattern for track $trackId...]');
    try {
      final text = await AiService.instance.complete(
        systemPrompt: sys,
        userMessage:  userText,
        context:      _buildContext(),
      );
      final json = jsonDecode(text) as Map<String, dynamic>;
      final steps = (json['steps'] as List).map((s) {
        final m = s as Map<String, dynamic>;
        return StepData(
          active:   m['active'] as bool,
          pitch:    m['pitch'] as int,
          velocity: (m['velocity'] as num).toDouble(),
        );
      }).toList();
      // Apply to engine + project
      final engine  = _ref.read(engineProvider);
      final notifier = _ref.read(projectProvider.notifier);
      for (var i = 0; i < steps.length; i++) {
        engine.setStep(trackId, i,
          active: steps[i].active, pitch: steps[i].pitch, velocity: steps[i].velocity);
        notifier.updateStep(trackId, i, steps[i]);
      }
      _appendAssistant('Pattern applied to track $trackId!');
    } catch (e) {
      _appendAssistant('Could not parse response: $e');
    }
  }

  Future<void> suggestSoundDesign(int trackId, String userText) async {
    _appendUser(userText);
    const sys = '''
You are a synthesizer sound design assistant.
Return ONLY a JSON object with this exact structure, no explanation:
{
  "oscType": 0-4,
  "attack": 0.001-10.0,
  "decay": 0.001-10.0,
  "sustain": 0.0-1.0,
  "release": 0.001-10.0,
  "volume": 0.0-1.0
}
oscType: 0=sine, 1=saw, 2=square, 3=triangle, 4=noise.
''';
    try {
      final text = await AiService.instance.complete(
        systemPrompt: sys,
        userMessage:  userText,
        context:      _buildContext(),
      );
      final json = jsonDecode(text) as Map<String, dynamic>;
      final engine   = _ref.read(engineProvider);
      final notifier = _ref.read(projectProvider.notifier);

      void apply(VoiceParam p, dynamic v) {
        final val = (v as num).toDouble();
        engine.setVoiceParam(trackId, p, val);
        notifier.updateVoiceParam(trackId, p, val);
      }

      if (json.containsKey('oscType'))   apply(VoiceParam.oscType,   json['oscType']);
      if (json.containsKey('attack'))    apply(VoiceParam.attack,    json['attack']);
      if (json.containsKey('decay'))     apply(VoiceParam.decay,     json['decay']);
      if (json.containsKey('sustain'))   apply(VoiceParam.sustain,   json['sustain']);
      if (json.containsKey('release'))   apply(VoiceParam.release,   json['release']);
      if (json.containsKey('volume'))    apply(VoiceParam.volume,    json['volume']);

      _appendAssistant('Sound design applied to track $trackId!');
    } catch (e) {
      _appendAssistant('Error: $e');
    }
  }

  Future<void> getMixSuggestions(String userText) async {
    _appendUser(userText);
    await _stream(
      systemPrompt: 'You are a mix engineer. Suggest specific level, '
          'EQ, reverb, and delay settings. Be concise and actionable.',
      userText: userText,
    );
  }

  Future<void> _stream({
    required String systemPrompt,
    required String userText,
  }) async {
    state = state.copyWith(isStreaming: true, error: null);
    final buffer = StringBuffer();
    state = state.copyWith(
      messages: [...state.messages, const AiMessage(isUser: false, text: '')],
    );
    try {
      await for (final chunk in AiService.instance.streamMessage(
        systemPrompt: systemPrompt,
        userMessage:  userText,
        context:      _buildContext(),
      )) {
        buffer.write(chunk);
        final updated = List<AiMessage>.from(state.messages);
        updated[updated.length - 1] =
            AiMessage(isUser: false, text: buffer.toString());
        state = state.copyWith(messages: updated);
      }
    } catch (e) {
      state = state.copyWith(error: e.toString());
    } finally {
      state = state.copyWith(isStreaming: false);
    }
  }

  void _appendUser(String text) {
    state = state.copyWith(
      messages: [...state.messages, AiMessage(isUser: true, text: text)],
    );
  }

  void _appendAssistant(String text) {
    state = state.copyWith(
      messages: [...state.messages, AiMessage(isUser: false, text: text)],
    );
  }

  void clearMessages() => state = const AiState();
}

final aiProvider = StateNotifierProvider<AiNotifier, AiState>(
  (ref) => AiNotifier(ref),
);
