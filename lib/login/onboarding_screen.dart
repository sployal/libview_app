import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/adaptive_layout.dart';

class OnboardingPage {
  const OnboardingPage({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.onGetStarted,
    required this.onSignIn,
  });

  final VoidCallback onGetStarted;
  final VoidCallback onSignIn;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _accent = Color(0xFF6366F1);
  static const _accentDeep = Color(0xFF8B5CF6);

  static const _pages = [
    OnboardingPage(
      icon: CupertinoIcons.book_fill,
      title: 'All your course files\nin one place',
      subtitle:
          'Open years, semesters, and units to read and download notes stored for your course.',
      accent: Color(0xFF6366F1),
    ),
    OnboardingPage(
      icon: CupertinoIcons.sparkles,
      title: 'Study with an\nAI tutor',
      subtitle:
          'Ask questions about your units, drop in photos of notes, and keep chats on this device.',
      accent: Color(0xFF8B5CF6),
    ),
    OnboardingPage(
      icon: CupertinoIcons.flame_fill,
      title: 'Stay consistent\nand organized',
      subtitle:
          'Build a study streak, track daily todos, and pick up downloads whenever you need them.',
      accent: Color(0xFFF59E0B),
    ),
  ];

  final _pageController = PageController();
  int _index = 0;

  bool get _isLast => _index == _pages.length - 1;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goNext() {
    HapticFeedback.selectionClick();
    if (_isLast) {
      widget.onGetStarted();
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7);
    final titleColor = isDark ? Colors.white : const Color(0xFF1C1C1E);
    final subtitleColor =
        isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70);
    final page = _pages[_index];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: background,
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                page.accent.withValues(alpha: isDark ? 0.28 : 0.16),
                background,
                background,
              ],
              stops: const [0, 0.42, 1],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: AdaptiveLayout.pagePadding(context),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: widget.onSignIn,
                      style: TextButton.styleFrom(
                        foregroundColor: subtitleColor,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 12,
                        ),
                      ),
                      child: const Text(
                        'Skip',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: _pages.length,
                      onPageChanged: (value) {
                        setState(() => _index = value);
                        HapticFeedback.selectionClick();
                      },
                      itemBuilder: (context, index) {
                        final item = _pages[index];
                        return _OnboardingSlide(
                          page: item,
                          titleColor: titleColor,
                          subtitleColor: subtitleColor,
                        );
                      },
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < _pages.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 240),
                          curve: Curves.easeOutCubic,
                          width: i == _index ? 22 : 8,
                          height: 8,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: i == _index
                                ? page.accent
                                : (isDark
                                    ? Colors.white.withValues(alpha: 0.18)
                                    : const Color(0xFFD1D1D6)),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: const LinearGradient(
                          colors: [_accent, _accentDeep],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _accent.withValues(alpha: 0.32),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: _goNext,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          _isLast ? 'Get started' : 'Continue',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: widget.onSignIn,
                    style: TextButton.styleFrom(
                      foregroundColor: titleColor,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(
                      'I already have an account',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: subtitleColor,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OnboardingSlide extends StatelessWidget {
  const _OnboardingSlide({
    required this.page,
    required this.titleColor,
    required this.subtitleColor,
  });

  final OnboardingPage page;
  final Color titleColor;
  final Color subtitleColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
      child: Column(
        children: [
          const Spacer(flex: 1),
          Container(
            width: 132,
            height: 132,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(36),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  page.accent,
                  Color.lerp(page.accent, const Color(0xFF8B5CF6), 0.45)!,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: page.accent.withValues(alpha: 0.38),
                  blurRadius: 32,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Icon(page.icon, size: 58, color: Colors.white),
          ),
          const SizedBox(height: 36),
          Text(
            'Edupal',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
              color: page.accent,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            page.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.9,
              height: 1.15,
              color: titleColor,
            ),
          ),
          const SizedBox(height: 14),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              page.subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w400,
                height: 1.45,
                color: subtitleColor,
                letterSpacing: -0.2,
              ),
            ),
          ),
          const Spacer(flex: 2),
        ],
      ),
    );
  }
}
