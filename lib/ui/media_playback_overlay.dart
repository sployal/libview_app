import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../services/download_service.dart';
import '../services/media_session.dart';
import 'drive_thumbnail.dart';

/// Full-screen and popped-out players. Shown only while [MediaSession] is
/// active, which the client files browser is the only starter of.
class MediaPlaybackOverlay extends StatefulWidget {
  const MediaPlaybackOverlay({super.key});

  @override
  State<MediaPlaybackOverlay> createState() => _MediaPlaybackOverlayState();
}

class _MediaPlaybackOverlayState extends State<MediaPlaybackOverlay>
    with SingleTickerProviderStateMixin {
  final Map<String, double> _downloadProgress = {};
  final Set<String> _downloading = {};
  late final AnimationController _equalizer;
  Offset? _miniOffset;
  bool? _miniWasAudio;

  @override
  void initState() {
    super.initState();
    _equalizer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    MediaSession.instance.addListener(_onSession);
    MediaSession.instance.playing.addListener(_onPlaying);
  }

  @override
  void dispose() {
    MediaSession.instance.removeListener(_onSession);
    MediaSession.instance.playing.removeListener(_onPlaying);
    _equalizer.dispose();
    super.dispose();
  }

  void _onPlaying() {
    final session = MediaSession.instance;
    final animate = session.active &&
        session.current?.isAudio == true &&
        session.playing.value;
    if (animate) {
      if (!_equalizer.isAnimating) _equalizer.repeat();
    } else {
      _equalizer.stop();
    }
    if (mounted) setState(() {});
  }

  void _onSession() {
    final session = MediaSession.instance;
    if (!session.active) {
      _miniOffset = null;
    }
    final isAudio = session.current?.isAudio;
    if (_miniWasAudio != null && isAudio != null && isAudio != _miniWasAudio) {
      _miniOffset = null;
    }
    _miniWasAudio = isAudio;
    _onPlaying();
  }

  double _bottomClearance(BuildContext context) {
    final padding = MediaQuery.paddingOf(context).bottom;
    final view = MediaQuery.viewPaddingOf(context).bottom;
    // The shell already counts the bottom bar in padding. Don't add it again.
    if (padding > view) return padding;
    return view + kBottomNavigationBarHeight;
  }

  Future<void> _downloadCurrent() async {
    final item = MediaSession.instance.current;
    if (item == null) return;
    if (_downloading.contains(item.id)) {
      DownloadService.cancelDownload(item.id);
      setState(() => _downloading.remove(item.id));
      return;
    }
    setState(() {
      _downloading.add(item.id);
      _downloadProgress[item.id] = 0;
    });
    final result = await DownloadService.downloadFile(
      fileId: item.id,
      subject: item.subject,
      onProgress: (progress) {
        if (!mounted) return;
        setState(() => _downloadProgress[item.id] = progress);
      },
    );
    if (!mounted) return;
    setState(() => _downloading.remove(item.id));
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

  Future<void> _showQueue() async {
    final session = MediaSession.instance;
    if (!session.active || session.queue.isEmpty) return;
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _QueueSheet(session: session),
    );
    if (picked == null || picked == session.index) return;
    HapticFeedback.selectionClick();
    await session.playAt(picked);
  }

  Future<void> _pickMode() async {
    final session = MediaSession.instance;
    final picked = await showModalBottomSheet<PlaybackRepeatMode>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _ModeSheet(selected: session.mode),
    );
    if (picked == null) return;
    HapticFeedback.selectionClick();
    session.setMode(picked);
  }

  @override
  Widget build(BuildContext context) {
    final session = MediaSession.instance;
    if (!session.active) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            if (!session.poppedOut)
              Positioned.fill(
                child: _FullPlayer(
                  session: session,
                  bottomInset: _bottomClearance(context),
                  equalizer: _equalizer,
                  downloading: session.current != null &&
                      _downloading.contains(session.current!.id),
                  downloadProgress:
                      _downloadProgress[session.current?.id] ?? 0,
                  onDownload: _downloadCurrent,
                  onMode: _pickMode,
                  onQueue: _showQueue,
                ),
              ),
            if (session.poppedOut)
              _MiniPlayer(
                session: session,
                constraints: constraints,
                offset: _miniOffset,
                bottomInset: _bottomClearance(context),
                equalizer: _equalizer,
                onDrag: (next) => setState(() => _miniOffset = next),
              ),
          ],
        );
      },
    );
  }
}

class _Palette {
  _Palette(this.isDark, this.isAudio);

  final bool isDark;
  final bool isAudio;

  Color get accent =>
      isAudio ? const Color(0xFFEC4899) : const Color(0xFF0EA5E9);
  Color get canvas => isAudio
      ? (isDark ? const Color(0xFF1A1020) : const Color(0xFFF8EEF3))
      : (isDark ? const Color(0xFF070B12) : const Color(0xFFE7F2F8));
  Color get ink => isDark ? const Color(0xFFF9FAFB) : const Color(0xFF111827);
  Color get muted => isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
  Color get sheet => isAudio
      ? (isDark ? const Color(0xF22A1528) : const Color(0xF2FFFFFF))
      : (isDark ? const Color(0xF20C121C) : const Color(0xF2FFFFFF));
  Color get line => accent.withValues(alpha: isDark ? 0.28 : 0.18);
}

