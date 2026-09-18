import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';

import 'media_session.dart';
import 'upload_service.dart';

/// Lock-screen / notification controls for [MediaSession].
class MediaNotification {
  MediaNotification._();

  static PlaybackAudioHandler? _handler;

  static bool get supported {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  static Future<void> ensureInitialized() async {
    if (!supported || _handler != null) return;
    try {
      _handler = await AudioService.init(
        builder: PlaybackAudioHandler.new,
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.example.libview.playback',
          androidNotificationChannelName: 'Now playing',
          androidNotificationChannelDescription:
              'Controls for audio and video playing in Edupal',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
          androidNotificationIcon: 'drawable/ic_stat_playback',
          androidShowNotificationBadge: true,
          fastForwardInterval: Duration(seconds: 10),
          rewindInterval: Duration(seconds: 10),
          notificationColor: ui.Color(0xFF0EA5E9),
        ),
      );
    } catch (_) {}
  }
}

class PlaybackAudioHandler extends BaseAudioHandler with SeekHandler {
  PlaybackAudioHandler() {
    final session = MediaSession.instance;
    session.addListener(_onSession);
    session.playing.addListener(_onSession);
    session.position.addListener(_onPosition);
    unawaited(_configureAudioSession());
    _onSession();
  }

  bool _stopping = false;
  bool _askedPermission = false;
  DateTime _lastPositionPublish = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> _configureAudioSession() async {
    try {
      final session = await AudioSession.instance;
      // On Android, ExoPlayer already owns audio focus. Requesting it again
      // here sends AUDIOFOCUS_LOSS to the player and it keeps pausing.
      if (Platform.isIOS) {
        await session.configure(const AudioSessionConfiguration.music());
        session.interruptionEventStream.listen((event) {
          if (event.begin && event.type != AudioInterruptionType.duck) {
            unawaited(MediaSession.instance.pause());
          }
        });
      }
      session.becomingNoisyEventStream.listen((_) {
        unawaited(MediaSession.instance.pause());
      });
    } catch (_) {}
  }

  Future<void> _ensureAndroidNotificationPermission() async {
    if (_askedPermission || kIsWeb || !Platform.isAndroid) return;
    _askedPermission = true;
    try {
      await Permission.notification.request();
    } catch (_) {}
  }

  void _onPosition() {
    final session = MediaSession.instance;
    if (!session.active || !session.playing.value) return;
    final now = DateTime.now();
    if (now.difference(_lastPositionPublish) < const Duration(milliseconds: 800)) {
      return;
    }
    _lastPositionPublish = now;
    _publishState();
  }

  void _onSession() {
    final session = MediaSession.instance;
    if (!session.active) {
      if (!_stopping &&
          playbackState.value.processingState != AudioProcessingState.idle) {
        unawaited(stop());
      }
      return;
    }
    unawaited(_ensureAndroidNotificationPermission());
    unawaited(_publishItem());
    _publishState();
  }

  static const _play = MediaControl(
    androidIcon: 'drawable/ic_media_play_round',
    label: 'Play',
    action: MediaAction.play,
  );
  static const _pause = MediaControl(
    androidIcon: 'drawable/ic_media_pause_round',
    label: 'Pause',
    action: MediaAction.pause,
  );
  static const _previous = MediaControl(
    androidIcon: 'drawable/ic_media_prev_round',
    label: 'Previous',
    action: MediaAction.skipToPrevious,
  );
  static const _next = MediaControl(
    androidIcon: 'drawable/ic_media_next_round',
    label: 'Next',
    action: MediaAction.skipToNext,
  );
  static const _stop = MediaControl(
    androidIcon: 'drawable/ic_media_stop_round',
    label: 'Stop',
    action: MediaAction.stop,
  );

  Future<void> _publishItem() async {
    final session = MediaSession.instance;
    final item = session.current;
    if (item == null) {
      mediaItem.add(null);
      queue.add(const []);
      return;
    }
    final duration =
        session.duration > Duration.zero ? session.duration : null;
    final art = await _artworkFor(item);
    if (MediaSession.instance.current?.id != item.id) return;
    mediaItem.add(
      MediaItem(
        id: item.id,
        title: item.title,
        artist: item.subject.isEmpty ? 'Edupal' : item.subject,
        album: item.isAudio ? 'Audio' : 'Video',
        duration: duration,
        artUri: art,
        playable: true,
        displayTitle: item.title,
        displaySubtitle: item.isAudio ? 'Now playing' : 'Video preview',
      ),
    );
    queue.add([
      for (final entry in session.queue)
        MediaItem(
          id: entry.id,
          title: entry.title,
          artist: entry.subject.isEmpty ? 'Edupal' : entry.subject,
          album: entry.isAudio ? 'Audio' : 'Video',
          playable: true,
        ),
    ]);
  }

  Future<Uri> _artworkFor(MediaQueueItem item) async {
    final dir = await getTemporaryDirectory();
    if (item.hasThumbnail) {
      final path = '${dir.path}/notif_art_${item.id}.jpg';
      final file = File(path);
      try {
        if (!await file.exists() || await file.length() == 0) {
          final headers = await UploadService.instance.authHeaders();
          await Dio().download(
            UploadService.thumbnailUrl(item.id),
            path,
            options: Options(headers: headers),
          );
        }
        if (await file.exists() && await file.length() > 0) {
          return Uri.file(path);
        }
      } catch (_) {}
    }
    return _fallbackArt(dir, item.isAudio);
  }

