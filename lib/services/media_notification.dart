import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:video_player/video_player.dart';

import 'media_session.dart';

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
          notificationColor: Color(0xFF6366F1),
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
      await session.configure(const AudioSessionConfiguration.music());
      session.interruptionEventStream.listen((event) {
        if (event.begin && event.type != AudioInterruptionType.duck) {
          unawaited(MediaSession.instance.pause());
        }
      });
      session.becomingNoisyEventStream.listen((_) {
        unawaited(MediaSession.instance.pause());
      });
    } catch (_) {}
  }

  Future<void> _activateAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.setActive(true);
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
    unawaited(_activateAudioSession());
    _publishItem();
    _publishState();
  }

  void _publishItem() {
    final session = MediaSession.instance;
    final item = session.current;
    if (item == null) {
      mediaItem.add(null);
      queue.add(const []);
      return;
    }
    final duration =
        session.duration > Duration.zero ? session.duration : null;
    mediaItem.add(
      MediaItem(
        id: item.id,
        title: item.title,
        artist: item.subject.isEmpty ? 'Edupal' : item.subject,
        album: item.isAudio ? 'Audio' : 'Video',
        duration: duration,
        playable: true,
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

  void _publishState() {
    final session = MediaSession.instance;
    if (!session.active) return;

    final playing = session.playing.value || session.loading;
    final controls = <MediaControl>[
      if (session.canSkipPrevious) MediaControl.skipToPrevious,
      if (playing) MediaControl.pause else MediaControl.play,
      if (session.canSkipNext) MediaControl.skipToNext,
      MediaControl.stop,
    ];
    final compact = <int>[];
    for (var i = 0; i < controls.length && compact.length < 3; i++) {
      final control = controls[i];
      if (control == MediaControl.play ||
          control == MediaControl.pause ||
          control == MediaControl.skipToPrevious ||
          control == MediaControl.skipToNext) {
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
