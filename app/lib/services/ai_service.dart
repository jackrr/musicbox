import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

const _anthropicApiKeyStorageKey = 'anthropic_api_key';
const _providerTypeStorageKey    = 'ai_provider_type';
const _openaiBaseUrlStorageKey   = 'ai_openai_base_url';
const _openaiApiKeyStorageKey    = 'ai_openai_api_key';
const _openaiModelStorageKey     = 'ai_openai_model';

const _anthropicModel  = 'claude-sonnet-4-6';
const _anthropicApiUrl = 'https://api.anthropic.com/v1/messages';

class OpenAICompatConfig {
  final String baseUrl;
  final String apiKey;
  final String model;
  const OpenAICompatConfig({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
  });
}

class AiService {
  static AiService? _instance;
  AiService._();
  static AiService get instance => _instance ??= AiService._();

  final _storage = const FlutterSecureStorage();

  // ---------------------------------------------------------------------------
  // Provider type
  // ---------------------------------------------------------------------------

  Future<String> getProviderType() async {
    return await _storage.read(key: _providerTypeStorageKey) ?? 'anthropic';
  }

  Future<void> saveProviderType(String type) =>
      _storage.write(key: _providerTypeStorageKey, value: type);

  // ---------------------------------------------------------------------------
  // Anthropic credentials
  // ---------------------------------------------------------------------------

  Future<String?> getApiKey() => _storage.read(key: _anthropicApiKeyStorageKey);
  Future<void> saveApiKey(String key) =>
      _storage.write(key: _anthropicApiKeyStorageKey, value: key);
  Future<void> clearApiKey() => _storage.delete(key: _anthropicApiKeyStorageKey);

  // ---------------------------------------------------------------------------
  // OpenAI-compat credentials
  // ---------------------------------------------------------------------------

  Future<OpenAICompatConfig?> getOpenAICompatConfig() async {
    final baseUrl = await _storage.read(key: _openaiBaseUrlStorageKey);
    final apiKey  = await _storage.read(key: _openaiApiKeyStorageKey);
    final model   = await _storage.read(key: _openaiModelStorageKey);
    if (baseUrl == null || baseUrl.isEmpty ||
        apiKey  == null || apiKey.isEmpty  ||
        model   == null || model.isEmpty) {
      return null;
    }
    return OpenAICompatConfig(baseUrl: baseUrl, apiKey: apiKey, model: model);
  }

  Future<void> saveOpenAICompatConfig(OpenAICompatConfig config) async {
    await _storage.write(key: _openaiBaseUrlStorageKey, value: config.baseUrl);
    await _storage.write(key: _openaiApiKeyStorageKey,  value: config.apiKey);
    await _storage.write(key: _openaiModelStorageKey,   value: config.model);
  }

  Future<void> clearOpenAICompatConfig() async {
    await _storage.delete(key: _openaiBaseUrlStorageKey);
    await _storage.delete(key: _openaiApiKeyStorageKey);
    await _storage.delete(key: _openaiModelStorageKey);
  }

  // ---------------------------------------------------------------------------
  // Generic "is a provider configured?" check (used by hasApiKeyProvider)
  // ---------------------------------------------------------------------------

  Future<bool> hasApiKey() async {
    final type = await getProviderType();
    if (type == 'openai_compat') {
      final cfg = await getOpenAICompatConfig();
      return cfg != null;
    }
    final k = await getApiKey();
    return k != null && k.isNotEmpty;
  }

  // ---------------------------------------------------------------------------
  // Non-streaming request — used for tool-enabled chat turns.
  //
  // [messages] and [tools] are in Anthropic wire format.
  // Returns the same Anthropic-format (text, toolCalls, stopReason) regardless
  // of which provider is active, so callers need no changes.
  // ---------------------------------------------------------------------------

  Future<({String text, List<Map<String, dynamic>> toolCalls, String stopReason})>
      chatRequest({
    required String systemPrompt,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> tools = const [],
  }) async {
    final type = await getProviderType();
    if (type == 'openai_compat') {
      final cfg = await getOpenAICompatConfig();
      if (cfg == null) throw const AiServiceException('OpenAI-compat provider not configured.');
      return _openaiChatRequest(
        config: cfg,
        systemPrompt: systemPrompt,
        messages: messages,
        tools: tools,
      );
    }
    return _anthropicChatRequest(
      systemPrompt: systemPrompt,
      messages: messages,
      tools: tools,
    );
  }

  // ---------------------------------------------------------------------------
  // Streaming request — text-only, used for MIX suggestions etc.
  // ---------------------------------------------------------------------------