class _FullPlayer extends StatelessWidget {
  const _FullPlayer({
    required this.session,
    required this.bottomInset,
    required this.equalizer,
    required this.downloading,
    required this.downloadProgress,
    required this.onDownload,
    required this.onMode,
    required this.onQueue,
  });

  final MediaSession session;
  final double bottomInset;
  final AnimationController equalizer;
  final bool downloading;
  final double downloadProgress;
  final VoidCallback onDownload;
  final VoidCallback onMode;
  final VoidCallback onQueue;

  @override
  Widget build(BuildContext context) {
    final item = session.current;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = _Palette(isDark, item?.isAudio ?? false);
    final ready = item != null && !session.loading && session.error == null;
    if (ready && !item.isAudio) {
      return _VideoTheater(
        session: session,
        bottomInset: bottomInset,
        downloading: downloading,
        downloadProgress: downloadProgress,
        onDownload: onDownload,
        onMode: onMode,
        onQueue: onQueue,
      );
    }
    if (ready && item.isAudio) {
      return _AudioTheater(
        session: session,
        bottomInset: bottomInset,
        equalizer: equalizer,
        downloading: downloading,
        downloadProgress: downloadProgress,
        onDownload: onDownload,
        onMode: onMode,
        onQueue: onQueue,
      );
    }
    return Material(
      color: palette.canvas,
      child: Column(
        children: [
          SafeArea(
            bottom: false,
            child: _TopBar(
              palette: palette,
              title: item?.title ?? 'Now playing',
              subtitle: item == null
                  ? null
                  : '${item.kindLabel} · ${session.index + 1} of ${session.queue.length}',
              downloading: downloading,
              onBack: session.close,
              onPopOut: () {
                HapticFeedback.lightImpact();
                session.popOut();
              },
              onDownload: onDownload,
              onQueue: onQueue,
            ),
          ),
          if (downloading)
            LinearProgressIndicator(
              value: downloadProgress > 0 ? downloadProgress : null,
              minHeight: 2,
              color: palette.accent,
              backgroundColor: palette.accent.withValues(alpha: 0.12),
            ),
          Expanded(
            child: item == null
                ? const SizedBox.shrink()
                : session.loading
                    ? _StatusPane(
                        palette: palette,
                        icon: item.isAudio
                            ? Icons.audiotrack_rounded
                            : Icons.movie_rounded,
                        message: session.status ?? 'Loading...',
                        busy: true,
                      )
                    : session.error != null
                        ? _StatusPane(
                            palette: palette,
                            icon: item.isAudio
                                ? Icons.audiotrack_rounded
                                : Icons.videocam_off_rounded,
                            message: session.error!,
                            onRetry: session.retry,
                            onExternal: item.isAudio
                                ? null
                                : () async {
                                    try {
                                      await session.openExternal();
                                    } catch (error) {
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('$error'),
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                    }
                                  },
                          )
                        : item.isAudio
                            ? _AudioStage(
                                item: item,
                                palette: palette,
                                equalizer: equalizer,
                                playingListenable: session.playing,
                              )
                            : _VideoStage(session: session, palette: palette),
          ),
          if (item != null && session.error == null && !session.loading)
            _ControlDock(
              session: session,
              palette: palette,
              onMode: onMode,
              onQueue: onQueue,
            ),
          SizedBox(height: bottomInset),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.palette,
    required this.title,
    required this.subtitle,
    required this.downloading,
    required this.onBack,
    required this.onPopOut,
    required this.onDownload,
    required this.onQueue,
  });

  final _Palette palette;
  final String title;
  final String? subtitle;
  final bool downloading;
  final VoidCallback onBack;
  final VoidCallback onPopOut;
  final VoidCallback onDownload;
  final VoidCallback onQueue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            tooltip: 'Close',
            icon: const Icon(Icons.arrow_back_rounded),
            color: palette.ink,
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: palette.ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: palette.muted, fontSize: 12),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: onQueue,
            tooltip: 'Queue',
            icon: Icon(
              palette.isAudio
                  ? Icons.queue_music_rounded
                  : Icons.playlist_play_rounded,
            ),
            color: palette.ink,
          ),
          IconButton(
            onPressed: onPopOut,
            tooltip: 'Pop out',
            icon: const Icon(Icons.picture_in_picture_alt_rounded),
            color: palette.ink,
          ),
          IconButton(
            onPressed: onDownload,
            tooltip: downloading ? 'Cancel download' : 'Download',
            icon: Icon(
              downloading ? Icons.close_rounded : Icons.download_rounded,
            ),
            color: downloading ? const Color(0xFFEF4444) : palette.ink,
          ),
        ],
      ),
    );
  }
}

