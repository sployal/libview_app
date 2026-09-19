import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/download_service.dart';
import '../services/upload_service.dart';

/// Full-screen Drive image with next/previous among files in the same folder.
class DriveImagePreview extends StatefulWidget {
  const DriveImagePreview({
    super.key,
    required this.fileId,
    required this.title,
    required this.onBack,
    this.subject,
    this.onPrevious,
    this.onNext,
    this.index = 0,
    this.total = 1,
  });

  final String fileId;
  final String title;
  final String? subject;
  final VoidCallback onBack;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final int index;
  final int total;

  @override
  State<DriveImagePreview> createState() => _DriveImagePreviewState();
}

class _DriveImagePreviewState extends State<DriveImagePreview> {
  static const _darkBg = Color(0xFF111827);
  static const _lightBg = Color(0xFFE8EEF5);

  final TransformationController _transform = TransformationController();
  late Future<Map<String, String>?> _headers;
  bool _downloading = false;
  double _downloadProgress = 0;
  String? _activeDownloadFileId;
  bool _tabTickersEnabled = true;
  TapDownDetails? _doubleTapDetails;
  int _gesturePointerCount = 0;
  double _gestureStartScale = 1;

  bool get _hasGallery => widget.total > 1;
  bool get _canPrevious => widget.onPrevious != null;
  bool get _canNext => widget.onNext != null;

  @override
  void initState() {
    super.initState();
    _headers = _loadHeaders();
  }