  Stream<String> streamMessage({
    required String systemPrompt,
    required List<Map<String, dynamic>> messages,
  }) async* {
    final type = await getProviderType();
    if (type == 'openai_compat') {
      final cfg = await getOpenAICompatConfig();
      if (cfg == null) throw const AiServiceException('OpenAI-compat provider not configured.');
      yield* _openaiStreamMessage(
        config: cfg,
        systemPrompt: systemPrompt,
        messages: messages,
      );
      return;
    }
    yield* _anthropicStreamMessage(systemPrompt: systemPrompt, messages: messages);
  }

  /// Convenience: collect full streaming response.
  Future<String> complete({
    required String systemPrompt,
    required List<Map<String, dynamic>> messages,
  }) async {
    final buffer = StringBuffer();
    await for (final chunk in streamMessage(
        systemPrompt: systemPrompt, messages: messages)) {
      buffer.write(chunk);
    }
    return buffer.toString();
  }

  // ---------------------------------------------------------------------------
  // Anthropic implementation
  // ---------------------------------------------------------------------------

  Future<({String text, List<Map<String, dynamic>> toolCalls, String stopReason})>
      _anthropicChatRequest({
    required String systemPrompt,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> tools = const [],
  }) async {
    final key = await getApiKey();
    if (key == null || key.isEmpty) {
      throw const AiServiceException('No Anthropic API key configured.');
    }

    final body = <String, dynamic>{
      'model':      _anthropicModel,
      'max_tokens': 1024,
      'system':     systemPrompt,
      'messages':   messages,
    };
    if (tools.isNotEmpty) body['tools'] = tools;

    final resp = await http.post(
      Uri.parse(_anthropicApiUrl),
      headers: {
        'x-api-key':         key,
        'anthropic-version': '2023-06-01',
        'content-type':      'application/json',
      },
      body: jsonEncode(body),
    );

    if (resp.statusCode != 200) {
      throw AiServiceException('API error ${resp.statusCode}: ${resp.body}');
    }

    final json       = jsonDecode(resp.body) as Map<String, dynamic>;
    final content    = (json['content'] as List).cast<Map<String, dynamic>>();
    final stopReason = (json['stop_reason'] as String?) ?? '';

    final text = content
        .where((b) => b['type'] == 'text')
        .map((b) => b['text'] as String)
        .join('');

    final toolCalls = content
        .where((b) => b['type'] == 'tool_use')
        .toList();

    return (text: text, toolCalls: toolCalls, stopReason: stopReason);
  }

  Stream<String> _anthropicStreamMessage({
    required String systemPrompt,
    required List<Map<String, dynamic>> messages,
  }) async* {
    final key = await getApiKey();
    if (key == null || key.isEmpty) {
      throw const AiServiceException('No Anthropic API key configured.');
    }

    final request = http.Request('POST', Uri.parse(_anthropicApiUrl))
      ..headers.addAll({
        'x-api-key':         key,
        'anthropic-version': '2023-06-01',
        'content-type':      'application/json',
      })
      ..body = jsonEncode({
        'model':      _anthropicModel,
        'max_tokens': 1024,
        'stream':     true,
        'system':     systemPrompt,
        'messages':   messages,
      });

    final response = await http.Client().send(request);
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw AiServiceException('API error ${response.statusCode}: $body');
    }

