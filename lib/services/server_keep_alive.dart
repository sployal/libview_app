import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';

import 'auth_service.dart';
import 'upload_service.dart';

/// Pings Render `/health` while the app is in the foreground so the free
/// instance does not spin down after 15 minutes of no inbound traffic.
/// Students and signed-out users never send this ping.
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
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _profileSub;
  bool _started = false;
  bool _inFlight = false;
  bool _allowed = false;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    AuthService.instance.authStateChanges.listen(_onAuthChanged);
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

  void _onAuthChanged(User? user) {
    _profileSub?.cancel();
    _profileSub = null;
    if (user == null) {
      _setAllowed(false);
      return;
    }
    _profileSub = AuthService.instance.profileDocStream(user.uid).listen((doc) {
      final role = (doc.data()?['role'] as String?)?.toLowerCase().trim();
      _setAllowed(role != null && role.isNotEmpty && role != 'student');
    });
  }

  void _setAllowed(bool allowed) {
    _allowed = allowed;
    if (!allowed) {
      _stopTimer();
      return;
    }
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle == null || lifecycle == AppLifecycleState.resumed) {
      _onForeground();
    }
  }

  void _onForeground() {
    if (!_allowed) {
      _stopTimer();
      return;
    }
    _ping();
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) => _ping());
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _ping() async {
    if (!_allowed || _inFlight) return;
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
