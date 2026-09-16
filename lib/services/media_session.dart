import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import 'upload_service.dart';

/// How the current folder queue continues after an item finishes.
///
/// [none] is the default: playback stops and the player suggests the next
/// item in this folder, without starting it.
enum PlaybackRepeatMode { none, one, all, shuffle }

/// One audio or video file from the folder that was open when playback started.
///
/// Child folders are never included. The list is a snapshot of that folder.
class MediaQueueItem {
  const MediaQueueItem({
    required this.id,
    required this.title,
    required this.isAudio,
    required this.subject,
  });

  final String id;
  final String title;
  final bool isAudio;
  final String subject;

  String get kindLabel => isAudio ? 'Audio' : 'Video';
}

/// Client-only playback session. Only the client files browser starts it.
///
/// The controller lives here so a popped-out player can keep running while
/// the rest of the app is used.
class MediaSession extends ChangeNotifier {
  MediaSession._();

  static final MediaSession instance = MediaSession._();

  final ValueNotifier<Duration> position = ValueNotifier(Duration.zero);
  final ValueNotifier<bool> playing = ValueNotifier(false);

  /// True only while the full-screen player covers the app.
  final ValueNotifier<bool> expanded = ValueNotifier(false);

  PlaybackRepeatMode mode = PlaybackRepeatMode.none;
  List<MediaQueueItem> queue = const [];
  int index = 0;
  VideoPlayerController? controller;
  Duration duration = Duration.zero;
  bool active = false;
  bool poppedOut = false;
  bool loading = false;
  bool showUpNext = false;
  String? status;
  String? error;

  final List<int> _history = [];
  List<int> _shuffleBag = [];
  int _token = 0;
  bool _endedLatch = false;
  CancelToken? _cacheCancel;

  MediaQueueItem? get current {
    if (index < 0 || index >= queue.length) return null;
    return queue[index];
  }

  /// Next item in folder order. Shown only while [mode] is [PlaybackRepeatMode.none].
  MediaQueueItem? get upcoming {
    final next = index + 1;
    if (next < 0 || next >= queue.length) return null;
    return queue[next];
  }

  bool get isExpanded => active && !poppedOut;

  bool get canSkipNext {
    if (queue.length <= 1) return false;
    if (mode == PlaybackRepeatMode.all || mode == PlaybackRepeatMode.shuffle) {
      return true;
    }
    return index < queue.length - 1;
  }

  bool get canSkipPrevious {
    final value = controller?.value;
    if (value != null &&
        value.isInitialized &&
        value.position > const Duration(seconds: 3)) {
      return true;
    }
    if (queue.length <= 1) return false;
    if (mode == PlaybackRepeatMode.all) return true;
    if (mode == PlaybackRepeatMode.shuffle) {
      return _history.isNotEmpty || index > 0;
    }
    return index > 0;
  }

  String get modeLabel {
    switch (mode) {
      case PlaybackRepeatMode.none:
        return 'None';
      case PlaybackRepeatMode.one:
        return 'Loop 1';
      case PlaybackRepeatMode.all:
        return 'Loop all';
      case PlaybackRepeatMode.shuffle:
        return 'Shuffle';
    }
  }

  Future<void> open({
    required List<MediaQueueItem> queue,
    required int index,
  }) async {
    if (queue.isEmpty) return;
    _cacheCancel?.cancel('replaced');
    this.queue = List<MediaQueueItem>.of(queue);
    this.index = index.clamp(0, this.queue.length - 1);
    mode = PlaybackRepeatMode.none;
    poppedOut = false;
    active = true;
    showUpNext = false;
    error = null;
    _history.clear();
    _shuffleBag = [];
    _syncExpanded();
    notifyListeners();
    await _loadCurrent();
  }

  void close() {
    _token++;
    _cacheCancel?.cancel('closed');
    _cacheCancel = null;
    active = false;
    poppedOut = false;
    showUpNext = false;
    loading = false;
    error = null;
    status = null;
    queue = const [];
    index = 0;
    duration = Duration.zero;
    _history.clear();
    _shuffleBag = [];
    _endedLatch = false;
    final old = controller;
    controller = null;
    old?.removeListener(_onTick);
    old?.dispose();
    position.value = Duration.zero;
    playing.value = false;
    _syncExpanded();
    notifyListeners();
  }

  void popOut() {
    if (!active || poppedOut) return;
    poppedOut = true;
    _syncExpanded();
    notifyListeners();
  }

  void expand() {
    if (!active || !poppedOut) return;
    poppedOut = false;
    _syncExpanded();
    notifyListeners();
  }

  void setMode(PlaybackRepeatMode value) {
    if (mode == value) return;
    mode = value;
    if (value == PlaybackRepeatMode.shuffle) {
      _refillShuffle(exclude: index);
      _history.clear();
    }
    if (value != PlaybackRepeatMode.none) {
      showUpNext = false;
    }
    notifyListeners();
  }

  bool _backConsumed = false;

