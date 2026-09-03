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
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.45),
        foregroundColor: Colors.white,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        title: title.isEmpty
            ? null
            : Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
        actions: [
          IconButton(
            tooltip: 'Save to Downloads',
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(CupertinoIcons.arrow_down_to_line),
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
          child: Center(
            child: Hero(
              tag: widget.heroTag,
              child: Image.network(
                widget.imageUrl,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const Center(
                    child: CupertinoActivityIndicator(
                      color: Colors.white,
                      radius: 14,
                    ),
                  );
                },
                errorBuilder: (_, __, ___) => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        CupertinoIcons.photo,
                        color: Colors.white54,
                        size: 48,
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Could not load image',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
