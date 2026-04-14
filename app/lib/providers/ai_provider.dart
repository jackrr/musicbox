import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/types.dart';
import '../models/project.dart';
import '../services/ai_service.dart';
import 'engine_provider.dart';
import 'project_provider.dart';
import 'sequencer_provider.dart';

// ---------------------------------------------------------------------------
// API key
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
    this.messages    = const [],
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

// ---------------------------------------------------------------------------
// Tool definitions sent to Claude
// ---------------------------------------------------------------------------

const _tools = [
  {
    'name': 'set_bpm',
    'description': 'Set the project BPM (tempo).',
    'input_schema': {
      'type': 'object',
      'properties': {
        'bpm': {'type': 'number', 'description': 'Tempo in BPM (20–300).'},
      },
      'required': ['bpm'],
    },
  },
  {
    'name': 'set_voice_param',
    'description':
        'Set a synth voice parameter for a track. Use this to change ADSR, '
        'oscillator type, or volume.',
    'input_schema': {
      'type': 'object',
      'properties': {
        'track_id': {
          'type': 'integer',
          'description': 'Track index 0–7.',
        },
        'param': {
          'type': 'string',
          'enum': ['oscType', 'attack', 'decay', 'sustain', 'release', 'volume'],
          'description':
              'oscType: 0=sine 1=saw 2=square 3=triangle 4=noise. '
              'attack/decay/release: seconds. sustain/volume: 0–1.',
        },
        'value': {'type': 'number'},
      },
      'required': ['track_id', 'param', 'value'],
    },
  },
  {
    'name': 'set_effect',
    'description':
        'Set an effect parameter for a track. reverbRoom and reverbDamp are '
        'global (apply to all tracks, track_id is ignored).',
    'input_schema': {
      'type': 'object',
      'properties': {
        'track_id': {
          'type': 'integer',
          'description': 'Track index 0–7 (ignored for reverbRoom/reverbDamp).',
        },
        'param': {
          'type': 'string',
          'enum': [
            'reverbSend', 'delaySend', 'delayTime', 'delayFeedback',
            'distDrive', 'reverbRoom', 'reverbDamp',
            'filterType', 'filterCutoff', 'filterResonance',
          ],
          'description':
              'reverbSend/delaySend/distDrive: 0–1. '
              'delayTime: 0.0625–4 (beats). delayFeedback: 0–0.95. '
              'reverbRoom/reverbDamp: 0–1 (global). '
              'filterType: 0=off 1=LP 2=HP. filterCutoff/filterResonance: 0–1.',
        },
        'value': {'type': 'number'},
      },
      'required': ['track_id', 'param', 'value'],
    },
  },
  {
    'name': 'set_step',
    'description': 'Activate or clear a single step in the sequencer grid.',
    'input_schema': {
      'type': 'object',
      'properties': {
        'track_id':  {'type': 'integer', 'description': 'Track 0–7.'},
        'step_idx':  {'type': 'integer', 'description': 'Step 0–63.'},
        'active':    {'type': 'boolean'},
        'pitch':     {'type': 'integer',
                      'description': 'MIDI note 0–127. kick=36 snare=38 hat=42.'},
        'velocity':  {'type': 'number',  'description': '0.0–1.0.'},
      },
      'required': ['track_id', 'step_idx', 'active'],
    },
  },
];

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class AiNotifier extends StateNotifier<AiState> {
  final Ref _ref;

  // Conversation history in Anthropic wire format.
  // Kept separate from the display `messages` so we can include tool_use and
  // tool_result turns without showing them as chat bubbles.
  final List<Map<String, dynamic>> _chatHistory = [];

  AiNotifier(this._ref) : super(const AiState());

  // ---------------------------------------------------------------------------
  // Context helpers
  // ---------------------------------------------------------------------------

  Map<String, dynamic> _buildContext() {
    final project = _ref.read(projectProvider).value;
    final seq     = _ref.read(sequencerProvider);
    if (project == null) return {};
    return {
      'bpm':      seq.bpm,
      'numSteps': seq.numSteps,
      'reverbRoom': project.reverbRoom,
      'reverbDamp': project.reverbDamp,
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

  String _chatSystemPrompt() => '''
You are an AI music production assistant embedded in the musicbox app.
You can directly modify the project using the provided tools.
When the user asks you to change something, use the appropriate tool immediately.
After using tools, give a short confirmation of what you changed.
Keep responses concise.

Current project state:
${jsonEncode(_buildContext())}
''';

  // ---------------------------------------------------------------------------
  // Tool execution
  // ---------------------------------------------------------------------------

  String _executeTool(String name, Map<String, dynamic> input) {
    try {
      final engine    = _ref.read(engineProvider);
      final notifier  = _ref.read(projectProvider.notifier);
      final seqNot    = _ref.read(sequencerProvider.notifier);

      switch (name) {
        case 'set_bpm': {
          final bpm = (input['bpm'] as num).toDouble();
          seqNot.setBpm(bpm);
          return 'BPM set to $bpm';
        }

        case 'set_voice_param': {
          final trackId   = input['track_id'] as int;
          final paramName = input['param'] as String;
          final value     = (input['value'] as num).toDouble();
          final param     = VoiceParam.values.firstWhere(
            (p) => p.name == paramName,
            orElse: () => throw ArgumentError('Unknown param $paramName'),
          );
          engine.setVoiceParam(trackId, param, value);
          notifier.updateVoiceParam(trackId, param, value);
          return 'Track ${trackId + 1}: $paramName = $value';
        }

        case 'set_effect': {
          final trackId   = input['track_id'] as int;
          final paramName = input['param'] as String;
          final value     = (input['value'] as num).toDouble();
          final param     = EffectParam.values.firstWhere(
            (p) => p.name == paramName,
            orElse: () => throw ArgumentError('Unknown param $paramName'),
          );
          engine.setEffect(trackId, param, value);
          // Global reverb params route to their own notifier methods
          if (param == EffectParam.reverbRoom) {
            notifier.updateReverbRoom(value);
          } else if (param == EffectParam.reverbDamp) {
            notifier.updateReverbDamp(value);
          } else {
            notifier.updateEffect(trackId, param, value);
          }
          return 'Track ${trackId + 1}: $paramName = $value';
        }

        case 'set_step': {
          final trackId  = input['track_id']  as int;
          final stepIdx  = input['step_idx']  as int;
          final active   = input['active']    as bool;
          final pitch    = (input['pitch']    as int?)    ?? 60;
          final velocity = ((input['velocity'] as num?)   ?? 0.8).toDouble();
          final step     = StepData(active: active, pitch: pitch, velocity: velocity);
          engine.setStep(trackId, stepIdx,
              active: active, pitch: pitch, velocity: velocity);
          notifier.updateStep(trackId, stepIdx, step);
          return 'Step $stepIdx on track ${trackId + 1}: active=$active pitch=$pitch';
        }

        default:
          return 'Unknown tool: $name';
      }
    } catch (e) {
      return 'Tool error: $e';
    }
  }

  // ---------------------------------------------------------------------------
  // Chat (with history + tool use)
  // ---------------------------------------------------------------------------

  Future<void> sendChat(String userText) async {
    _appendUser(userText);
    _chatHistory.add({'role': 'user', 'content': userText});

    state = state.copyWith(isStreaming: true, error: null);

    try {
      var currentMessages = List<Map<String, dynamic>>.from(_chatHistory);
      String finalText = '';

      // Multi-turn tool loop (max 4 tool rounds to avoid runaway calls)
      for (var round = 0; round < 4; round++) {
        final (:text, :toolCalls, :stopReason) = await AiService.instance.chatRequest(
          systemPrompt: _chatSystemPrompt(),
          messages:     currentMessages,
          tools:        _tools,
        );

        if (toolCalls.isEmpty) {
          finalText = text;
          break;
        }

        // Build the assistant message content (text + tool_use blocks)
        final assistantContent = <Map<String, dynamic>>[
          if (text.isNotEmpty) {'type': 'text', 'text': text},
          ...toolCalls,
        ];
        currentMessages.add({'role': 'assistant', 'content': assistantContent});

        // Execute each tool and collect results
        final toolResultContent = <Map<String, dynamic>>[];
        for (final tc in toolCalls) {
          final result = _executeTool(
            tc['name']  as String,
            (tc['input'] as Map).cast<String, dynamic>(),
          );
          toolResultContent.add({
            'type':        'tool_result',
            'tool_use_id': tc['id'],
            'content':     result,
          });
        }
        currentMessages.add({'role': 'user', 'content': toolResultContent});

        // If stop_reason wasn't tool_use, Claude is done
        if (stopReason != 'tool_use') {
          finalText = text;
          break;
        }
      }

      // Add final assistant turn to persistent history
      if (finalText.isNotEmpty) {
        _chatHistory.add({'role': 'assistant', 'content': finalText});
        _appendAssistant(finalText);
      }
    } catch (e) {
      state = state.copyWith(error: e.toString());
    } finally {
      state = state.copyWith(isStreaming: false);
    }
  }

  // ---------------------------------------------------------------------------
  // One-shot modes (PATTERN, SOUND, MIX) — no persistent history, just context
  // ---------------------------------------------------------------------------

  Future<void> generatePattern(int trackId, String userText) async {
    _appendUser(userText);
    const sys = '''
You are a step sequencer pattern generator.
Return ONLY a JSON object with this exact structure, no explanation:
{"steps": [{"active": true/false, "pitch": 0-127, "velocity": 0.0-1.0}, ...]}
The array must have exactly numSteps elements (from context).
Pitches: kick=36, snare=38, closed hat=42, open hat=46, clap=39.
''';
    try {
      final text = await AiService.instance.complete(
        systemPrompt: sys,
        messages: [
          {'role': 'user', 'content': '${jsonEncode(_buildContext())}\n\n$userText'},
        ],
      );
      final json  = jsonDecode(text) as Map<String, dynamic>;
      final steps = (json['steps'] as List).map((s) {
        final m = s as Map<String, dynamic>;
        return StepData(
          active:   m['active']   as bool,
          pitch:    m['pitch']    as int,
          velocity: (m['velocity'] as num).toDouble(),
        );
      }).toList();

      final engine  = _ref.read(engineProvider);
      final project = _ref.read(projectProvider.notifier);
      for (var i = 0; i < steps.length; i++) {
        engine.setStep(trackId, i,
            active: steps[i].active, pitch: steps[i].pitch,
            velocity: steps[i].velocity);
        project.updateStep(trackId, i, steps[i]);
      }
      _appendAssistant('Pattern applied to track ${trackId + 1}.');
    } catch (e) {
      _appendAssistant('Could not parse response: $e');
    }
  }

  Future<void> suggestSoundDesign(int trackId, String userText) async {
    _appendUser(userText);
    const sys = '''
You are a synthesizer sound design assistant.
Return ONLY a JSON object (no explanation):
{"oscType":0-4,"attack":0.001-10,"decay":0.001-10,"sustain":0-1,"release":0.001-10,"volume":0-1}
oscType: 0=sine 1=saw 2=square 3=triangle 4=noise.
''';
    try {
      final text = await AiService.instance.complete(
        systemPrompt: sys,
        messages: [
          {'role': 'user', 'content': '${jsonEncode(_buildContext())}\n\n$userText'},
        ],
      );
      final json     = jsonDecode(text) as Map<String, dynamic>;
      final engine   = _ref.read(engineProvider);
      final notifier = _ref.read(projectProvider.notifier);

      void apply(VoiceParam p, dynamic v) {
        final val = (v as num).toDouble();
        engine.setVoiceParam(trackId, p, val);
        notifier.updateVoiceParam(trackId, p, val);
      }

      if (json.containsKey('oscType'))  apply(VoiceParam.oscType,  json['oscType']);
      if (json.containsKey('attack'))   apply(VoiceParam.attack,   json['attack']);
      if (json.containsKey('decay'))    apply(VoiceParam.decay,    json['decay']);
      if (json.containsKey('sustain'))  apply(VoiceParam.sustain,  json['sustain']);
      if (json.containsKey('release'))  apply(VoiceParam.release,  json['release']);
      if (json.containsKey('volume'))   apply(VoiceParam.volume,   json['volume']);

      _appendAssistant('Sound design applied to track ${trackId + 1}.');
    } catch (e) {
      _appendAssistant('Error: $e');
    }
  }

  Future<void> getMixSuggestions(String userText) async {
    _appendUser(userText);
    await _stream(
      systemPrompt:
          'You are a mix engineer. Suggest specific level, reverb, and delay '
          'settings. Be concise and actionable.',
      userMessage: userText,
    );
  }

  // ---------------------------------------------------------------------------
  // Streaming helper (text-only, no tool use, no history)
  // ---------------------------------------------------------------------------

  Future<void> _stream({
    required String systemPrompt,
    required String userMessage,
  }) async {
    state = state.copyWith(isStreaming: true, error: null);
    final buffer = StringBuffer();
    state = state.copyWith(
      messages: [...state.messages, const AiMessage(isUser: false, text: '')],
    );
    try {
      await for (final chunk in AiService.instance.streamMessage(
        systemPrompt: systemPrompt,
        messages: [
          {
            'role':    'user',
            'content': '${jsonEncode(_buildContext())}\n\n$userMessage',
          },
        ],
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

  // ---------------------------------------------------------------------------

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

  void clearMessages() {
    _chatHistory.clear();
    state = const AiState();
  }
}

final aiProvider = StateNotifierProvider<AiNotifier, AiState>(
  (ref) => AiNotifier(ref),
);