class _StatusPane extends StatelessWidget {
  const _StatusPane({
    required this.palette,
    required this.icon,
    required this.message,
    this.busy = false,
    this.onRetry,
    this.onExternal,
  });

  final _Palette palette;
  final IconData icon;
  final String message;
  final bool busy;
  final VoidCallback? onRetry;
  final VoidCallback? onExternal;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              SizedBox(
                width: 42,
                height: 42,
                child: CircularProgressIndicator(
                  strokeWidth: 2.6,
                  color: palette.accent,
                ),
              )
            else
              Icon(icon, size: 48, color: palette.muted),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.ink, fontSize: 16),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onRetry,
                style: FilledButton.styleFrom(
                  backgroundColor: palette.accent,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Try again'),
              ),
            ],
            if (onExternal != null)
              TextButton(
                onPressed: onExternal,
                child: const Text('Open in phone player'),
              ),
          ],
        ),
      ),
    );
  }
}

class _VideoTheater extends StatefulWidget {
  const _VideoTheater({
    required this.session,
    required this.bottomInset,
    required this.downloading,
    required this.downloadProgress,
    required this.onDownload,
    required this.onMode,
    required this.onQueue,
  });

  final MediaSession session;
  final double bottomInset;
  final bool downloading;
  final double downloadProgress;
  final VoidCallback onDownload;
  final VoidCallback onMode;
  final VoidCallback onQueue;

  @override
  State<_VideoTheater> createState() => _VideoTheaterState();
}

class _VideoTheaterState extends State<_VideoTheater> {
  bool _chrome = true;
  Timer? _hideTimer;
  static final _overlayPalette = _Palette(true, false);

  MediaSession get session => widget.session;

  @override
  void initState() {
    super.initState();
    session.addListener(_onSession);
    session.playing.addListener(_onPlaying);
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    session.removeListener(_onSession);
    session.playing.removeListener(_onPlaying);
    super.dispose();
  }

  void _onSession() {
    if (!mounted) return;
    if (session.showUpNext && !_chrome) {
      setState(() => _chrome = true);
    }
    _scheduleHide();
  }

