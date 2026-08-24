import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/connectivity_service.dart';

class NoInternetScreen extends StatefulWidget {
  const NoInternetScreen({super.key, this.onRetry});

  static const routeName = 'no_internet';

  final Future<void> Function()? onRetry;

  /// Returns true when the device is online. If offline, opens this screen
  /// and returns true only after the user reconnects and taps Try again.
  static Future<bool> ensureOnline(BuildContext context) async {
    if (await ConnectivityService.hasInternet()) return true;
    if (!context.mounted) return false;

    final currentName = ModalRoute.of(context)?.settings.name;
    if (currentName == routeName) return false;

    final restored = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        settings: const RouteSettings(name: routeName),
        fullscreenDialog: true,
        builder: (_) => const NoInternetScreen(),
      ),
    );
    return restored == true;
  }

  @override
  State<NoInternetScreen> createState() => _NoInternetScreenState();
}

class _NoInternetScreenState extends State<NoInternetScreen> {
  bool _checking = false;

  Future<void> _tryAgain() async {
    if (_checking) return;
    HapticFeedback.lightImpact();
    setState(() => _checking = true);
    final online = await ConnectivityService.hasInternet();
    if (!mounted) return;

    if (!online) {
      setState(() => _checking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Still no connection. Check Wi-Fi or mobile data.'),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    await widget.onRetry?.call();
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF111827) : const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: canPop
                    ? IconButton(
                        tooltip: 'Go back',
                        onPressed: () => Navigator.of(context).pop(false),
                        icon: Icon(
                          Icons.arrow_back_rounded,
                          color: isDark
                              ? const Color(0xFFF9FAFB)
                              : const Color(0xFF111827),
                        ),
                      )
                    : const SizedBox(height: 48),
              ),
              const Spacer(flex: 2),
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.wifi_off_rounded,
                  size: 46,
                  color: Color(0xFF6366F1),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'No internet connection',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : const Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'This action needs the internet. Connect to Wi-Fi or mobile data, then try again.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.45,
                  color: isDark
                      ? const Color(0xFF9CA3AF)
                      : const Color(0xFF6B7280),
                ),
              ),
              const Spacer(flex: 3),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _checking ? null : _tryAgain,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    disabledBackgroundColor:
                        const Color(0xFF6366F1).withOpacity(0.45),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _checking
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          'Try again',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
              if (canPop) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _checking
                      ? null
                      : () => Navigator.of(context).pop(false),
                  child: Text(
                    'Go back',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? const Color(0xFF9CA3AF)
                          : const Color(0xFF6B7280),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
