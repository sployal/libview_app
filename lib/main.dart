import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'services/streak_service.dart';
import 'services/theme_controller.dart';
import 'screens/home_screen.dart';
import 'screens/semesters_screen.dart';
import 'screens/downloads_screen.dart';
import 'screens/ai_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/no_internet_screen.dart';
import 'login/auth_screen.dart';
import 'screens/app_update_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await ThemeController.instance.load();

  runApp(const StudyApp());
}

class StudyApp extends StatelessWidget {
  const StudyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) {
        return MaterialApp(
          title: 'UniStudy',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            primarySwatch: Colors.blue,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF6366F1),
              brightness: Brightness.light,
            ),
            fontFamily: 'SF Pro Display',
            useMaterial3: true,
            scaffoldBackgroundColor: const Color(0xFFF8FAFC),
            appBarTheme: const AppBarTheme(
              elevation: 0,
              centerTitle: true,
              backgroundColor: Color(0xFFF8FAFC),
              foregroundColor: Color(0xFF1F2937),
              surfaceTintColor: Colors.transparent,
            ),
            splashFactory: NoSplash.splashFactory,
          ),
          darkTheme: ThemeData(
            primarySwatch: Colors.blue,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF6366F1),
              brightness: Brightness.dark,
            ),
            fontFamily: 'SF Pro Display',
            useMaterial3: true,
            scaffoldBackgroundColor: const Color(0xFF111827),
            appBarTheme: const AppBarTheme(
              elevation: 0,
              centerTitle: true,
              backgroundColor: Color(0xFF111827),
              foregroundColor: Color(0xFFF9FAFB),
              surfaceTintColor: Colors.transparent,
            ),
            splashFactory: NoSplash.splashFactory,
          ),
          themeMode: ThemeController.instance.mode,
          home: const AppUpdateGate(child: AuthGate()),
        );
      },
    );
  }
}

// Auth Gate - decides whether to show login or main screen
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<firebase_auth.User?>(
      stream: AuthService.instance.authStateChanges,
      builder: (context, snapshot) {
        // Show loading while checking auth state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        final user = snapshot.data;

        // If user is logged in, show main screen
        if (user != null) {
          return const MainScreen();
        }

        // Otherwise show auth screen
        return const AuthScreen();
      },
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _NestedNavigatorObserver extends NavigatorObserver {
  _NestedNavigatorObserver(this.onChanged);

  final VoidCallback onChanged;

  void _notify() => onChanged();

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _notify();

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _notify();

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _notify();

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _notify();
}

class _MainScreenState extends State<MainScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  int _selectedIndex = 0;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  final GlobalKey<NavigatorState> _homeNavigatorKey =
      GlobalKey<NavigatorState>();
  late final NavigatorObserver _homeNavObserver;

  List<Widget> get _screens => [
        Navigator(
          key: _homeNavigatorKey,
          observers: [_homeNavObserver],
          onGenerateRoute: (settings) {
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => const HomeScreen(),
            );
          },
        ),
        const SemestersScreen(),
        const AiScreen(),
        const DownloadsScreen(),
        const ProfileScreen(),
      ];

  bool get _homeNestedCanPop =>
      _selectedIndex == 0 &&
      (_homeNavigatorKey.currentState?.canPop() ?? false);

  @override
  void initState() {
    super.initState();
    _homeNavObserver = _NestedNavigatorObserver(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    });
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _animationController.forward();
    WidgetsBinding.instance.addObserver(this);
    StreakService.instance.recordDailyOpen();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      StreakService.instance.recordDailyOpen();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _selectTab(int index) async {
    if (index == _selectedIndex && index == 0) {
      _homeNavigatorKey.currentState?.popUntil((route) => route.isFirst);
      return;
    }

    const onlineRequiredTabs = {1, 2};
    if (onlineRequiredTabs.contains(index) && index != _selectedIndex) {
      if (!await NoInternetScreen.ensureOnline(context)) return;
    }
    if (!mounted) return;

    setState(() {
      _selectedIndex = index;
    });
    HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return NotificationListener<SwitchMainTabNotification>(
      onNotification: (notification) {
        _selectTab(notification.index);
        return true;
      },
      child: PopScope(
        canPop: !_homeNestedCanPop,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          _homeNavigatorKey.currentState?.maybePop();
        },
        child: Scaffold(
          extendBody: true,
          backgroundColor:
              isDark ? const Color(0xFF111827) : const Color(0xFFF8FAFC),
          body: FadeTransition(
            opacity: _fadeAnimation,
            child: IndexedStack(
              index: _selectedIndex,
              children: _screens,
            ),
          ),
          bottomNavigationBar: _AppBottomNav(
            selectedIndex: _selectedIndex,
            isDark: isDark,
            onTap: _selectTab,
          ),
        ),
      ),
    );
  }
}

class _AppBottomNav extends StatelessWidget {
  const _AppBottomNav({
    required this.selectedIndex,
    required this.isDark,
    required this.onTap,
  });

  final int selectedIndex;
  final bool isDark;
  final ValueChanged<int> onTap;

  static const _items = [
    (Icons.home_rounded, Icons.home_outlined, 'Home'),
    (Icons.school_rounded, Icons.school_outlined, 'Semesters'),
    (Icons.auto_awesome_rounded, Icons.auto_awesome_outlined, 'AI'),
    (Icons.download_rounded, Icons.download_outlined, 'Downloads'),
    (Icons.person_rounded, Icons.person_outline_rounded, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF6366F1);
    final surface = isDark ? const Color(0xFF1F2937) : Colors.white;
    const unselected = Color(0xFF9CA3AF);

    return Container(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(isDark ? 0.18 : 0.12),
            blurRadius: 28,
            offset: const Offset(0, -8),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.35 : 0.08),
            blurRadius: 18,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: isDark
                      ? Colors.white.withOpacity(0.08)
                      : accent.withOpacity(0.16),
                ),
              ),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.alphaBlend(
                    accent.withOpacity(isDark ? 0.16 : 0.10),
                    surface.withOpacity(isDark ? 0.88 : 0.94),
                  ),
                  surface.withOpacity(isDark ? 0.90 : 0.96),
                ],
              ),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                child: Row(
                  children: [
                    for (var i = 0; i < _items.length; i++)
                      Expanded(
                        child: _NavItem(
                          icon: selectedIndex == i
                              ? _items[i].$1
                              : _items[i].$2,
                          label: _items[i].$3,
                          selected: selectedIndex == i,
                          accent: accent,
                          unselected: unselected,
                          onTap: () => onTap(i),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.accent,
    required this.unselected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final Color accent;
  final Color unselected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? accent : unselected;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: selected ? accent.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: selected ? 1.08 : 1,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}