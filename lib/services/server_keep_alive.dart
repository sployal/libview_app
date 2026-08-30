import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';

import 'upload_service.dart';

/// Pings Render `/health` while the app is in the foreground so the free
/// instance does not spin down after 15 minutes of no inbound traffic.
class ServerKeepAlive with WidgetsBindingObserver {
  ServerKeepAlive._();

  static final ServerKeepAlive instance = ServerKeepAlive._();

  static const Duration _interval = Duration(minutes: 11);

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: UploadService.baseUrl,
      connectTimeout: const Duration(seconds: 90),
      receiveTimeout: const Duration(seconds: 90),
    ),
  );

  Timer? _timer;
  bool _started = false;
  bool _inFlight = false;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _onForeground();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _onForeground();
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _stopTimer();
      case AppLifecycleState.inactive:
        break;
    }
  }

  void _onForeground() {
    _ping();
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) => _ping());
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _ping() async {
    if (_inFlight) return;
    _inFlight = true;
    try {
      await _dio.get<dynamic>('/health');
    } catch (_) {
      // Cold starts and offline devices are expected; the next tick retries.
    } finally {
      _inFlight = false;
    }
  }
}