  void _onPlaying() {
    if (!mounted) return;
    if (!session.playing.value) {
      _hideTimer?.cancel();
      setState(() => _chrome = true);
      return;
    }
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!session.playing.value || session.showUpNext) return;
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted || !session.playing.value || session.showUpNext) return;
      setState(() => _chrome = false);
    });
  }

  void _onVideoTap() {
    if (session.showUpNext) return;
    HapticFeedback.selectionClick();
    setState(() => _chrome = !_chrome);
    if (_chrome) _scheduleHide();
  }

  @override
  Widget build(BuildContext context) {
    final item = session.current;
    final controller = session.controller;
    final ready = controller != null && controller.value.isInitialized;
    final next = session.upcoming;
    final showChrome = _chrome || !session.playing.value || session.showUpNext;
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (ready)
            Center(
              child: AspectRatio(
                aspectRatio: controller.value.aspectRatio == 0
                    ? 16 / 9
                    : controller.value.aspectRatio,
                child: IgnorePointer(child: VideoPlayer(controller)),
              ),
            ),
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _onVideoTap,
            ),
          ),
          if (session.showUpNext && next != null)
            _UpNextCurtain(
              item: next,
              palette: _overlayPalette,
              onPlay: () {
                HapticFeedback.lightImpact();
                session.playUpcoming();
              },
              onReplay: session.togglePlay,
              onDismiss: session.dismissUpNext,
            ),
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !showChrome,
              child: AnimatedOpacity(
                opacity: showChrome ? 1 : 0,
                duration: const Duration(milliseconds: 220),
                child: Stack(
                  children: [
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.72),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: SafeArea(
                        bottom: false,
                        child: _TopBar(
                          palette: _overlayPalette,
                          title: item?.title ?? 'Now playing',
                          subtitle: item == null
                              ? null
                              : '${item.kindLabel} · ${session.index + 1} of ${session.queue.length}',
                          downloading: widget.downloading,
                          onBack: session.close,
                          onPopOut: () {
                            HapticFeedback.lightImpact();
                            session.popOut();
                          },
                          onDownload: widget.onDownload,
                          onQueue: widget.onQueue,
                        ),
                      ),
                    ),
                  ),
                  if (!session.showUpNext)
                    Center(
                      child: _PlayOrb(
                        palette: _overlayPalette,
                        playing: session.playing.value,
                        onTap: () {
                          HapticFeedback.lightImpact();
                          session.togglePlay();
                          _scheduleHide();
                        },
                      ),
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: widget.bottomInset + 12,
                    child: _ControlDock(
                      session: session,
                      palette: _overlayPalette,
                      onMode: widget.onMode,
                      onQueue: widget.onQueue,
                      overlay: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
          ),
          if (widget.downloading)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: LinearProgressIndicator(
                  value: widget.downloadProgress > 0
                      ? widget.downloadProgress
                      : null,
                  minHeight: 2,
                  color: _overlayPalette.accent,
                  backgroundColor: Colors.white24,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _VideoStage extends StatelessWidget {
  const _VideoStage({required this.session, required this.palette});

  final MediaSession session;
  final _Palette palette;

  @override
  Widget build(BuildContext context) {
    final controller = session.controller;
    final ready = controller != null && controller.value.isInitialized;
    final next = session.upcoming;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: palette.accent.withValues(alpha: palette.isDark ? 0.18 : 0.16),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (ready)
                Center(
                  child: AspectRatio(
                    aspectRatio: controller.value.aspectRatio == 0
                        ? 16 / 9
                        : controller.value.aspectRatio,
                    child: IgnorePointer(
                      child: VideoPlayer(controller),
                    ),
                  ),
                ),
              if (!session.showUpNext)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      session.togglePlay();
                    },
                  ),
                ),
              if (!session.playing.value && !session.showUpNext)
                Center(
                  child: _PlayOrb(palette: palette, onTap: session.togglePlay),
                ),
              if (session.showUpNext && next != null)
                _UpNextCurtain(
                  item: next,
                  palette: palette,
                  onPlay: () {
                    HapticFeedback.lightImpact();
                    session.playUpcoming();
                  },
                  onReplay: session.togglePlay,
                  onDismiss: session.dismissUpNext,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AudioTheater extends StatelessWidget {
  const _AudioTheater({
    required this.session,
    required this.bottomInset,
    required this.equalizer,
    required this.downloading,
    required this.downloadProgress,
    required this.onDownload,
    required this.onMode,
    required this.onQueue,
  });

  final MediaSession session;
  final double bottomInset;
  final AnimationController equalizer;
  final bool downloading;
  final double downloadProgress;
  final VoidCallback onDownload;
  final VoidCallback onMode;
  final VoidCallback onQueue;

  static final _overlayPalette = _Palette(true, true);

  @override
  Widget build(BuildContext context) {
    final item = session.current;
    final palette = _overlayPalette;
    return ColoredBox(
      color: const Color(0xFF0A0710),
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.18),
                radius: 1.05,
                colors: [
                  palette.accent.withValues(alpha: 0.34),
                  const Color(0xFF0A0710),
                ],
              ),
            ),
          ),
          if (item != null)
            Padding(
              padding: EdgeInsets.fromLTRB(24, 88, 24, 168 + bottomInset),
              child: _AudioStage(
                item: item,
                palette: palette,
                equalizer: equalizer,
                playingListenable: session.playing,
                showTitle: true,
              ),
            ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.72),
                    Colors.transparent,
                  ],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: _TopBar(
                  palette: palette,
                  title: item?.title ?? 'Now playing',
                  subtitle: item == null
                      ? null
                      : '${item.kindLabel} · ${session.index + 1} of ${session.queue.length}',
                  downloading: downloading,
                  onBack: session.close,
                  onPopOut: () {
                    HapticFeedback.lightImpact();
                    session.popOut();
                  },
                  onDownload: onDownload,
                  onQueue: onQueue,
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: bottomInset + 12,
            child: _ControlDock(
              session: session,
              palette: palette,
              onMode: onMode,
              onQueue: onQueue,
              overlay: true,
            ),
          ),
          if (downloading)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: LinearProgressIndicator(
                  value: downloadProgress > 0 ? downloadProgress : null,
                  minHeight: 2,
                  color: palette.accent,
                  backgroundColor: Colors.white24,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AudioStage extends StatelessWidget {
  const _AudioStage({
    required this.item,
    required this.palette,
    required this.equalizer,
    required this.playingListenable,
    this.showTitle = true,
  });

  final MediaQueueItem item;
  final _Palette palette;
  final AnimationController equalizer;
  final ValueNotifier<bool> playingListenable;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final disc = (constraints.maxHeight * 0.58).clamp(168.0, 280.0);
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: disc,
              height: disc,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedBuilder(
                    animation: equalizer,
                    builder: (context, _) {
                      return CustomPaint(
                        size: Size.square(disc),
                        painter: _GlowRingPainter(
                          color: palette.accent,
                          turns: equalizer.value,
                          dark: palette.isDark,
                        ),
                      );
                    },
                  ),
                  Container(
                    width: disc * 0.72,
                    height: disc * 0.72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          palette.accent.withValues(alpha: palette.isDark ? 0.45 : 0.28),
                          palette.isDark
                              ? const Color(0xFF111827)
                              : Colors.white,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: palette.accent.withValues(alpha: 0.28),
                          blurRadius: 28,
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.audiotrack_rounded,
                      size: disc * 0.28,
                      color: palette.accent,
                    ),
                  ),
                ],
              ),
            ),
            if (showTitle) ...[
              const SizedBox(height: 22),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Text(
                  item.title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            ValueListenableBuilder<bool>(
              valueListenable: playingListenable,
              builder: (context, playing, _) {
                return _EqualizerBars(
                  animation: equalizer,
                  color: palette.accent,
                  active: playing,
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _GlowRingPainter extends CustomPainter {
  _GlowRingPainter({
    required this.color,
    required this.turns,
    required this.dark,
  });

  final Color color;
  final double turns;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 6;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..shader = SweepGradient(
        transform: GradientRotation(turns * 6.28318),
        colors: [
          color.withValues(alpha: 0.05),
          color,
          color.withValues(alpha: 0.05),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawCircle(center, radius, paint);
    canvas.drawCircle(
      center,
      radius - 14,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color.withValues(alpha: dark ? 0.22 : 0.16),
    );
  }

  @override
  bool shouldRepaint(covariant _GlowRingPainter oldDelegate) {
    return oldDelegate.turns != turns || oldDelegate.color != color;
  }
}

class _EqualizerBars extends StatelessWidget {
  const _EqualizerBars({
    required this.animation,
    required this.color,
    required this.active,
  });

  final Animation<double> animation;
  final Color color;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < 5; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2.5),
                  child: Container(
                    width: 4,
                    height: active
                        ? 6 + 14 * ((animation.value + i * 0.17) % 1)
                        : 6,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: active ? 0.9 : 0.35),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ControlDock extends StatelessWidget {
  const _ControlDock({
    required this.session,
    required this.palette,
    required this.onMode,
    required this.onQueue,
    this.overlay = false,
  });

  final MediaSession session;
  final _Palette palette;
  final VoidCallback onMode;
  final VoidCallback onQueue;
  final bool overlay;

  @override
  Widget build(BuildContext context) {
    final controls = Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _modeCaption(session),
                  maxLines: 2,
                  style: TextStyle(color: palette.muted, fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              _QueueButton(palette: palette, onTap: onQueue),
              const SizedBox(width: 8),
              _ModePill(
                palette: palette,
                label: session.modeLabel,
                onTap: onMode,
              ),
            ],
          ),
          const SizedBox(height: 6),
          _SeekBar(palette: palette),
          const SizedBox(height: 4),
          _TransportRow(session: session, palette: palette),
        ],
      ),
    );
    if (overlay) {
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              (palette.isAudio
                      ? const Color(0xFF120814)
                      : Colors.black)
                  .withValues(alpha: 0.86),
            ],
          ),
        ),
        child: controls,
      );
    }
    final audio = palette.isAudio;
    return Padding(
      padding: EdgeInsets.fromLTRB(audio ? 16 : 0, 0, audio ? 16 : 0, audio ? 4 : 0),
      child: ClipRRect(
        borderRadius: BorderRadius.vertical(
          top: const Radius.circular(28),
          bottom: Radius.circular(audio ? 28 : 0),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: palette.sheet,
              border: Border.all(color: palette.line),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(18, 12, 18, audio ? 8 : 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _modeCaption(session),
                          maxLines: 2,
                          style: TextStyle(color: palette.muted, fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _QueueButton(palette: palette, onTap: onQueue),
                      const SizedBox(width: 8),
                      _ModePill(
                        palette: palette,
                        label: session.modeLabel,
                        onTap: onMode,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _SeekBar(palette: palette),
                  const SizedBox(height: 4),
                  _TransportRow(session: session, palette: palette),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _modeCaption(MediaSession session) {
    final kind = session.current?.isAudio == true ? 'audio files' : 'videos';
    final one = session.current?.isAudio == true ? 'audio' : 'video';
    switch (session.mode) {
      case PlaybackRepeatMode.none:
        return session.upcoming == null
            ? 'Last $one in this folder'
            : 'Stops after this $one';
      case PlaybackRepeatMode.one:
        return 'Repeating this $one';
      case PlaybackRepeatMode.all:
        return 'Playing the $kind in this folder, then starting over';
      case PlaybackRepeatMode.shuffle:
        return 'Shuffled $kind in this folder';
    }
  }
}

class _SeekBar extends StatefulWidget {
  const _SeekBar({required this.palette});

  final _Palette palette;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final session = MediaSession.instance;
    return ValueListenableBuilder<Duration>(
      valueListenable: session.position,
      builder: (context, position, _) {
        final maxMs = session.duration.inMilliseconds <= 0
            ? 1.0
            : session.duration.inMilliseconds.toDouble();
        final value = (_drag ?? position.inMilliseconds.toDouble()).clamp(0, maxMs);
        final shown = Duration(milliseconds: value.round());
        return Column(
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: widget.palette.accent,
                inactiveTrackColor: widget.palette.muted.withValues(alpha: 0.28),
                thumbColor: widget.palette.accent,
                overlayColor: widget.palette.accent.withValues(alpha: 0.16),
              ),
              child: Slider(
                value: value.toDouble(),
                max: maxMs,
                onChangeStart: (next) => setState(() => _drag = next),
                onChanged: (next) => setState(() => _drag = next),
                onChangeEnd: (next) {
                  setState(() => _drag = null);
                  session.seekTo(Duration(milliseconds: next.round()));
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                children: [
                  Text(
                    _formatDuration(shown),
                    style: TextStyle(color: widget.palette.muted, fontSize: 12),
                  ),
                  const Spacer(),
                  Text(
                    _formatDuration(session.duration),
                    style: TextStyle(color: widget.palette.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TransportRow extends StatelessWidget {
  const _TransportRow({
    required this.session,
    required this.palette,
  });

  final MediaSession session;
  final _Palette palette;

  @override
  Widget build(BuildContext context) {
    final playing = session.playing.value;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _RoundButton(
          icon: Icons.skip_previous_rounded,
          tooltip: 'Previous',
          color: palette.ink,
          enabled: session.canSkipPrevious,
          onTap: () {
            HapticFeedback.selectionClick();
            session.skipPrevious();
          },
        ),
        _RoundButton(
          icon: Icons.replay_10_rounded,
          tooltip: 'Back 10 seconds',
          color: palette.ink,
          onTap: () => session.seekBy(const Duration(seconds: -10)),
        ),
        _PlayOrb(
          palette: palette,
          playing: playing,
          onTap: () {
            HapticFeedback.lightImpact();
            session.togglePlay();
          },
        ),
        _RoundButton(
          icon: Icons.forward_10_rounded,
          tooltip: 'Forward 10 seconds',
          color: palette.ink,
          onTap: () => session.seekBy(const Duration(seconds: 10)),
        ),
        _RoundButton(
          icon: Icons.skip_next_rounded,
          tooltip: 'Next',
          color: palette.ink,
          enabled: session.canSkipNext,
          onTap: () {
            HapticFeedback.selectionClick();
            session.skipNext();
          },
        ),
      ],
    );
  }
}

class _PlayOrb extends StatelessWidget {
  const _PlayOrb({
    required this.palette,
    required this.onTap,
    this.playing = false,
  });

  final _Palette palette;
  final VoidCallback onTap;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    const size = 62.0;
    return Material(
      color: palette.accent,
      shape: const CircleBorder(),
      elevation: 0,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: Colors.white,
            size: size * 0.56,
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: enabled ? onTap : null,
      icon: Icon(icon),
      color: color,
      disabledColor: color.withValues(alpha: 0.28),
      iconSize: 28,
    );
  }
}

class _ModePill extends StatelessWidget {
  const _ModePill({
    required this.palette,
    required this.label,
    required this.onTap,
  });

  final _Palette palette;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final selected = label != 'None';
    return Tooltip(
      message: 'Playback mode',
      child: Material(
        color: selected
            ? palette.accent.withValues(alpha: 0.16)
            : palette.muted.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? palette.accent : palette.muted,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QueueButton extends StatelessWidget {
  const _QueueButton({required this.palette, required this.onTap});

  final _Palette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Queue',
      child: Material(
        color: palette.accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(
              palette.isAudio
                  ? Icons.queue_music_rounded
                  : Icons.playlist_play_rounded,
              color: palette.accent,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}

class _UpNextCurtain extends StatelessWidget {
  const _UpNextCurtain({
    required this.item,
    required this.palette,
    required this.onPlay,
    required this.onReplay,
    required this.onDismiss,
  });

  final MediaQueueItem item;
  final _Palette palette;
  final VoidCallback onPlay;
  final VoidCallback onReplay;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.72),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                onPressed: onDismiss,
                tooltip: 'Dismiss',
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ),
            const Spacer(),
            const Text(
              'Up next',
              style: TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 12),
            _VideoPreview(item: item),
            const SizedBox(height: 14),
            Text(
              item.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              item.kindLabel,
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onPlay,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF111827),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              ),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Play next'),
            ),
            TextButton(
              onPressed: onReplay,
              child: const Text('Replay', style: TextStyle(color: Colors.white70)),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

class _VideoPreview extends StatelessWidget {
  const _VideoPreview({required this.item});

  final MediaQueueItem item;

  @override
  Widget build(BuildContext context) {
    final fallback = _MediaMark(item: item, radius: 16);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white24),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: item.hasThumbnail
                ? DriveThumbnail(
                    fileId: item.id,
                    fit: BoxFit.cover,
                    fallback: fallback,
                  )
                : fallback,
          ),
        ),
      ),
    );
  }
}

class _ArtThumb extends StatelessWidget {
  const _ArtThumb({
    required this.item,
    required this.width,
    required this.height,
    required this.radius,
  });

  final MediaQueueItem item;
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final fallback = _MediaMark(item: item, radius: radius);
    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: item.hasThumbnail
            ? DriveThumbnail(
                fileId: item.id,
                fit: BoxFit.cover,
                fallback: fallback,
              )
            : fallback,
      ),
    );
  }
}

class _MediaMark extends StatelessWidget {
  const _MediaMark({required this.item, required this.radius});

  final MediaQueueItem item;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final color = item.isAudio ? const Color(0xFFEC4899) : const Color(0xFF6366F1);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.85),
            color.withValues(alpha: 0.45),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          item.isAudio ? Icons.audiotrack_rounded : Icons.movie_rounded,
          color: Colors.white,
          size: 22,
        ),
      ),
    );
  }
}

