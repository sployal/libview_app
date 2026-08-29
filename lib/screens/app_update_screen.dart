import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_update_service.dart';
import '../ui/app_splash_screen.dart';
import '../services/download_service.dart';

class AppUpdateGate extends StatefulWidget {
  const AppUpdateGate({super.key, required this.child});

  final Widget child;

  @override
  State<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends State<AppUpdateGate>
    with WidgetsBindingObserver {
  AppUpdateRelease? _requiredUpdate;
  bool _checking = false;
  bool _pendingCheck = false;
  StreamSubscription<User?>? _authSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authSub = FirebaseAuth.instance.authStateChanges().listen((_) {
      _checkForUpdate();
    });
    _checkForUpdate();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkForUpdate();
    }
  }

  Future<void> _checkForUpdate() async {
    if (_checking) {
      _pendingCheck = true;
      return;
    }
    _checking = true;
    try {
      final release = await AppUpdateService.findRequiredUpdate();
      if (!mounted) return;
      setState(() => _requiredUpdate = release);
    } finally {
      _checking = false;
      if (_pendingCheck) {
        _pendingCheck = false;
        _checkForUpdate();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final release = _requiredUpdate;
    if (release == null) return widget.child;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      StartupOverlay.instance.revealDestination();
    });
    return AppUpdateScreen(release: release);
  }
}

class AppUpdateScreen extends StatefulWidget {
  const AppUpdateScreen({super.key, required this.release});

  final AppUpdateRelease release;

  @override
  State<AppUpdateScreen> createState() => _AppUpdateScreenState();
}

class _AppUpdateScreenState extends State<AppUpdateScreen> {
  bool _busy = false;
  double? _progress;
  String? _error;
  File? _apkFile;

  Future<void> _update() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      var apk = _apkFile;
      if (apk == null || !await apk.exists()) {
        apk = await AppUpdateService.downloadApk(
          widget.release,
          onProgress: (value) {
            if (!mounted) return;
            setState(() => _progress = value);
          },
        );
        if (!mounted) return;
        setState(() => _apkFile = apk);
      }

      await AppUpdateService.installApk(apk);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final release = widget.release;
    final sizeLabel = release.sizeBytes != null
        ? DownloadService.formatFileSize(release.sizeBytes!)
        : null;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor:
            isDark ? const Color(0xFF111827) : const Color(0xFFF8FAFC),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              children: [
                const Spacer(flex: 2),
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.system_update_alt_rounded,
                    size: 44,
                    color: Color(0xFF6366F1),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'Update required',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : const Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'A newer Edupal build is available. Install it to keep using the app.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.45,
                    color: isDark
                        ? const Color(0xFF9CA3AF)
                        : const Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 28),
                _VersionCard(
                  isDark: isDark,
                  currentLabel: AppUpdateService.currentApkLabel,
                  nextLabel: release.versionLabel,
                  fileName: release.fileName,
                  sizeLabel: sizeLabel,
                ),
                if (_busy) ...[
                  const SizedBox(height: 28),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: _progress,
                      minHeight: 8,
                      backgroundColor: const Color(0xFF6366F1).withOpacity(0.16),
                      color: const Color(0xFF6366F1),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _progress == null
                        ? 'Preparing download…'
                        : 'Downloading ${(100 * _progress!).clamp(0, 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark
                          ? const Color(0xFF9CA3AF)
                          : const Color(0xFF6B7280),
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFEF4444),
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
                const Spacer(flex: 3),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: _busy
                        ? null
                        : () {
                            HapticFeedback.lightImpact();
                            _update();
                          },
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1),
                      disabledBackgroundColor:
                          const Color(0xFF6366F1).withOpacity(0.45),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      _apkFile != null ? 'Install update' : 'Download and install',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Android will ask you to confirm the install.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? const Color(0xFF6B7280)
                        : const Color(0xFF9CA3AF),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VersionCard extends StatelessWidget {
  const _VersionCard({
    required this.isDark,
    required this.currentLabel,
    required this.nextLabel,
    required this.fileName,
    this.sizeLabel,
  });

  final bool isDark;
  final String currentLabel;
  final String nextLabel;
  final String fileName;
  final String? sizeLabel;

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? const Color(0xFF1F2937) : Colors.white;
    final muted =
        isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.06)
              : const Color(0xFF6366F1).withOpacity(0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row('Installed', currentLabel, muted),
          const SizedBox(height: 10),
          _row('Available', nextLabel, const Color(0xFF6366F1)),
          const SizedBox(height: 10),
          _row(
            'File',
            sizeLabel == null ? fileName : '$fileName · $sizeLabel',
            muted,
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, Color valueColor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 78,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? const Color(0xFF6B7280) : const Color(0xFF9CA3AF),
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: valueColor,
            ),
          ),
        ),
      ],
    );
  }
}