  /// Closes the full player on system back, and swallows a second handler
  /// that runs in the same event after the first one already closed it.
  bool consumeSystemBack() {
    if (isExpanded) {
      close();
      _backConsumed = true;
      scheduleMicrotask(() => _backConsumed = false);
      return true;
    }
    return _backConsumed;
  }

  void dismissUpNext() {
    if (!showUpNext) return;
    showUpNext = false;
    notifyListeners();
  }

  Future<void> retry() => _loadCurrent();

  Future<void> togglePlay() async {
    final currentController = controller;
    if (currentController == null || !currentController.value.isInitialized) {
      return;
    }
    if (currentController.value.isPlaying) {
      await currentController.pause();
      notifyListeners();
      return;
    }
    final atEnd = duration > Duration.zero &&
        currentController.value.position >=
            duration - const Duration(milliseconds: 300);
    if (atEnd) {
      _endedLatch = false;
      showUpNext = false;
      await currentController.seekTo(Duration.zero);
    }
    await currentController.play();
    notifyListeners();
  }

  Future<void> seekTo(Duration target) async {
    final currentController = controller;
    if (currentController == null || !currentController.value.isInitialized) {
      return;
    }
    var next = target;
    if (next < Duration.zero) next = Duration.zero;
    if (duration > Duration.zero && next > duration) next = duration;
    _endedLatch = false;
    if (showUpNext) showUpNext = false;
    await currentController.seekTo(next);
    position.value = next;
    notifyListeners();
  }

  Future<void> seekBy(Duration delta) async {
    final currentController = controller;
    if (currentController == null || !currentController.value.isInitialized) {
      return;
    }
    await seekTo(currentController.value.position + delta);
  }

  Future<void> skipNext() async {
    if (!canSkipNext) return;
    if (mode == PlaybackRepeatMode.shuffle) {
      await _goTo(_takeShuffleNext());
      return;
    }
    if (index + 1 < queue.length) {
      await _goTo(index + 1);
      return;
    }
    if (mode == PlaybackRepeatMode.all && queue.isNotEmpty) {
      await _goTo(0);
    }
  }

  Future<void> skipPrevious() async {
    final currentController = controller;
    if (currentController != null &&
        currentController.value.isInitialized &&
        currentController.value.position > const Duration(seconds: 3)) {
      showUpNext = false;
      _endedLatch = false;
      await currentController.seekTo(Duration.zero);
      await currentController.play();
      notifyListeners();
      return;
    }
    if (mode == PlaybackRepeatMode.shuffle && _history.isNotEmpty) {
      await _goTo(_history.removeLast());
      return;
    }
    if (index > 0) {
      await _goTo(index - 1);
      return;
    }
    if (mode == PlaybackRepeatMode.all && queue.length > 1) {
      await _goTo(queue.length - 1);
    }
  }

  Future<void> playUpcoming() async {
    final next = upcoming;
    if (next == null) return;
    await _goTo(index + 1);
  }

  Future<void> openExternal() async {
    final item = current;
    if (item == null || item.isAudio) {
      throw Exception('Could not open this video in another app');
    }
    final token = _token;
    final path = await _cacheForPlayback(item, token);
    if (token != _token) return;
    final result = await OpenFile.open(path, type: 'video/*');
    if (result.type != ResultType.done) {
      throw Exception(result.message);
    }
    close();
  }

  Future<void> _goTo(int next) async {
    if (next < 0 || next >= queue.length) return;
    index = next;
    showUpNext = false;
    notifyListeners();
    await _loadCurrent();
  }

  Future<void> _loadCurrent() async {
    final token = ++_token;
    final item = current;
    if (item == null) return;
    _cacheCancel?.cancel('replaced');
    _endedLatch = false;
    showUpNext = false;
    loading = true;
    error = null;
    status = 'Loading...';
    duration = Duration.zero;
    position.value = Duration.zero;
    playing.value = false;
    await _disposeController();
    if (token != _token) return;
    notifyListeners();

    try {
      final headers = await UploadService.instance.authHeaders();
      if (token != _token) return;
      await _startController(
        token,
        VideoPlayerController.networkUrl(
          Uri.parse(UploadService.mediaStreamUrl(item.id)),
          httpHeaders: headers,
          viewType: _viewType(item.isAudio),
        ),
      );
      return;
    } catch (_) {
      if (token != _token) return;
    }

    if (item.isAudio) {
      if (token != _token || !active) return;
      loading = false;
      error = 'Could not play this audio file';
      notifyListeners();
      return;
    }

    try {
      if (token != _token) return;
      status = 'Preparing a local copy...';
      notifyListeners();
      final path = await _cacheForPlayback(item, token);
      if (token != _token) return;
      await _startController(
        token,
        VideoPlayerController.file(
          File(path),
          viewType: _viewType(false),
        ),
      );
      return;
    } catch (_) {
      if (token != _token) return;
    }

    try {
      if (token != _token) return;
      status = 'Opening in the phone player...';
      notifyListeners();
      await openExternal();
    } catch (_) {
      if (token != _token || !active) return;
      loading = false;
      error = 'Could not play this video on this phone';
      notifyListeners();
    }
  }