class _MiniPlayer extends StatelessWidget {
  const _MiniPlayer({
    required this.session,
    required this.constraints,
    required this.offset,
    required this.bottomInset,
    required this.equalizer,
    required this.onDrag,
  });

  final MediaSession session;
  final BoxConstraints constraints;
  final Offset? offset;
  final double bottomInset;
  final AnimationController equalizer;
  final ValueChanged<Offset> onDrag;

  @override
  Widget build(BuildContext context) {
    final item = session.current;
    if (item == null) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = _Palette(isDark, item.isAudio);
    final size = item.isAudio
        ? Size((constraints.maxWidth - 24).clamp(240, 460), 78)
        : const Size(236, 168);
    final fallback = Offset(
      item.isAudio
          ? (constraints.maxWidth - size.width) / 2
          : constraints.maxWidth - size.width - 12,
      constraints.maxHeight - size.height - bottomInset,
    );
    final origin = offset ?? fallback;
    final left = origin.dx.clamp(8.0, constraints.maxWidth - size.width - 8);
    final top = origin.dy.clamp(
      8.0,
      constraints.maxHeight - size.height - 8,
    );
    return Positioned(
      left: left,
      top: top,
      width: size.width,
      height: size.height,
      child: GestureDetector(
        onPanUpdate: (details) => onDrag(Offset(left, top) + details.delta),
        child: item.isAudio
            ? _AudioMini(
                session: session,
                item: item,
                palette: palette,
                equalizer: equalizer,
              )
            : _VideoMini(session: session, item: item, palette: palette),
      ),
    );
  }
}

