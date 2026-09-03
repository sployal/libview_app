import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Tracks real startup work and keeps the splash overlay up until
/// the destination screen (home, auth, or onboarding) is ready to show.
class StartupOverlay extends ChangeNotifier {
  StartupOverlay._();

  static final StartupOverlay instance = StartupOverlay._();

  double _progress = 0.08;
  bool _visible = true;
  bool _completing = false;
  bool _awaitingHome = false;

  double get progress => _progress;
  bool get visible => _visible;
  bool get awaitingHome => _awaitingHome;

  void setProgress(double value) {
    if (_completing) return;
    final next = value.clamp(0.0, 0.98);
    if (next <= _progress) return;
    _progress = next;
    _notifySafe();
  }

  void expectHome() {
    if (_completing) return;
    _awaitingHome = true;
    setProgress(0.48);
  }

  void revealDestination() {
    _awaitingHome = false;
    complete();
  }

  void _notifySafe() {
    final notify = notifyListeners;
    WidgetsBinding.instance.addPostFrameCallback((_) => notify());
  }

  void completeIfAwaitingHome() {
    if (_awaitingHome) complete();
  }

  void complete() {
    if (_completing) return;
    _completing = true;
    _awaitingHome = false;
    _progress = 1;
    _notifySafe();
  }

  void hide() {
    if (!_visible) return;
    _visible = false;
    _notifySafe();
  }
}

class AppSplashScreen extends StatelessWidget {
  const AppSplashScreen({super.key, this.progress});

  final double? progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final background = theme.scaffoldBackgroundColor;
    final muted = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
    final percent = ((progress ?? 0) * 100).clamp(0, 100).round();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
          .copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: background,
        systemNavigationBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 18,
                    backgroundColor: scheme.primary.withOpacity(0.14),
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Loading $percent%',
                  style: TextStyle(
                    color: muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
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

/// Theme-matched placeholder while auth/profile resolve under the overlay.
class StartupHold extends StatelessWidget {
  const StartupHold({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    );
  }
}

class SplashGate extends StatefulWidget {
  const SplashGate({super.key, required this.child});

  final Widget child;

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  static const _fadeDuration = Duration(milliseconds: 220);
  bool _fading = false;

  @override
  void initState() {
    super.initState();
    StartupOverlay.instance.addListener(_onOverlay);
    Future<void>.delayed(const Duration(seconds: 15), () {
      if (StartupOverlay.instance.visible) {
        StartupOverlay.instance.complete();
      }
    });
  }

  @override
  void dispose() {
    StartupOverlay.instance.removeListener(_onOverlay);
    super.dispose();
  }

  void _onOverlay() {
    final overlay = StartupOverlay.instance;
    if (overlay.progress >= 1 && overlay.visible && !_fading) {
      _fading = true;
      if (mounted) setState(() {});
      Future<void>.delayed(_fadeDuration, () {
        overlay.hide();
      });
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final overlay = StartupOverlay.instance;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (overlay.visible)
          IgnorePointer(
            child: AnimatedOpacity(
              opacity: _fading ? 0 : 1,
              duration: _fadeDuration,
              curve: Curves.easeOut,
              child: AppSplashScreen(progress: overlay.progress),
            ),
          ),
      ],
    );
  }
}
