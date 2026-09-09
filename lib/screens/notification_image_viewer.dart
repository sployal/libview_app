import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/download_service.dart';

class NotificationImageViewer extends StatefulWidget {
  const NotificationImageViewer({
    super.key,
    required this.imageUrl,
    required this.heroTag,
    this.title,
  });

  final String imageUrl;
  final String heroTag;
  final String? title;

  @override
  State<NotificationImageViewer> createState() =>
      _NotificationImageViewerState();
}

class _NotificationImageViewerState extends State<NotificationImageViewer> {
  final TransformationController _transform = TransformationController();
  bool _saving = false;
  TapDownDetails? _doubleTapDetails;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _onDoubleTap() {
    final position = _doubleTapDetails?.localPosition;
    final current = _transform.value.getMaxScaleOnAxis();
    if (current > 1.05) {
      _transform.value = Matrix4.identity();
      return;
    }
    if (position == null) {
      _transform.value = Matrix4.identity()..scale(2.5);
      return;
    }
    final zoomed = Matrix4.identity()
      ..translate(-position.dx * 1.5, -position.dy * 1.5)
      ..scale(2.5);
    _transform.value = zoomed;
  }

  String _fileName() {
    final uri = Uri.tryParse(widget.imageUrl);
    final last = uri?.pathSegments.isNotEmpty == true
        ? uri!.pathSegments.last
        : '';
    if (last.isNotEmpty && last.contains('.')) {
      return last.split('?').first;
    }
    return 'notification_${DateTime.now().millisecondsSinceEpoch}.jpg';
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final result = await DownloadService.downloadFromUrl(
      url: widget.imageUrl,
      fileName: _fileName(),
      subject: 'Notifications',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor:
            result.success ? const Color(0xFF10B981) : const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = (widget.title ?? '').trim();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background =
        isDark ? const Color(0xFF111827) : const Color(0xFFE8EEF5);
    final titleColor =
        isDark ? const Color(0xFFF9FAFB) : const Color(0xFF111827);
    final muted = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        foregroundColor: titleColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle:
            isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        title: title.isEmpty
            ? null
            : Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: titleColor,
                ),
              ),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            style: TextButton.styleFrom(foregroundColor: titleColor),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_saving ? 'Saving…' : 'Save'),
                const SizedBox(width: 6),
                _saving
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: titleColor,
                        ),
                      )
                    : const Icon(CupertinoIcons.arrow_down_to_line, size: 20),
              ],
            ),
          ),
        ],
      ),
      body: GestureDetector(
        onDoubleTapDown: (details) => _doubleTapDetails = details,
        onDoubleTap: _onDoubleTap,
        child: InteractiveViewer(
          transformationController: _transform,
          minScale: 1,
          maxScale: 5,
          constrained: true,
          child: Center(
            child: Hero(
              tag: widget.heroTag,
              child: Image.network(
                widget.imageUrl,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return Center(
                    child: CupertinoActivityIndicator(
                      color: muted,
                      radius: 14,
                    ),
                  );
                },
                errorBuilder: (_, __, ___) => Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        CupertinoIcons.photo,
                        color: muted,
                        size: 48,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Could not load image',
                        style: TextStyle(color: muted),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        color: background,
        elevation: 0,
        padding: EdgeInsets.zero,
        height: 40,
        child: const SizedBox.shrink(),
      ),
    );
  }
}
