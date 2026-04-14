import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

const _apiKeyStorageKey = 'anthropic_api_key';
const _model            = 'claude-sonnet-4-6';
const _apiUrl           = 'https://api.anthropic.com/v1/messages';

class AiService {
  static AiService? _instance;
  AiService._();
  static AiService get instance => _instance ??= AiService._();

  final _storage = const FlutterSecureStorage();

  Future<String?> getApiKey() => _storage.read(key: _apiKeyStorageKey);
  Future<void> saveApiKey(String key) =>
      _storage.write(key: _apiKeyStorageKey, value: key);
  Future<void> clearApiKey() => _storage.delete(key: _apiKeyStorageKey);
  Future<bool> hasApiKey() async {
    final k = await getApiKey();
    return k != null && k.isNotEmpty;
  }

  // ---------------------------------------------------------------------------
  // Non-streaming request — used for tool-enabled chat turns.
  //
  // Returns the raw content block list from Claude's response so the caller
  // can handle both text blocks and tool_use blocks.
  // ---------------------------------------------------------------------------

  Future<({String text, List<Map<String, dynamic>> toolCalls, String stopReason})>
      chatRequest({
    required String systemPrompt,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> tools = const [],
  }) async {
    final key = await getApiKey();
    if (key == null || key.isEmpty) {
      throw const AiServiceException('No API key configured.');
    }

    final body = <String, dynamic>{
      'model':      _model,
      'max_tokens': 1024,
      'system':     systemPrompt,
      'messages':   messages,
    };
    if (tools.isNotEmpty) body['tools'] = tools;

    final resp = await http.post(
      Uri.parse(_apiUrl),
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

  // ---------------------------------------------------------------------------
  // Streaming request — used for text-only modes (MIX suggestions etc.)
  //
  // [messages] is the full Anthropic-format conversation history.
  // ---------------------------------------------------------------------------

  Stream<String> streamMessage({
    required String systemPrompt,
    required List<Map<String, dynamic>> messages,
  }) async* {
    final key = await getApiKey();
    if (key == null || key.isEmpty) {
      throw const AiServiceException('No API key configured.');
    }

    final request = http.Request('POST', Uri.parse(_apiUrl))
      ..headers.addAll({
        'x-api-key':         key,
        'anthropic-version': '2023-06-01',
        'content-type':      'application/json',
      })
      ..body = jsonEncode({
        'model':      _model,
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

  /// Convenience: collect full streaming response (non-streaming callers).
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
}

class AiServiceException implements Exception {
  final String message;
  const AiServiceException(this.message);
  @override
  String toString() => 'AiServiceException: $message';
}
