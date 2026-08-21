import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class ChatMessage {
  final String role; // 'user' or 'model'
  final String text;

  const ChatMessage({required this.role, required this.text});
}

class AiService {
  static const String _model = 'gemini-2.0-flash';
  static const String _systemInstruction =
      'You are UniStudy AI, a helpful university study assistant. '
      'Answer clearly and concisely. Help with coursework, exam prep, '
      'explanations, summaries, and study planning. If a question is '
      'outside academics, still be helpful but keep a study-focused tone.';

  static String get apiKey {
    final key = dotenv.env['GEMINI_API_KEY'] ?? '';
    if (key.isEmpty) {
      throw StateError(
        'GEMINI_API_KEY is missing from .env. Add your Gemini API key to use the AI chat.',
      );
    }
    return key;
  }

  static Future<String> sendMessage(List<ChatMessage> history) async {
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent?key=${apiKey}',
    );

    final contents = history
        .where((m) => m.text.trim().isNotEmpty)
        .map((m) => {
              'role': m.role == 'user' ? 'user' : 'model',
              'parts': [
                {'text': m.text},
              ],
            })
        .toList();

    final body = jsonEncode({
      'systemInstruction': {
        'parts': [
          {'text': _systemInstruction},
        ],
      },
      'contents': contents,
      'generationConfig': {
        'temperature': 0.7,
        'maxOutputTokens': 2048,
      },
    });

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    if (response.statusCode != 200) {
      String detail = 'Request failed (${response.statusCode})';
      try {
        final error = jsonDecode(response.body);
        detail = error['error']?['message']?.toString() ?? detail;
      } catch (_) {}
      throw Exception(detail);
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = data['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) {
      throw Exception('No response from AI. Try again.');
    }

    final parts = candidates.first['content']?['parts'] as List<dynamic>?;
    final text = parts
            ?.map((p) => p['text']?.toString() ?? '')
            .join()
            .trim() ??
        '';

    if (text.isEmpty) {
      throw Exception('The AI returned an empty reply. Try rephrasing.');
    }

    return text;
  }
}
