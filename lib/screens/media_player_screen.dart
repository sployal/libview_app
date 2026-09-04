import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../services/download_service.dart';
import '../services/upload_service.dart';

class MediaPlayerScreen extends StatefulWidget {
  const MediaPlayerScreen({
    super.key,
    required this.fileId,
    required this.title,
    required this.isAudio,
    this.subject,
    this.onBack,
  });

  final String fileId;
  final String title;
  final bool isAudio;
  final String? subject;
  final VoidCallback? onBack;

  @override
  State<MediaPlayerScreen> createState() => _MediaPlayerScreenState();
}

class _MediaPlayerScreenState extends State<MediaPlayerScreen> {
  VideoPlayerController? _controller;
  bool _loading = true;
  String? _status;
  String? _error;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  bool _showControls = true;

  static const _darkBg = Color(0xFF111827);
  static const _lightBg = Color(0xFFF8FAFC);

  bool get _usePlatformView =>
      !widget.isAudio &&
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void dispose() {
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    setState(() {
      _loading = true;
      _error = null;
      _status = 'Loading...';
    });
    try {
      final headers = await UploadService.instance.authHeaders();
      await _startController(
        VideoPlayerController.networkUrl(
          Uri.parse(UploadService.mediaStreamUrl(widget.fileId)),
          httpHeaders: headers,
          viewType: _usePlatformView
              ? VideoViewType.platformView
              : VideoViewType.textureView,
        ),
      );
      return;
    } catch (_) {}

    if (widget.isAudio) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not play this audio file';
      });
      return;
    }

    try {
      setState(() => _status = 'Preparing a local copy...');
      final path = await _cacheForPlayback();
      if (!mounted) return;
      await _startController(
        VideoPlayerController.file(
          File(path),
          viewType: _usePlatformView
              ? VideoViewType.platformView
              : VideoViewType.textureView,
        ),
      );
      return;
    } catch (_) {}

    try {
      setState(() => _status = 'Opening in the phone player...');
      await _openInSystemPlayer();
      if (!mounted) return;
      _handleBack();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not play this video on this phone';
      });
    }
  }

  Future<void> _startController(VideoPlayerController controller) async {
    try {
      await controller.initialize();
      if (controller.value.hasError) {
        throw StateError(controller.value.errorDescription ?? 'decode failed');
      }
      controller.addListener(_onTick);
      await controller.play();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _controller?.removeListener(_onTick);
        _controller?.dispose();
        _controller = controller;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      controller.dispose();
      rethrow;
    }
  }

  void _onTick() {
    final controller = _controller;
    if (controller == null || !mounted) return;
    if (controller.value.hasError && _error == null) {
      setState(() {
        _error = widget.isAudio
            ? 'Could not play this audio file'
            : 'Could not play this video on this phone';
      });
      return;
    }
    setState(() {});
  }

  Future<String> _cacheForPlayback() async {
    final headers = await UploadService.instance.authHeaders();
    final dir = await getTemporaryDirectory();
    final safe = widget.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final path = '${dir.path}/play_${widget.fileId}_$safe';
    final file = File(path);
    if (await file.exists() && await file.length() > 0) {
      return path;
    }
    await Dio().download(
      UploadService.mediaStreamUrl(widget.fileId),
      path,
      options: Options(
        headers: headers,
        receiveTimeout: const Duration(minutes: 20),
      ),
    );
    return path;
  }

  Future<void> _openInSystemPlayer() async {
    final path = await _cacheForPlayback();
    final result = await OpenFile.open(
      path,
      type: widget.isAudio ? 'audio/*' : 'video/*',
    );
    if (result.type != ResultType.done) {
      throw Exception(result.message);
    }
  }

  void _handleBack() {
    if (widget.onBack != null) {
      widget.onBack!();
      return;
    }
    Navigator.maybePop(context);
  }

  Future<void> _downloadFile() async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
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
    setState(() => _isDownloading = false);
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
    DownloadService.cancelDownload(widget.fileId);
  }

  double _bottomNavInset(BuildContext context) {
    return MediaQuery.viewPaddingOf(context).bottom +
        kBottomNavigationBarHeight;
  }

  String _formatDuration(Duration value) {
    final two = (int n) => n.toString().padLeft(2, '0');
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60);
    final seconds = value.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${two(minutes)}:${two(seconds)}';
    }
    return '${two(minutes)}:${two(seconds)}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark ? _darkBg : _lightBg;
    final titleColor =
        isDark ? const Color(0xFFF9FAFB) : const Color(0xFF111827);
    final muted = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;

    return Scaffold(
      backgroundColor: widget.isAudio ? background : Colors.black,
      appBar: AppBar(
        backgroundColor: widget.isAudio ? background : Colors.black,
        foregroundColor: widget.isAudio ? titleColor : Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: _handleBack,
        ),
        title: Text(
          widget.title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: widget.isAudio ? titleColor : Colors.white,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isDownloading ? Icons.close_rounded : Icons.download_rounded,
            ),
            color: _isDownloading ? const Color(0xFFEF4444) : null,
            onPressed: _isDownloading ? _cancelDownload : _downloadFile,
            tooltip: _isDownloading ? 'Cancel download' : 'Download',
          ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.only(bottom: _bottomNavInset(context)),
        child: _loading
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      color: widget.isAudio
                          ? const Color(0xFF6366F1)
                          : Colors.white,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _status ?? 'Loading...',
                      style: TextStyle(color: muted),
                    ),
                  ],
                ),
              )
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            widget.isAudio
                                ? Icons.audiotrack_rounded
                                : Icons.videocam_off_rounded,
                            size: 48,
                            color: muted,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: titleColor, fontSize: 16),
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: _prepare,
                            child: const Text('Try again'),
                          ),
                          if (!widget.isAudio) ...[
                            const SizedBox(height: 10),
                            TextButton(
                              onPressed: () async {
                                setState(() {
                                  _loading = true;
                                  _error = null;
                                  _status = 'Opening in the phone player...';
                                });
                                try {
                                  await _openInSystemPlayer();
                                  if (mounted) _handleBack();
                                } catch (_) {
                                  if (!mounted) return;
                                  setState(() {
                                    _loading = false;
                                    _error =
                                        'Could not open this video in another app';
                                  });
                                }
                              },
                              child: const Text('Open in phone player'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                : widget.isAudio
                    ? _audioBody(
                        controller: controller!,
                        titleColor: titleColor,
                        muted: muted,
                      )
                    : _videoBody(controller: controller!, ready: ready),
      ),
    );
  }

  Widget _videoBody({
    required VideoPlayerController controller,
    required bool ready,
  }) {
    return GestureDetector(
      onTap: () => setState(() => _showControls = !_showControls),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: Colors.black,
            child: ready
                ? Center(
                    child: AspectRatio(
                      aspectRatio: controller.value.aspectRatio == 0
                          ? 16 / 9
                          : controller.value.aspectRatio,
                      child: VideoPlayer(controller),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          if (_showControls || !controller.value.isPlaying)
            _controlsOverlay(controller, light: false),
        ],
      ),
    );
  }

  Widget _audioBody({
    required VideoPlayerController controller,
    required Color titleColor,
    required Color muted,
  }) {
    return Column(
      children: [
        const Spacer(),
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            color: const Color(0xFFEC4899).withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(32),
          ),
          child: const Icon(
            Icons.audiotrack_rounded,
            size: 56,
            color: Color(0xFFEC4899),
          ),
        ),
        const SizedBox(height: 28),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Text(
            widget.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: titleColor,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const Spacer(),
        _controlsOverlay(controller, light: true, muted: muted),
        const SizedBox(height: 28),
      ],
    );
  }

  Widget _controlsOverlay(
    VideoPlayerController controller, {
    required bool light,
    Color? muted,
  }) {
    final duration = controller.value.duration;
    final position = controller.value.position;
    final playing = controller.value.isPlaying;
    final maxMs = duration.inMilliseconds <= 0 ? 1 : duration.inMilliseconds;
    final value = position.inMilliseconds.clamp(0, maxMs).toDouble();
    final dim = muted ?? (light ? const Color(0xFF6B7280) : Colors.white70);

    return Align(
      alignment: Alignment.bottomCenter,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: light
              ? null
              : const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black54],
                ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 28, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: () {
                  if (playing) {
                    controller.pause();
                  } else {
                    controller.play();
                  }
                },
                iconSize: 56,
                color: light ? const Color(0xFFEC4899) : Colors.white,
                icon: Icon(
                  playing
                      ? Icons.pause_circle_filled_rounded
                      : Icons.play_circle_filled_rounded,
                ),
              ),
              Slider(
                value: value,
                max: maxMs.toDouble(),
                activeColor: light ? const Color(0xFFEC4899) : Colors.white,
                inactiveColor: dim.withValues(alpha: 0.35),
                onChanged: (next) {
                  controller.seekTo(Duration(milliseconds: next.round()));
                },
              ),
              Row(
                children: [
                  Text(
                    _formatDuration(position),
                    style: TextStyle(color: dim, fontSize: 12),
                  ),
                  const Spacer(),
                  Text(
                    _formatDuration(duration),
                    style: TextStyle(color: dim, fontSize: 12),
                  ),
                ],
              ),
              if (_isDownloading) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: _downloadProgress > 0 ? _downloadProgress : null,
                  color: const Color(0xFF6366F1),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