  VideoViewType _viewType(bool isAudio) {
    if (!isAudio &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android) {
      return VideoViewType.platformView;
    }
    return VideoViewType.textureView;
  }

  Future<void> _startController(
    int token,
    VideoPlayerController next,
  ) async {
    try {
      await next.initialize();
      if (token != _token) {
        await next.dispose();
        return;
      }
      if (next.value.hasError) {
        throw StateError(next.value.errorDescription ?? 'decode failed');
      }
      next.addListener(_onTick);
      await next.play();
      if (token != _token) {
        next.removeListener(_onTick);
        await next.dispose();
        return;
      }
      await _disposeController();
      controller = next;
      duration = next.value.duration;
      position.value = next.value.position;
      playing.value = next.value.isPlaying;
      loading = false;
      error = null;
      status = null;
      notifyListeners();
    } catch (_) {
      next.removeListener(_onTick);
      await next.dispose();
      rethrow;
    }
  }

  Future<void> _disposeController() async {
    final old = controller;
    controller = null;
    if (old == null) return;
    old.removeListener(_onTick);
    try {
      await old.pause();
    } catch (_) {}
    await old.dispose();
  }

  void _onTick() {
    final currentController = controller;
    if (currentController == null) return;
    final value = currentController.value;
    if (value.hasError) {
      if (error == null) {
        final item = current;
        error = item?.isAudio == true
            ? 'Could not play this audio file'
            : 'Could not play this video on this phone';
        loading = false;
        notifyListeners();
      }
      return;
    }

    if (position.value != value.position) {
      position.value = value.position;
    }
    if (playing.value != value.isPlaying) {
      playing.value = value.isPlaying;
      notifyListeners();
    }
    if (value.duration > Duration.zero && value.duration != duration) {
      duration = value.duration;
      notifyListeners();
    }
    _maybeHandleEnd(value);
  }

  void _maybeHandleEnd(VideoPlayerValue value) {
    final length = value.duration;
    if (!value.isInitialized || length <= const Duration(milliseconds: 400)) {
      return;
    }
    final atEnd = length - value.position <= const Duration(milliseconds: 280);
    if (!atEnd) {
      _endedLatch = false;
      return;
    }
    if (_endedLatch || value.isPlaying) return;
    _endedLatch = true;
    unawaited(_handleEnd());
  }

  Future<void> _handleEnd() async {
    switch (mode) {
      case PlaybackRepeatMode.one:
        await _restart();
      case PlaybackRepeatMode.all:
        if (queue.length <= 1) {
          await _restart();
          return;
        }
        await _goTo((index + 1) % queue.length);
      case PlaybackRepeatMode.shuffle:
        if (queue.length <= 1) {
          await _restart();
          return;
        }
        await _goTo(_takeShuffleNext());
      case PlaybackRepeatMode.none:
        if (upcoming != null) {
          showUpNext = true;
          notifyListeners();
        }
    }
  }

  Future<void> _restart() async {
    final currentController = controller;
    if (currentController == null || !currentController.value.isInitialized) {
      return;
    }
    showUpNext = false;
    _endedLatch = true;
    await currentController.seekTo(Duration.zero);
    await currentController.play();
    notifyListeners();
  }

  int _takeShuffleNext() {
    if (_shuffleBag.isEmpty) _refillShuffle(exclude: index);
    if (_shuffleBag.isEmpty) return index;
    _history.add(index);
    return _shuffleBag.removeAt(0);
  }

  void _refillShuffle({required int exclude}) {
    final bag = <int>[
      for (var i = 0; i < queue.length; i++)
        if (i != exclude) i,
    ];
    bag.shuffle(Random());
    _shuffleBag = bag;
  }

  Future<String> _cacheForPlayback(MediaQueueItem item, int token) async {
    final headers = await UploadService.instance.authHeaders();
    if (token != _token) {
      throw StateError('cancelled');
    }
    final dir = await getTemporaryDirectory();
    final safe = item.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final path = '${dir.path}/play_${item.id}_$safe';
    final file = File(path);
    if (await file.exists() && await file.length() > 0) {
      return path;
    }
    final cancel = CancelToken();
    _cacheCancel = cancel;
    try {
      await Dio().download(
        UploadService.mediaStreamUrl(item.id),
        path,
        cancelToken: cancel,
        options: Options(
          headers: headers,
          receiveTimeout: const Duration(minutes: 20),
        ),
      );
    } on DioException catch (error) {
      if (CancelToken.isCancel(error) || token != _token) {
        throw StateError('cancelled');
      }
      rethrow;
    }
    if (token != _token) {
      throw StateError('cancelled');
    }
    return path;
  }

  void _syncExpanded() {
    final next = isExpanded;
    if (expanded.value != next) expanded.value = next;
  }
}
