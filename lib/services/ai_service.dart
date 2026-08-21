import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'upload_service.dart';

class ChatMessage {
  final String role; // 'user' or 'assistant'
  final String text;
  final Uint8List? imageBytes;
  final String? imageMime;

  const ChatMessage({
    required this.role,
    required this.text,
    this.imageBytes,
    this.imageMime,
  });
}

class AiService {
  AiService._();

  static final AiService instance = AiService._();

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: UploadService.baseUrl,
      connectTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(minutes: 2),
      sendTimeout: const Duration(minutes: 2),
    ),
  );

  Future<String> sendMessage(List<ChatMessage> history) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Please sign in to use AI chat.');
    }

    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw Exception('Could not get auth token. Please sign in again.');
    }

    final payload = {
      'messages': history.map((m) {
        final map = <String, dynamic>{
          'role': m.role == 'user' ? 'user' : 'assistant',
          'content': m.text,
        };
        if (m.imageBytes != null && m.imageBytes!.isNotEmpty) {
          map['imageBase64'] = base64Encode(m.imageBytes!);
          map['imageMime'] = m.imageMime ?? 'image/jpeg';
        }
        return map;
      }).toList(),
    };

    try {
      final response = await _dio.post(
        '/ai/chat',
        data: payload,
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        ),
      );

      final reply = response.data?['reply']?.toString().trim() ?? '';
      if (reply.isEmpty) {
        throw Exception('The AI returned an empty reply. Try rephrasing.');
      }
      return reply;
    } on DioException catch (e) {
      final data = e.response?.data;
      String detail = 'AI request failed';
      if (data is Map && data['error'] != null) {
        detail = data['error'].toString();
      } else if (e.message != null && e.message!.isNotEmpty) {
        detail = e.message!;
      }
      throw Exception(detail);
    }
  }
}
