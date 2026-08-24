import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/ai_conversation_store.dart';
import '../services/ai_service.dart';

class AiScreen extends StatefulWidget {
  const AiScreen({super.key});

  @override
  State<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends State<AiScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  final _store = AiConversationStore.instance;
  Uint8List? _pendingImage;
  String? _pendingImageMime;
  bool _isSending = false;
  late String _conversationId;
  String _conversationTitle = 'New conversation';

  @override
  void initState() {
    super.initState();
    _conversationId = _store.newId();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    if (_isSending) return;

    if (Platform.isAndroid) {
      final status = await Permission.camera.request();
      if (!status.isGranted && !status.isLimited) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Camera permission is needed to take a photo.'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        return;
      }
    }

    final photo = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 95,
    );
    if (photo == null) return;
    await _cropAndAttach(photo.path);
  }

  Future<void> _browseFiles() async {
    if (_isSending) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
      dialogTitle: 'Attach an image',
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    var path = file.path;
    if (path == null || path.isEmpty) {
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) return;
      final dir = await getTemporaryDirectory();
      path =
          '${dir.path}/ai_pick_${DateTime.now().millisecondsSinceEpoch}.${file.extension ?? 'jpg'}';
      await File(path).writeAsBytes(bytes, flush: true);
    }

    await _cropAndAttach(path);
  }

  Future<void> _cropAndAttach(String sourcePath) async {
    CroppedFile? cropped;
    try {
      cropped = await ImageCropper().cropImage(
        sourcePath: sourcePath,
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 90,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop image',
            toolbarColor: const Color(0xFF6366F1),
            toolbarWidgetColor: Colors.white,
            activeControlsWidgetColor: const Color(0xFF6366F1),
            initAspectRatio: CropAspectRatioPreset.original,
            lockAspectRatio: false,
            aspectRatioPresets: const [
              CropAspectRatioPreset.original,
              CropAspectRatioPreset.square,
              CropAspectRatioPreset.ratio4x3,
              CropAspectRatioPreset.ratio16x9,
            ],
          ),
          IOSUiSettings(
            title: 'Crop image',
            aspectRatioPresets: const [
              CropAspectRatioPreset.original,
              CropAspectRatioPreset.square,
              CropAspectRatioPreset.ratio4x3,
              CropAspectRatioPreset.ratio16x9,
            ],
          ),
        ],
      );
    } catch (_) {
      cropped = null;
    }

    if (cropped == null) return;

    final bytes = await File(cropped.path).readAsBytes();
    if (bytes.isEmpty) return;

    const maxBytes = 4 * 1024 * 1024;
    if (bytes.length > maxBytes) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please choose an image smaller than 4 MB.'),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    if (!mounted) return;
    setState(() {
      _pendingImage = bytes;
      _pendingImageMime = 'image/jpeg';
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    final image = _pendingImage;
    final imageMime = _pendingImageMime;
    if ((text.isEmpty && image == null) || _isSending) return;

    setState(() {
      _messages.add(ChatMessage(
        role: 'user',
        text: text,
        imageBytes: image,
        imageMime: imageMime,
      ));
      _isSending = true;
      _pendingImage = null;
      _pendingImageMime = null;
    });
    _controller.clear();
    _scrollToBottom();
    await _persistConversation();

    try {
      final reply = await AiService.instance.sendMessage(_messages);
      if (!mounted) return;
      setState(() {
        _messages.add(ChatMessage(role: 'assistant', text: reply));
      });
      await _persistConversation();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.removeLast();
        _controller.text = text;
        _pendingImage = image;
        _pendingImageMime = imageMime;
      });
      if (_messages.isEmpty) {
        await _store.delete(_conversationId);
      } else {
        await _persistConversation();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _persistConversation() async {
    if (_messages.isEmpty) return;
    final saved = await _store.save(
      id: _conversationId,
      messages: List<ChatMessage>.from(_messages),
    );
    if (!mounted) return;
    setState(() {
      _conversationTitle = saved.title;
    });
  }

  Future<void> _startNewConversation({bool persistCurrent = true}) async {
    if (_isSending) return;
    if (persistCurrent && _messages.isNotEmpty) {
      await _persistConversation();
    }
    if (!mounted) return;
    setState(() {
      _messages.clear();
      _pendingImage = null;
      _pendingImageMime = null;
      _conversationId = _store.newId();
      _conversationTitle = 'New conversation';
    });
  }

  Future<void> _openConversation(String id) async {
    if (_isSending) return;
    if (_messages.isNotEmpty) {
      await _persistConversation();
    }
    final conversation = await _store.load(id);
    if (!mounted || conversation == null) return;
    setState(() {
      _conversationId = conversation.id;
      _conversationTitle = conversation.title;
      _messages
        ..clear()
        ..addAll(conversation.messages);
      _pendingImage = null;
      _pendingImageMime = null;
    });
    _scrollToBottom();
  }

  Future<void> _deleteConversation(String id) async {
    await _store.delete(id);
    if (!mounted) return;
    if (id == _conversationId) {
      await _startNewConversation(persistCurrent: false);
    }
  }

  Future<void> _confirmDelete(AiConversationSummary item) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete conversation?'),
          content: Text(
            '“${item.title}” will be removed from this device. This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (shouldDelete == true) {
      await _deleteConversation(item.id);
    }
  }

  Future<void> _showHistory() async {
    if (_isSending) return;
    if (_messages.isNotEmpty) {
      await _persistConversation();
    }
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return _ConversationHistorySheet(
          currentId: _conversationId,
          onNew: () {
            Navigator.pop(sheetContext);
            _startNewConversation();
          },
          onOpen: (id) {
            Navigator.pop(sheetContext);
            if (id != _conversationId) {
              _openConversation(id);
            }
          },
          onDelete: (item) async {
            await _confirmDelete(item);
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? const Color(0xFF818CF8) : const Color(0xFF6366F1);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Study AI',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              _messages.isEmpty ? 'Stored on this device' : _conversationTitle,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'New conversation',
            onPressed: _isSending ? null : () => _startNewConversation(),
            icon: const Icon(Icons.add_comment_outlined),
          ),
          IconButton(
            tooltip: 'Conversations',
            onPressed: _isSending ? null : () => _showHistory(),
            icon: const Icon(Icons.history_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? _EmptyState(accent: accent, isDark: isDark)
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    itemCount: _messages.length + (_isSending ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _messages.length) {
                        return _TypingBubble(accent: accent, isDark: isDark);
                      }
                      return _ChatBubble(
                        message: _messages[index],
                        accent: accent,
                        isDark: isDark,
                      );
                    },
                  ),
          ),
          _Composer(
            controller: _controller,
            isSending: _isSending,
            accent: accent,
            isDark: isDark,
            pendingImage: _pendingImage,
            onTakePhoto: _takePhoto,
            onBrowseFiles: _browseFiles,
            onClearImage: () {
              setState(() {
                _pendingImage = null;
                _pendingImageMime = null;
              });
            },
            onSend: _send,
          ),
        ],
      ),
    );
  }
}