class _VideoMini extends StatelessWidget {
  const _VideoMini({
    required this.session,
    required this.item,
    required this.palette,
  });

  final MediaSession session;
  final MediaQueueItem item;
  final _Palette palette;

  @override
  Widget build(BuildContext context) {
    final controller = session.controller;
    final ready = controller != null && controller.value.isInitialized;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.isDark ? const Color(0xFF161D2E) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: palette.isDark ? 0.4 : 0.16),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: Colors.black),
                  if (ready) VideoPlayer(controller),
                  if (session.showUpNext && session.upcoming != null)
                    GestureDetector(
                      onTap: session.playUpcoming,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _ArtThumb(
                            item: session.upcoming!,
                            width: 236,
                            height: 132,
                            radius: 0,
                          ),
                          const ColoredBox(color: Colors.black38),
                          const Center(
                            child: Text(
                              'Play next',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Positioned(
                    left: 4,
                    top: 4,
                    child: _MiniIcon(
                      icon: Icons.close_rounded,
                      tooltip: 'Close',
                      onTap: session.close,
                      scrim: true,
                    ),
                  ),
                  Positioned(
                    right: 4,
                    top: 4,
                    child: _MiniIcon(
                      icon: Icons.open_in_full_rounded,
                      tooltip: 'Full screen',
                      onTap: session.expand,
                      scrim: true,
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _ThinProgress(color: palette.accent),
                  ),
                ],
              ),
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: session.expand,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 2, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: palette.ink,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      _MiniIcon(
                        icon: session.playing.value
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        tooltip: session.playing.value ? 'Pause' : 'Play',
                        onTap: session.togglePlay,
                        color: palette.ink,
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
}

class _AudioMini extends StatelessWidget {
  const _AudioMini({
    required this.session,
    required this.item,
    required this.palette,
    required this.equalizer,
  });

  final MediaSession session;
  final MediaQueueItem item;
  final _Palette palette;
  final AnimationController equalizer;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.isDark ? const Color(0xFF161D2E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.line),
        boxShadow: [
          BoxShadow(
            color: palette.accent.withValues(alpha: 0.16),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: session.expand,
            child: Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 4, 4),
                    child: Row(
                      children: [
                        _EqualizerBars(
                          animation: equalizer,
                          color: palette.accent,
                          active: session.playing.value,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: palette.ink,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                session.showUpNext && session.upcoming != null
                                    ? 'Up next · ${session.upcoming!.title}'
                                    : 'Audio',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: session.showUpNext
                                      ? palette.accent
                                      : palette.muted,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _MiniIcon(
                          icon: session.playing.value
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          tooltip: session.playing.value ? 'Pause' : 'Play',
                          onTap: session.togglePlay,
                          color: palette.ink,
                        ),
                        _MiniIcon(
                          icon: Icons.skip_next_rounded,
                          tooltip: 'Next',
                          onTap: session.canSkipNext ? session.skipNext : null,
                          color: palette.ink,
                        ),
                        _MiniIcon(
                          icon: Icons.close_rounded,
                          tooltip: 'Close',
                          onTap: session.close,
                        ),
                      ],
                    ),
                  ),
                ),
                _ThinProgress(color: palette.accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ThinProgress extends StatelessWidget {
  const _ThinProgress({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Duration>(
      valueListenable: MediaSession.instance.position,
      builder: (context, position, _) {
        final total = MediaSession.instance.duration.inMilliseconds;
        final fraction = total <= 0
            ? 0.0
            : (position.inMilliseconds / total).clamp(0.0, 1.0);
        return LinearProgressIndicator(
          value: fraction,
          minHeight: 2,
          color: color,
          backgroundColor: color.withValues(alpha: 0.15),
        );
      },
    );
  }
}

class _MiniIcon extends StatelessWidget {
  const _MiniIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color = Colors.white,
    this.scrim = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final Color color;
  final bool scrim;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      onPressed: onTap,
      icon: DecoratedBox(
        decoration: BoxDecoration(
          color: scrim ? Colors.black.withValues(alpha: 0.45) : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 20,
          color: onTap == null ? color.withValues(alpha: 0.35) : color,
        ),
      ),
    );
  }
}

class _QueueSheet extends StatelessWidget {
  const _QueueSheet({required this.session});

  final MediaSession session;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final audio = session.current?.isAudio ?? false;
    final accent = audio ? const Color(0xFFEC4899) : const Color(0xFF0EA5E9);
    final ink = isDark ? const Color(0xFFF9FAFB) : const Color(0xFF111827);
    final muted = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
    final card = isDark ? const Color(0xFF161D2E) : Colors.white;
    final indexes = session.sequenceIndexes;
    final height = MediaQuery.sizeOf(context).height * 0.62;
    final countLabel = audio
        ? '${indexes.length} ${indexes.length == 1 ? 'track' : 'tracks'}'
        : '${indexes.length} ${indexes.length == 1 ? 'video' : 'videos'}';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: card,
            borderRadius: BorderRadius.circular(24),
          ),
          child: SizedBox(
            height: height,
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: muted.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  audio ? 'Audio queue' : 'Video queue',
                  style: TextStyle(
                    color: ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'This folder only · $countLabel',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    itemCount: indexes.length,
                    itemBuilder: (context, position) {
                      final index = indexes[position];
                      final item = session.queue[index];
                      final playing = index == session.index;
                      return ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        selected: playing,
                        selectedTileColor: accent.withValues(alpha: 0.12),
                        leading: audio
                            ? CircleAvatar(
                                backgroundColor: accent.withValues(alpha: 0.16),
                                child: Icon(
                                  Icons.audiotrack_rounded,
                                  color: accent,
                                  size: 18,
                                ),
                              )
                            : _ArtThumb(
                                item: item,
                                width: 64,
                                height: 40,
                                radius: 8,
                              ),
                        title: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: ink,
                            fontWeight: playing ? FontWeight.w700 : FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          playing ? 'Now playing' : '${position + 1}',
                          style: TextStyle(
                            color: playing ? accent : muted,
                            fontSize: 12,
                          ),
                        ),
                        trailing: playing
                            ? Icon(Icons.equalizer_rounded, color: accent)
                            : null,
                        onTap: () => Navigator.pop(context, index),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeSheet extends StatelessWidget {
  const _ModeSheet({required this.selected});

  final PlaybackRepeatMode selected;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? const Color(0xFFF9FAFB) : const Color(0xFF111827);
    final muted = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
    final card = isDark ? const Color(0xFF161D2E) : Colors.white;
    const options = [
      (
        PlaybackRepeatMode.none,
        'None',
        'Stop here and suggest the next one in this folder',
        Icons.playlist_play_rounded,
      ),
      (
        PlaybackRepeatMode.one,
        'Loop 1',
        'Repeat the current audio or video',
        Icons.repeat_one_rounded,
      ),
      (
        PlaybackRepeatMode.all,
        'Loop all',
        'Play the rest of this queue, then start over',
        Icons.repeat_rounded,
      ),
      (
        PlaybackRepeatMode.shuffle,
        'Shuffle',
        'Play this queue in a random order',
        Icons.shuffle_rounded,
      ),
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: card,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: muted.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Playback',
                  style: TextStyle(
                    color: ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'This folder only, same type',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
                const SizedBox(height: 8),
                for (final option in options)
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    selected: option.$1 == selected,
                    selectedTileColor: const Color(0xFF6366F1).withValues(alpha: 0.12),
                    leading: Icon(
                      option.$4,
                      color: option.$1 == selected
                          ? const Color(0xFF6366F1)
                          : muted,
                    ),
                    title: Text(
                      option.$2,
                      style: TextStyle(
                        color: ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      option.$3,
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                    trailing: option.$1 == selected
                        ? const Icon(Icons.check_rounded, color: Color(0xFF6366F1))
                        : null,
                    onTap: () => Navigator.pop(context, option.$1),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _formatDuration(Duration value) {
  final two = (int n) => n.toString().padLeft(2, '0');
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60);
  final seconds = value.inSeconds.remainder(60);
  if (hours > 0) return '$hours:${two(minutes)}:${two(seconds)}';
  return '${two(minutes)}:${two(seconds)}';
}
