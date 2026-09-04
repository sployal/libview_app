import 'package:flutter/material.dart';

import '../services/upload_service.dart';

/// Loads a Drive file preview through the signed-in backend proxy.
class DriveThumbnail extends StatefulWidget {
  const DriveThumbnail({
    super.key,
    required this.fileId,
    required this.fallback,
    this.fit = BoxFit.cover,
  });

  final String fileId;
  final Widget fallback;
  final BoxFit fit;

  @override
  State<DriveThumbnail> createState() => _DriveThumbnailState();
}

class _DriveThumbnailState extends State<DriveThumbnail> {
  static final Set<String> _missingIds = <String>{};
  late Future<Map<String, String>?> _headers;

  @override
  void initState() {
    super.initState();
    _headers = _loadHeaders();
  }

  @override
  void didUpdateWidget(covariant DriveThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fileId != widget.fileId) {
      _headers = _loadHeaders();
    }
  }

  Future<Map<String, String>?> _loadHeaders() async {
    if (widget.fileId.isEmpty ||
        widget.fileId.startsWith('local-') ||
        _missingIds.contains(widget.fileId)) {
      return null;
    }
    try {
      return await UploadService.instance.authHeaders();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, String>?>(
      future: _headers,
      builder: (context, snapshot) {
        final headers = snapshot.data;
        if (headers == null || headers.isEmpty) {
          return widget.fallback;
        }
        return Image.network(
          UploadService.thumbnailUrl(widget.fileId),
          key: ValueKey('thumb-${widget.fileId}'),
          fit: widget.fit,
          width: double.infinity,
          height: double.infinity,
          gaplessPlayback: true,
          cacheWidth: 400,
          headers: headers,
          errorBuilder: (_, __, ___) {
            _missingIds.add(widget.fileId);
            return widget.fallback;
          },
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded || frame != null) return child;
            return widget.fallback;
          },
        );
      },
    );
  }
}