  @override
  void didUpdateWidget(covariant DriveImagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fileId != widget.fileId) {
      _transform.value = Matrix4.identity();
      _headers = _loadHeaders();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tickersEnabled = TickerMode.of(context);
    if (_tabTickersEnabled && !tickersEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onBack();
      });
    }
    _tabTickersEnabled = tickersEnabled;
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  Future<Map<String, String>?> _loadHeaders() async {
    if (widget.fileId.isEmpty || widget.fileId.startsWith('local-')) {
      return null;
    }
    try {
      return await UploadService.instance.authHeaders();
    } catch (_) {
      return null;
    }
  }

  double _bottomNavInset(BuildContext context) {
    return MediaQuery.viewPaddingOf(context).bottom +
        kBottomNavigationBarHeight;
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
    _transform.value = Matrix4.identity()
      ..translate(-position.dx * 1.5, -position.dy * 1.5)
      ..scale(2.5);
  }

  Future<void> _downloadFile() async {
    if (_downloading) return;
    setState(() {
      _downloading = true;
      _downloadProgress = 0;
      _activeDownloadFileId = widget.fileId;
    });

    final result = await DownloadService.downloadFile(
      fileId: widget.fileId,
      subject: widget.subject ?? 'Unknown',
      onProgress: (progress) {
        if (!mounted) return;
        setState(() => _downloadProgress = progress);
      },
    );

    if (!mounted) return;
    setState(() {
      _downloading = false;
      _activeDownloadFileId = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.success
            ? const Color(0xFF10B981)
            : result.cancelled
                ? const Color(0xFF6B7280)
                : const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _cancelDownload() {
    final fileId = _activeDownloadFileId;
    if (fileId == null) return;
    DownloadService.cancelDownload(fileId);
  }

  void _goPrevious() {
    if (!_canPrevious) return;
    HapticFeedback.selectionClick();
    widget.onPrevious!();
  }

  void _goNext() {
    if (!_canNext) return;
    HapticFeedback.selectionClick();
    widget.onNext!();
  }

  void _onInteractionStart(ScaleStartDetails details) {
    _gesturePointerCount = details.pointerCount;
    _gestureStartScale = _transform.value.getMaxScaleOnAxis();
  }

  void _onInteractionUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount > _gesturePointerCount) {
      _gesturePointerCount = details.pointerCount;
    }
  }

  void _onInteractionEnd(ScaleEndDetails details) {
    final wasPinch = _gesturePointerCount > 1;
    final startScale = _gestureStartScale;
    _gesturePointerCount = 0;
    _gestureStartScale = 1;

    if (!_hasGallery || wasPinch) return;
    if (startScale > 1.05) return;
    if (_transform.value.getMaxScaleOnAxis() > 1.05) return;

    final velocity = details.velocity.pixelsPerSecond.dx;
    if (velocity < -420) {
      _goNext();
    } else if (velocity > 420) {
      _goPrevious();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark ? _darkBg : _lightBg;
    final titleColor =
        isDark ? const Color(0xFFF9FAFB) : const Color(0xFF111827);
    final muted = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
    final card = isDark ? const Color(0xFF1F2937) : Colors.white;
    final positionLabel = widget.total > 0
        ? '${widget.index + 1} of ${widget.total}'
        : '';

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        foregroundColor: titleColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: widget.onBack,
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: titleColor,
                fontSize: 16,
              ),
            ),
            if (_hasGallery)
              Text(
                positionLabel,
                style: TextStyle(color: muted, fontSize: 12),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              _downloading ? Icons.close_rounded : Icons.download_rounded,
            ),
            color: _downloading ? const Color(0xFFEF4444) : null,
            tooltip: _downloading ? 'Cancel download' : 'Download',
            onPressed: _downloading ? _cancelDownload : _downloadFile,
          ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.only(bottom: _bottomNavInset(context)),
        child: Stack(
          children: [
            FutureBuilder<Map<String, String>?>(
              future: _headers,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return _loading(muted);
                }
                final headers = snapshot.data;
                if (headers == null || headers.isEmpty) {
                  return _message(
                    muted,
                    'Could not load this image',
                    Icons.broken_image_outlined,
                  );
                }
                return InteractiveViewer(
                  transformationController: _transform,
                  minScale: 1,
                  maxScale: 5,
                  panEnabled: true,
                  scaleEnabled: true,
                  onInteractionStart: _onInteractionStart,
                  onInteractionUpdate: _onInteractionUpdate,
                  onInteractionEnd: _onInteractionEnd,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onDoubleTapDown: (details) => _doubleTapDetails = details,
                    onDoubleTap: _onDoubleTap,
                    child: Center(
                      child: Image.network(
                        UploadService.mediaStreamUrl(widget.fileId),
                        key: ValueKey('image-${widget.fileId}'),
                        fit: BoxFit.contain,
                        headers: headers,
                        gaplessPlayback: true,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return _loading(muted);
                        },
                        errorBuilder: (_, __, ___) => _message(
                          muted,
                          'Could not load this image',
                          Icons.broken_image_outlined,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            if (_hasGallery) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: _NavButton(
                  icon: Icons.chevron_left_rounded,
                  enabled: _canPrevious,
                  tooltip: 'Previous image',
                  onTap: _goPrevious,
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: _NavButton(
                  icon: Icons.chevron_right_rounded,
                  enabled: _canNext,
                  tooltip: 'Next image',
                  onTap: _goNext,
                ),
              ),
            ],
            if (_downloading)
              Container(
                color: Colors.black54,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    margin: const EdgeInsets.symmetric(horizontal: 32),
                    decoration: BoxDecoration(
                      color: card,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.downloading_rounded,
                          size: 48,
                          color: Color(0xFF6366F1),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Downloading...',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: titleColor,
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: 200,
                          child: LinearProgressIndicator(
                            value: _downloadProgress,
                            backgroundColor: const Color(0xFFCBD5E1),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Color(0xFF6366F1),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${(_downloadProgress * 100).toInt()}%',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: muted,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextButton.icon(
                          onPressed: _cancelDownload,
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Color(0xFFEF4444),
                          ),
                          label: const Text(
                            'Cancel',
                            style: TextStyle(
                              color: Color(0xFFEF4444),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _loading(Color muted) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
          ),
          const SizedBox(height: 16),
          Text('Loading...', style: TextStyle(color: muted, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _message(Color muted, String text, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: muted),
          const SizedBox(height: 12),
          Text(text, style: TextStyle(color: muted, fontSize: 16)),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.enabled,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.black.withValues(alpha: enabled ? 0.45 : 0.18),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? onTap : null,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(
                icon,
                color: Colors.white.withValues(alpha: enabled ? 1 : 0.35),
                size: 32,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