  Future<Uri> _fallbackArt(Directory dir, bool isAudio) async {
    final path = '${dir.path}/notif_art_${isAudio ? 'audio' : 'video'}.png';
    final file = File(path);
    if (await file.exists() && await file.length() > 0) {
      return Uri.file(path);
    }
    const dim = 512;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      ui.Rect.fromLTWH(0, 0, dim.toDouble(), dim.toDouble()),
    );
    final paint = ui.Paint()
      ..shader = ui.Gradient.linear(
        ui.Offset.zero,
        const ui.Offset(512, 512),
        isAudio
            ? const [ui.Color(0xFFEC4899), ui.Color(0xFF7C3AED)]
            : const [ui.Color(0xFF0284C7), ui.Color(0xFF6366F1)],
      );
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, dim.toDouble(), dim.toDouble()),
      paint,
    );
    final glow = ui.Paint()
      ..color = const ui.Color(0x66FFFFFF)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 28);
    canvas.drawCircle(const ui.Offset(256, 256), 92, glow);
    final disc = ui.Paint()..color = const ui.Color(0xE6FFFFFF);
    canvas.drawCircle(const ui.Offset(256, 256), 78, disc);
    final icon = ui.Paint()
      ..color = isAudio ? const ui.Color(0xFFEC4899) : const ui.Color(0xFF0284C7)
      ..style = ui.PaintingStyle.fill;
    if (isAudio) {
      final note = ui.Path()
        ..moveTo(236, 214)
        ..lineTo(236, 292)
        ..quadraticBezierTo(236, 312, 256, 312)
        ..quadraticBezierTo(276, 312, 276, 292)
        ..lineTo(276, 236)
        ..lineTo(298, 236)
        ..lineTo(298, 214)
        ..close();
      canvas.drawPath(note, icon);
    } else {
      final play = ui.Path()
        ..moveTo(236, 224)
        ..quadraticBezierTo(236, 216, 244, 220)
        ..lineTo(292, 250)
        ..quadraticBezierTo(298, 256, 292, 262)
        ..lineTo(244, 292)
        ..quadraticBezierTo(236, 296, 236, 288)
        ..close();
      canvas.drawPath(play, icon);
    }
    final image = await recorder.endRecording().toImage(dim, dim);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes != null) {
      await file.writeAsBytes(bytes.buffer.asUint8List());
    }
    return Uri.file(path);
  }

  void _publishState() {
    final session = MediaSession.instance;
    if (!session.active) return;

    final playing = session.playing.value || session.loading;
    final controls = <MediaControl>[
      if (session.canSkipPrevious) _previous,
      if (playing) _pause else _play,
      if (session.canSkipNext) _next,
      _stop,
    ];
    final compact = <int>[];
    for (var i = 0; i < controls.length && compact.length < 3; i++) {
      final control = controls[i];
      if (control == _play ||
          control == _pause ||
          control == _previous ||
          control == _next) {
        compact.add(i);
      }
    }

    final AudioProcessingState processing;
    if (session.loading || session.controller?.value.isBuffering == true) {
      processing = AudioProcessingState.buffering;
    } else {
      processing = AudioProcessingState.ready;
    }

    playbackState.add(
      PlaybackState(
        controls: controls,
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.skipToNext,
          MediaAction.skipToPrevious,
          MediaAction.stop,
        },
        androidCompactActionIndices: compact,
        processingState: processing,
        playing: playing,
        updatePosition: session.position.value,
        bufferedPosition: _bufferedPosition(session.controller?.value),
        speed: 1.0,
        queueIndex: session.index,
        repeatMode: _repeatMode(session.mode),
        shuffleMode: session.mode == PlaybackRepeatMode.shuffle
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
      ),
    );
  }

  Duration _bufferedPosition(VideoPlayerValue? value) {
    final ranges = value?.buffered;
    if (ranges == null || ranges.isEmpty) return Duration.zero;
    return ranges.last.end;
  }

  AudioServiceRepeatMode _repeatMode(PlaybackRepeatMode mode) {
    switch (mode) {
      case PlaybackRepeatMode.one:
        return AudioServiceRepeatMode.one;
      case PlaybackRepeatMode.all:
        return AudioServiceRepeatMode.all;
      case PlaybackRepeatMode.shuffle:
        return AudioServiceRepeatMode.all;
      case PlaybackRepeatMode.none:
        return AudioServiceRepeatMode.none;
    }
  }

  @override
  Future<void> play() => MediaSession.instance.play();

  @override
  Future<void> pause() => MediaSession.instance.pause();

  @override
  Future<void> seek(Duration position) => MediaSession.instance.seekTo(position);

  @override
  Future<void> skipToNext() => MediaSession.instance.skipNext();

  @override
  Future<void> skipToPrevious() => MediaSession.instance.skipPrevious();

  @override
  Future<void> fastForward() =>
      MediaSession.instance.seekBy(const Duration(seconds: 10));

  @override
  Future<void> rewind() =>
      MediaSession.instance.seekBy(const Duration(seconds: -10));

  @override
  Future<void> stop() async {
    if (_stopping) {
      await super.stop();
      return;
    }
    _stopping = true;
    try {
      if (MediaSession.instance.active) {
        MediaSession.instance.close();
      }
      mediaItem.add(null);
      queue.add(const []);
      await super.stop();
    } finally {
      _stopping = false;
    }
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    final session = MediaSession.instance;
    switch (repeatMode) {
      case AudioServiceRepeatMode.one:
        session.setMode(PlaybackRepeatMode.one);
      case AudioServiceRepeatMode.all:
      case AudioServiceRepeatMode.group:
        session.setMode(PlaybackRepeatMode.all);
      case AudioServiceRepeatMode.none:
        session.setMode(PlaybackRepeatMode.none);
    }
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    if (shuffleMode == AudioServiceShuffleMode.none) {
      MediaSession.instance.setMode(PlaybackRepeatMode.none);
      return;
    }
    MediaSession.instance.setMode(PlaybackRepeatMode.shuffle);
  }
}