    final stream = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final line in stream) {
      if (!line.startsWith('data: ')) continue;
      final data = line.substring(6);
      if (data == '[DONE]') break;
      try {
        final json = jsonDecode(data) as Map<String, dynamic>;
        if (json['type'] == 'content_block_delta') {
          final delta = json['delta'] as Map<String, dynamic>?;
          if (delta?['type'] == 'text_delta') {
            yield delta!['text'] as String;
          }
        }
      } catch (_) {}
    }
  }

  // ---------------------------------------------------------------------------
  // OpenAI-compat implementation
  // ---------------------------------------------------------------------------

  /// Convert Anthropic-format message history to OpenAI chat messages.
  List<Map<String, dynamic>> _toOAIMessages(
    String systemPrompt,
    List<Map<String, dynamic>> messages,
  ) {
    final result = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt},
    ];

    for (final msg in messages) {
      final role    = msg['role'] as String;
      final content = msg['content'];

      if (role == 'user') {
        if (content is String) {
          result.add({'role': 'user', 'content': content});
        } else if (content is List) {
          // Tool-result blocks — each becomes a separate "tool" message.
          for (final block in content.cast<Map<String, dynamic>>()) {
            if (block['type'] == 'tool_result') {
              result.add({
                'role':         'tool',
                'tool_call_id': block['tool_use_id'],
                'content':      block['content'] as String? ?? '',
              });
            }
          }
        }
      } else if (role == 'assistant') {
        if (content is String) {
          result.add({'role': 'assistant', 'content': content});
        } else if (content is List) {
          final blocks   = content.cast<Map<String, dynamic>>();
          final textParts = blocks
              .where((b) => b['type'] == 'text')
              .map((b) => b['text'] as String)
              .join('');
          final toolUses = blocks
              .where((b) => b['type'] == 'tool_use')
              .toList();

          final Map<String, dynamic> assistantMsg = {
            'role':    'assistant',
            'content': textParts.isEmpty ? null : textParts,
          };
          if (toolUses.isNotEmpty) {
            assistantMsg['tool_calls'] = toolUses.map((b) => {
              'id':   b['id'],
              'type': 'function',
              'function': {
                'name':      b['name'],
                'arguments': jsonEncode(b['input']),
              },
            }).toList();
          }
          result.add(assistantMsg);
        }
      }
    }

    return result;
  }

  /// Convert Anthropic-format tool schemas to OpenAI function-tool format.
  List<Map<String, dynamic>> _toOAITools(List<Map<String, dynamic>> tools) {
    return tools.map((t) => {
      'type': 'function',
      'function': {
        'name':        t['name'],
        'description': t['description'] ?? '',
        'parameters':  t['input_schema'],
      },
    }).toList();
  }

  Future<({String text, List<Map<String, dynamic>> toolCalls, String stopReason})>
      _openaiChatRequest({
    required OpenAICompatConfig config,
    required String systemPrompt,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> tools = const [],
  }) async {
    final oaiMessages = _toOAIMessages(systemPrompt, messages);
    final oaiTools    = _toOAITools(tools);

    final body = <String, dynamic>{
      'model':      config.model,
      'max_tokens': 1024,
      'messages':   oaiMessages,
    };
    if (oaiTools.isNotEmpty) body['tools'] = oaiTools;

    final resp = await http.post(
      Uri.parse('${config.baseUrl}/v1/chat/completions'),
      headers: {
        'Authorization': 'Bearer ${config.apiKey}',
        'Content-Type':  'application/json',
      },
      body: jsonEncode(body),
    );

    if (resp.statusCode != 200) {
      throw AiServiceException('API error ${resp.statusCode}: ${resp.body}');
    }

    final json       = jsonDecode(resp.body) as Map<String, dynamic>;
    final choice     = (json['choices'] as List)[0] as Map<String, dynamic>;
    final message    = choice['message'] as Map<String, dynamic>;
    final finishReason = choice['finish_reason'] as String? ?? 'stop';

    final text         = message['content'] as String? ?? '';
    final oaiToolCalls = (message['tool_calls'] as List?)
            ?.cast<Map<String, dynamic>>() ??
        [];

    // Convert OpenAI tool_calls → Anthropic tool_use blocks.
    final toolCalls = oaiToolCalls.map((tc) {
      final fn = tc['function'] as Map<String, dynamic>;
      dynamic input = <String, dynamic>{};
      try {
        input = jsonDecode(fn['arguments'] as String);
      } catch (_) {}
      return <String, dynamic>{
        'type':  'tool_use',
        'id':    tc['id'],
        'name':  fn['name'],
        'input': input,
      };
    }).toList();

    final stopReason = finishReason == 'tool_calls' ? 'tool_use' : 'end_turn';
    return (text: text, toolCalls: toolCalls, stopReason: stopReason);
  }

  Stream<String> _openaiStreamMessage({
    required OpenAICompatConfig config,
    required String systemPrompt,
    required List<Map<String, dynamic>> messages,
  }) async* {
    final oaiMessages = _toOAIMessages(systemPrompt, messages);

    final request = http.Request(
      'POST',
      Uri.parse('${config.baseUrl}/v1/chat/completions'),
    )
      ..headers.addAll({
        'Authorization': 'Bearer ${config.apiKey}',
        'Content-Type':  'application/json',
      })
      ..body = jsonEncode({
        'model':      config.model,
        'max_tokens': 1024,
        'stream':     true,
        'messages':   oaiMessages,
      });

    final response = await http.Client().send(request);
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw AiServiceException('API error ${response.statusCode}: $body');
    }

    final stream = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final line in stream) {
      if (!line.startsWith('data: ')) continue;
      final data = line.substring(6).trim();
      if (data == '[DONE]') break;
      try {
        final json    = jsonDecode(data) as Map<String, dynamic>;
        final choices = json['choices'] as List?;
        final delta   = (choices?.first as Map<String, dynamic>?)?['delta']
            as Map<String, dynamic>?;
        final content = delta?['content'] as String?;
        if (content != null && content.isNotEmpty) { yield content; }
      } catch (_) {}
    }
  }
}

class AiServiceException implements Exception {
  final String message;
  const AiServiceException(this.message);
  @override
  String toString() => 'AiServiceException: $message';
}