class _ConversationHistorySheet extends StatefulWidget {
  const _ConversationHistorySheet({
    required this.currentId,
    required this.onNew,
    required this.onOpen,
    required this.onDelete,
  });

  final String currentId;
  final VoidCallback onNew;
  final ValueChanged<String> onOpen;
  final Future<void> Function(AiConversationSummary item) onDelete;

  @override
  State<_ConversationHistorySheet> createState() =>
      _ConversationHistorySheetState();
}

class _ConversationHistorySheetState extends State<_ConversationHistorySheet> {
  late Future<List<AiConversationSummary>> _future;

  @override
  void initState() {
    super.initState();
    _future = AiConversationStore.instance.list();
  }

  void _reload() {
    setState(() {
      _future = AiConversationStore.instance.list();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Conversations',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: widget.onNew,
                    icon: const Icon(Icons.add_comment_outlined),
                    label: const Text('New'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                'Chats are stored only on this device. Open an old one, start a new chat, or delete any you no longer need.',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark
                      ? const Color(0xFF9CA3AF)
                      : const Color(0xFF6B7280),
                ),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<AiConversationSummary>>(
                future: _future,
                builder: (context, snapshot) {
                  final conversations =
                      snapshot.data ?? const <AiConversationSummary>[];
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (conversations.isEmpty) {
                    return Center(
                      child: Text(
                        'No saved conversations yet.',
                        style: TextStyle(
                          color: isDark
                              ? const Color(0xFF9CA3AF)
                              : const Color(0xFF6B7280),
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: conversations.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = conversations[index];
                      final isCurrent = item.id == widget.currentId;
                      return ListTile(
                        leading: Icon(
                          isCurrent
                              ? Icons.chat_bubble_rounded
                              : Icons.chat_bubble_outline_rounded,
                          color: isCurrent ? const Color(0xFF6366F1) : null,
                        ),
                        title: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          item.preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        selected: isCurrent,
                        trailing: IconButton(
                          tooltip: 'Delete conversation',
                          icon: const Icon(Icons.delete_outline_rounded),
                          onPressed: () async {
                            await widget.onDelete(item);
                            if (mounted) _reload();
                          },
                        ),
                        onTap: () => widget.onOpen(item.id),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.accent, required this.isDark});

  final Color accent;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: accent.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.auto_awesome_rounded, size: 40, color: accent),
            ),
            const SizedBox(height: 20),
            Text(
              'Ask UniStudy AI',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: isDark ? const Color(0xFFF9FAFB) : const Color(0xFF1F2937),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Ask a question, snap a photo of your notes, or attach an image. Conversations stay on this device — start a new chat, reopen old ones, or delete any you choose.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.message,
    required this.accent,
    required this.isDark,
  });

  final ChatMessage message;
  final Color accent;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? accent
              : (isDark ? const Color(0xFF1F2937) : Colors.white),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.2 : 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.imageBytes != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(
                  message.imageBytes!,
                  width: 220,
                  fit: BoxFit.cover,
                ),
              ),
              if (message.text.isNotEmpty) const SizedBox(height: 8),
            ],
            if (message.text.isNotEmpty)
              Text(
                message.text,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.4,
                  color: isUser
                      ? Colors.white
                      : (isDark ? const Color(0xFFF9FAFB) : const Color(0xFF1F2937)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble({required this.accent, required this.isDark});

  final Color accent;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1F2937) : Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(16),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: accent,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Thinking…',
              style: TextStyle(
                color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.isSending,
    required this.accent,
    required this.isDark,
    required this.pendingImage,
    required this.onTakePhoto,
    required this.onBrowseFiles,
    required this.onClearImage,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool isSending;
  final Color accent;
  final bool isDark;
  final Uint8List? pendingImage;
  final VoidCallback onTakePhoto;
  final VoidCallback onBrowseFiles;
  final VoidCallback onClearImage;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1F2937) : Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.3 : 0.06),
              blurRadius: 12,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (pendingImage != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        pendingImage!,
                        height: 72,
                        width: 72,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: GestureDetector(
                        onTap: isSending ? null : onClearImage,
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(2),
                          child: const Icon(
                            Icons.close_rounded,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                IconButton(
                  tooltip: 'Take photo',
                  onPressed: isSending ? null : onTakePhoto,
                  icon: Icon(Icons.photo_camera_outlined, color: accent),
                ),
                Expanded(
                  child: TextField(
                    controller: controller,
                    enabled: !isSending,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onSend(),
                    decoration: InputDecoration(
                      hintText: 'Ask a study question…',
                      prefixIcon: IconButton(
                        tooltip: 'Browse files',
                        onPressed: isSending ? null : onBrowseFiles,
                        icon: Icon(
                          Icons.attach_file_rounded,
                          color: accent,
                        ),
                      ),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 44,
                        minHeight: 44,
                      ),
                      filled: true,
                      fillColor: isDark
                          ? const Color(0xFF111827)
                          : const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: accent,
                  child: IconButton(
                    onPressed: isSending ? null : onSend,
                    icon: Icon(
                      isSending ? Icons.hourglass_top_rounded : Icons.send_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
