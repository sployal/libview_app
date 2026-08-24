import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'ai_service.dart';

class AiConversationSummary {
  final String id;
  final String title;
  final DateTime updatedAt;
  final String preview;

  const AiConversationSummary({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.preview,
  });

  factory AiConversationSummary.fromJson(Map<String, dynamic> json) {
    return AiConversationSummary(
      id: json['id'] as String,
      title: (json['title'] as String?)?.trim().isNotEmpty == true
          ? json['title'] as String
          : 'New conversation',
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      preview: json['preview'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'updatedAt': updatedAt.toIso8601String(),
        'preview': preview,
      };
}

class AiConversation {
  final String id;
  final String title;
  final DateTime updatedAt;
  final List<ChatMessage> messages;

  const AiConversation({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.messages,
  });
}

class AiConversationStore {
  AiConversationStore._();

  static final AiConversationStore instance = AiConversationStore._();

  static const _indexFileName = 'index.json';

  Future<Directory> _root() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/ai_conversations');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> _indexFile() async {
    final root = await _root();
    return File('${root.path}/$_indexFileName');
  }

  Future<Directory> _conversationDir(String id, {bool create = true}) async {
    final root = await _root();
    final dir = Directory('${root.path}/$id');
    if (create && !await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<List<AiConversationSummary>> list() async {
    try {
      final file = await _indexFile();
      if (!await file.exists()) return [];
      final decoded = json.decode(await file.readAsString());
      if (decoded is! List) return [];
      final items = decoded
          .whereType<Map>()
          .map((e) => AiConversationSummary.fromJson(
                Map<String, dynamic>.from(e),
              ))
          .toList();
      items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return items;
    } catch (_) {
      return [];
    }
  }

  Future<AiConversation?> load(String id) async {
    try {
      final dir = await _conversationDir(id, create: false);
      final file = File('${dir.path}/conversation.json');
      if (!await file.exists()) return null;
      final map = json.decode(await file.readAsString()) as Map<String, dynamic>;
      final messagesJson = map['messages'] as List? ?? [];
      final messages = <ChatMessage>[];
      for (final raw in messagesJson) {
        if (raw is! Map) continue;
        final item = Map<String, dynamic>.from(raw);
        Uint8List? imageBytes;
        final imageFileName = item['imageFile'] as String?;
        if (imageFileName != null && imageFileName.isNotEmpty) {
          final imageFile = File('${dir.path}/$imageFileName');
          if (await imageFile.exists()) {
            imageBytes = await imageFile.readAsBytes();
          }
        }
        messages.add(ChatMessage(
          role: item['role'] as String? ?? 'user',
          text: item['text'] as String? ?? '',
          imageBytes: imageBytes,
          imageMime: item['imageMime'] as String?,
        ));
      }
      return AiConversation(
        id: map['id'] as String? ?? id,
        title: map['title'] as String? ?? 'New conversation',
        updatedAt: DateTime.tryParse(map['updatedAt'] as String? ?? '') ??
            DateTime.now(),
        messages: messages,
      );
    } catch (_) {
      return null;
    }
  }

  Future<AiConversation> save({
    required String id,
    required List<ChatMessage> messages,
    String? title,
  }) async {
    final dir = await _conversationDir(id);
    final now = DateTime.now();
    final resolvedTitle = (title != null && title.trim().isNotEmpty)
        ? title.trim()
        : _titleFromMessages(messages);

    final serialized = <Map<String, dynamic>>[];
    for (var i = 0; i < messages.length; i++) {
      final message = messages[i];
      String? imageFile;
      if (message.imageBytes != null && message.imageBytes!.isNotEmpty) {
        imageFile = 'image_$i.jpg';
        await File('${dir.path}/$imageFile').writeAsBytes(
          message.imageBytes!,
          flush: true,
        );
      }
      serialized.add({
        'role': message.role,
        'text': message.text,
        if (imageFile != null) 'imageFile': imageFile,
        if (message.imageMime != null) 'imageMime': message.imageMime,
      });
    }

    final conversation = {
      'id': id,
      'title': resolvedTitle,
      'updatedAt': now.toIso8601String(),
      'messages': serialized,
    };
    await File('${dir.path}/conversation.json').writeAsString(
      json.encode(conversation),
      flush: true,
    );

    final summaries = await list();
    summaries.removeWhere((item) => item.id == id);
    summaries.insert(
      0,
      AiConversationSummary(
        id: id,
        title: resolvedTitle,
        updatedAt: now,
        preview: _previewFromMessages(messages),
      ),
    );
    final index = await _indexFile();
    await index.writeAsString(
      json.encode(summaries.map((e) => e.toJson()).toList()),
      flush: true,
    );

    return AiConversation(
      id: id,
      title: resolvedTitle,
      updatedAt: now,
      messages: messages,
    );
  }

  Future<void> delete(String id) async {
    final root = await _root();
    final dir = Directory('${root.path}/$id');
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    final summaries = await list();
    summaries.removeWhere((item) => item.id == id);
    final index = await _indexFile();
    await index.writeAsString(
      json.encode(summaries.map((e) => e.toJson()).toList()),
      flush: true,
    );
  }

  String newId() => DateTime.now().millisecondsSinceEpoch.toString();

  static String _titleFromMessages(List<ChatMessage> messages) {
    for (final message in messages) {
      final text = message.text.trim();
      if (text.isNotEmpty) {
        return text.length > 48 ? '${text.substring(0, 48)}…' : text;
      }
      if (message.imageBytes != null) return 'Photo question';
    }
    return 'New conversation';
  }

  static String _previewFromMessages(List<ChatMessage> messages) {
    for (final message in messages.reversed) {
      final text = message.text.trim();
      if (text.isNotEmpty) {
        return text.length > 80 ? '${text.substring(0, 80)}…' : text;
      }
    }
    return 'No messages yet';
  }
}
