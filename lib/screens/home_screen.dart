import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../services/download_service.dart';
import '../services/notification_service.dart';
import '../services/streak_service.dart';
import 'browse_documents.dart';
import 'downloads_screen.dart';
import 'notifications_screen.dart';

class SwitchMainTabNotification extends Notification {
  const SwitchMainTabNotification(this.index);
  final int index;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

  List<DownloadItem> recentDownloads = [];
  int totalDownloads = 0;
  bool _downloadsLoaded = false;
  late int currentStreak;
  late int longestStreak;
  int unreadNotificationCount = 0;
  StreamSubscription? _notificationsSub;
  StreamSubscription? _readsSub;

  late DateTime _visibleMonth;
  late DateTime _selectedDay;
  String? _firstName;

  static const _weekdayLabels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
  static const _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month);
    _selectedDay = DateTime(now.year, now.month, now.day);
    final cachedStreak = StreakService.instance.cachedStreak;
    currentStreak = cachedStreak.currentStreak;
    longestStreak = cachedStreak.longestStreak;
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 520),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));
    _slideController.forward();
    WidgetsBinding.instance.addObserver(this);
    DownloadService.listVersion.addListener(_loadDownloads);
    _loadRecentActivity();
    _loadUnreadNotificationCount();
    _setupNotificationSubscription();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    DownloadService.listVersion.removeListener(_loadDownloads);
    _notificationsSub?.cancel();
    _readsSub?.cancel();
    _slideController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _recordAndLoadStreak();
    }
  }

  void _setupNotificationSubscription() {
    _notificationsSub = NotificationService.instance.snapshots().listen((_) {
      _loadUnreadNotificationCount();
    });
    final userId = AuthService.instance.currentUser?.uid;
    if (userId != null) {
      _readsSub =
          NotificationService.instance.readSnapshots(userId).listen((_) {
        _loadUnreadNotificationCount();
      });
    }
  }

  Future<void> _loadUnreadNotificationCount() async {
    try {
      final count =
          await NotificationService.instance.unreadCountForCurrentUser();
      if (mounted) {
        setState(() {
          unreadNotificationCount = count;
        });
      }
    } catch (e) {
      debugPrint('Error loading unread count: $e');
    }
  }

  Future<void> _loadRecentActivity() async {
    await Future.wait([
      _loadDownloads(),
      _recordAndLoadStreak(),
      _loadGreetingName(),
    ]);
  }

  Future<void> _loadGreetingName() async {
    try {
      final user = AuthService.instance.currentUser;
      if (user == null) return;
      final doc = await FirebaseFirestore.instance
          .collection('profiles')
          .doc(user.uid)
          .get();
      final fullName = (doc.data()?['full_name'] as String?)?.trim() ?? '';
      final first = fullName.split(RegExp(r'\s+')).firstWhere(
            (part) => part.isNotEmpty,
            orElse: () => '',
          );
      if (!mounted) return;
      setState(() {
        _firstName = first.isEmpty ? null : first;
      });
    } catch (e) {
      debugPrint('Error loading greeting name: $e');
    }
  }

  String _greetingTitle() {
    final hour = DateTime.now().hour;
    final name = _firstName;
    if (hour < 12) {
      return name == null ? 'Good morning' : 'Good morning, $name';
    }
    if (hour < 17) {
      return name == null ? 'Good afternoon' : 'Good afternoon, $name';
    }
    return name == null ? 'Good evening' : 'Good evening, $name';
  }

  String _greetingSubtitle() {
    if (currentStreak > 0) {
      return 'Day $currentStreak of your study streak.';
    }
    return 'Open a file or start a focus session to begin.';
  }

  Future<void> _loadDownloads() async {
    final downloads = await DownloadService.getDownloads();
    if (!mounted) return;
    setState(() {
      totalDownloads = downloads.length;
      recentDownloads = downloads.take(3).toList();
      _downloadsLoaded = true;
    });
  }

  Future<void> _recordAndLoadStreak() async {
    final streak = await StreakService.instance.recordDailyOpen();
    if (!mounted) return;
    setState(() {
      currentStreak = streak.currentStreak;
      longestStreak = streak.longestStreak;
    });
  }

  Future<void> _openFile(DownloadItem download) async {
    try {
      await DownloadService.openDownloadedFile(download);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  Color _fileColor(String type) {
    switch (type) {
      case 'PDF':
        return const Color(0xFFEF4444);
      case 'DOC':
        return const Color(0xFF3B82F6);
      case 'PPT':
        return const Color(0xFFF59E0B);
      case 'XLS':
        return const Color(0xFF10B981);
      case 'IMG':
        return const Color(0xFF8B5CF6);
      default:
        return const Color(0xFF6B7280);
    }
  }

  IconData _fileIcon(String type) {
    switch (type) {
      case 'PDF':
        return Icons.picture_as_pdf_rounded;
      case 'DOC':
        return Icons.description_rounded;
      case 'PPT':
        return Icons.slideshow_rounded;
      case 'XLS':
        return Icons.table_chart_rounded;
      case 'IMG':
        return Icons.image_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  String _timeAgo(DownloadItem download) {
    try {
      final date = DateTime.parse(download.date);
      final now = DateTime.now();
      final difference = now.difference(date);
      if (difference.inDays > 0) {
        return '${difference.inDays}d ago';
      }
      if (difference.inHours > 0) {
        return '${difference.inHours}h ago';
      }
      if (difference.inMinutes > 0) {
        return '${difference.inMinutes}m ago';
      }
      return 'Just now';
    } catch (_) {
      return download.date;
    }
  }

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  bool _isStreakDay(DateTime day) {
    if (currentStreak <= 0) return false;
    final date = DateTime(day.year, day.month, day.day);
    final start = _today.subtract(Duration(days: currentStreak - 1));
    return !date.isBefore(start) && !date.isAfter(_today);
  }

  void _changeMonth(int delta) {
    HapticFeedback.selectionClick();
    setState(() {
      _visibleMonth = DateTime(
        _visibleMonth.year,
        _visibleMonth.month + delta,
      );
    });
  }

  String _selectedDayCaption() {
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final day = DateTime(
      _selectedDay.year,
      _selectedDay.month,
      _selectedDay.day,
    );
    final label =
        '${weekdays[day.weekday - 1]}, ${_monthNames[day.month - 1]} ${day.day}';
    if (_isSameDay(day, _today)) {
      return currentStreak > 0
          ? '$label · keep the streak going'
          : '$label · start your streak today';
    }
    if (_isStreakDay(day)) return '$label · study day';
    if (day.isAfter(_today)) return '$label · upcoming';
    return label;
  }

  Future<void> _openNotifications() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
    _loadUnreadNotificationCount();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background =
        isDark ? const Color(0xFF111827) : const Color(0xFFF8FAFC);
    final titleColor =
        isDark ? const Color(0xFFF9FAFB) : const Color(0xFF111827);
    final muted = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
    final card = isDark ? const Color(0xFF1F2937) : Colors.white;

    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: SlideTransition(
          position: _slideAnimation,
          child: RefreshIndicator(
            color: const Color(0xFF6366F1),
            onRefresh: _loadRecentActivity,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _buildHeader(titleColor, muted, card, isDark),
                      const SizedBox(height: 20),
                      if (recentDownloads.isNotEmpty) ...[
                        _buildContinueCard(isDark),
                        const SizedBox(height: 16),
                      ],
                      _buildTodayCard(isDark, card, titleColor, muted),
                      const SizedBox(height: 16),
                      const _StudyFocusCard(),
                      const SizedBox(height: 28),
                      _sectionLabel('Shortcuts', muted),
                      const SizedBox(height: 12),
                      _buildShortcuts(isDark, card, titleColor, muted),
                      const SizedBox(height: 28),
                      _buildRecentsHeader(titleColor, muted),
                      const SizedBox(height: 12),
                      _buildRecents(isDark, card, titleColor, muted),
                      const SizedBox(height: 28),
                      _sectionLabel('Calendar', muted),
                      const SizedBox(height: 12),
                      _buildCalendar(isDark, card, titleColor, muted),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text, Color muted) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: muted,
      ),
    );
  }

  Widget _buildHeader(
    Color titleColor,
    Color muted,
    Color card,
    bool isDark,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _greetingTitle(),
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                  height: 1.15,
                  color: titleColor,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _greetingSubtitle(),
                style: TextStyle(
                  fontSize: 15,
                  height: 1.35,
                  color: muted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _NotificationButton(
          count: unreadNotificationCount,
          isDark: isDark,
          onTap: _openNotifications,
        ),
      ],
    );
  }

  Widget _buildContinueCard(bool isDark) {
    final download = recentDownloads.first;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openFile(download),
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(_fileIcon(download.type), color: Colors.white),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Continue',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withOpacity(0.8),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        download.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        '${download.subject} · ${_timeAgo(download)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withOpacity(0.82),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTodayCard(
    bool isDark,
    Color card,
    Color titleColor,
    Color muted,
  ) {
    final weekGoal = 7;
    final weekProgress = (currentStreak % weekGoal) / weekGoal;
    final ringValue = currentStreak == 0 ? 0.0 : (weekProgress == 0 ? 1.0 : weekProgress);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 86,
                height: 86,
                child: CustomPaint(
                  painter: _StreakRingPainter(
                    progress: ringValue,
                    trackColor: isDark
                        ? const Color(0xFF374151)
                        : const Color(0xFFEEF2FF),
                    progressColor: currentStreak > 0
                        ? const Color(0xFFF97316)
                        : const Color(0xFF94A3B8),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          currentStreak > 0 ? '🔥' : '📚',
                          style: const TextStyle(fontSize: 18, height: 1),
                        ),
                        Text(
                          '$currentStreak',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: titleColor,
                            height: 1.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      currentStreak > 0 ? 'On a streak' : 'Start a streak',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: titleColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      currentStreak > 0
                          ? 'Best run is $longestStreak ${longestStreak == 1 ? 'day' : 'days'}.'
                          : 'Open the app daily to build a habit.',
                      style: TextStyle(fontSize: 13, height: 1.35, color: muted),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _MiniStat(
                          label: 'Files',
                          value: _downloadsLoaded ? '$totalDownloads' : '—',
                          color: const Color(0xFF6366F1),
                        ),
                        const SizedBox(width: 18),
                        _MiniStat(
                          label: 'Best',
                          value: '$longestStreak',
                          color: const Color(0xFFF59E0B),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: List.generate(7, (index) {
              final day = _today.subtract(Duration(days: 6 - index));
              final active = _isStreakDay(day);
              final isToday = _isSameDay(day, _today);
              return Expanded(
                child: Column(
                  children: [
                    Text(
                      _weekdayLabels[day.weekday % 7],
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: muted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: active
                            ? const Color(0xFFF97316)
                            : (isDark
                                ? const Color(0xFF374151)
                                : const Color(0xFFF1F5F9)),
                        border: isToday && !active
                            ? Border.all(
                                color: const Color(0xFF6366F1),
                                width: 1.5,
                              )
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${day.day}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: active
                              ? Colors.white
                              : (isDark
                                  ? const Color(0xFFE5E7EB)
                                  : const Color(0xFF334155)),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildShortcuts(
    bool isDark,
    Color card,
    Color titleColor,
    Color muted,
  ) {
    final items = [
      _Shortcut(
        title: 'Units',
        subtitle: 'Years & semesters',
        icon: Icons.school_rounded,
        color: const Color(0xFF6366F1),
        onTap: () {
          HapticFeedback.lightImpact();
          const SwitchMainTabNotification(1).dispatch(context);
        },
      ),
      _Shortcut(
        title: 'Downloads',
        subtitle: '$totalDownloads saved',
        icon: Icons.download_rounded,
        color: const Color(0xFF10B981),
        onTap: () {
          HapticFeedback.lightImpact();
          const SwitchMainTabNotification(3).dispatch(context);
        },
      ),
      _Shortcut(
        title: 'Files',
        subtitle: 'On this phone',
        icon: Icons.folder_rounded,
        color: const Color(0xFF0EA5E9),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const BrowseDocumentsScreen()),
          );
        },
      ),
      _Shortcut(
        title: 'Ask AI',
        subtitle: 'Study help',
        icon: Icons.auto_awesome_rounded,
        color: const Color(0xFF8B5CF6),
        onTap: () {
          HapticFeedback.lightImpact();
          const SwitchMainTabNotification(2).dispatch(context);
        },
      ),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.55,
      children: items
          .map(
            (item) => Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: item.onTap,
                borderRadius: BorderRadius.circular(20),
                child: Ink(
                  decoration: BoxDecoration(
                    color: card,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      if (!isDark)
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: item.color.withOpacity(isDark ? 0.2 : 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(item.icon, color: item.color, size: 20),
                        ),
                        const Spacer(),
                        Text(
                          item.title,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: titleColor,
                          ),
                        ),
                        Text(
                          item.subtitle,
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildRecentsHeader(Color titleColor, Color muted) {
    return Row(
      children: [
        Expanded(child: _sectionLabel('Recents', muted)),
        if (recentDownloads.isNotEmpty)
          GestureDetector(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DownloadsScreen()),
              );
            },
            child: const Text(
              'See all',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6366F1),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildRecents(
    bool isDark,
    Color card,
    Color titleColor,
    Color muted,
  ) {
    if (!_downloadsLoaded) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
            ),
          ),
        ),
      );
    }

    if (recentDownloads.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
        decoration: BoxDecoration(
          color: card,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            Icon(Icons.downloading_rounded, size: 36, color: muted),
            const SizedBox(height: 10),
            Text(
              'Nothing downloaded yet',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: titleColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Files you save will show up here.',
              style: TextStyle(fontSize: 13, color: muted),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          for (var i = 0; i < recentDownloads.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                indent: 72,
                color: isDark
                    ? const Color(0xFF374151)
                    : const Color(0xFFF1F5F9),
              ),
            _buildRecentRow(recentDownloads[i], titleColor, muted),
          ],
        ],
      ),
    );
  }

  Widget _buildRecentRow(
    DownloadItem download,
    Color titleColor,
    Color muted,
  ) {
    final color = _fileColor(download.type);
    return InkWell(
      onTap: () => _openFile(download),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_fileIcon(download.type), color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    download.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${download.subject} · ${_timeAgo(download)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: muted),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: muted),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendar(
    bool isDark,
    Color card,
    Color titleColor,
    Color muted,
  ) {
    final year = _visibleMonth.year;
    final month = _visibleMonth.month;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final leadingEmpty = DateTime(year, month, 1).weekday % 7;
    final cellCount = leadingEmpty + daysInMonth;
    final rowCount = ((cellCount + 6) ~/ 7);

    return Container(
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => _changeMonth(-1),
                  icon: Icon(Icons.chevron_left_rounded, color: muted),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        '${_monthNames[month - 1]} $year',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: titleColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _selectedDayCaption(),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => _changeMonth(1),
                  icon: Icon(Icons.chevron_right_rounded, color: muted),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: _weekdayLabels
                  .map(
                    (label) => Expanded(
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: muted,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Column(
              children: List.generate(rowCount, (row) {
                return Row(
                  children: List.generate(7, (col) {
                    final index = row * 7 + col;
                    final dayNumber = index - leadingEmpty + 1;
                    if (dayNumber < 1 || dayNumber > daysInMonth) {
                      return const Expanded(child: SizedBox(height: 44));
                    }
                    return Expanded(
                      child: _buildCalendarDay(
                        DateTime(year, month, dayNumber),
                        isDark,
                        titleColor,
                        muted,
                      ),
                    );
                  }),
                );
              }),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Row(
              children: [
                _legendDot(const Color(0xFF6366F1), 'Today', filled: true),
                const SizedBox(width: 16),
                _legendDot(const Color(0xFFF97316), 'Streak', filled: false),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label, {required bool filled}) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: filled ? color : color.withOpacity(0.18),
            shape: BoxShape.circle,
            border: filled ? null : Border.all(color: color, width: 1.5),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF6B7280),
          ),
        ),
      ],
    );
  }

  Widget _buildCalendarDay(
    DateTime date,
    bool isDark,
    Color titleColor,
    Color muted,
  ) {
    final isToday = _isSameDay(date, _today);
    final isSelected = _isSameDay(date, _selectedDay);
    final isStreak = _isStreakDay(date) && !isToday;
    final isWeekend = date.weekday == DateTime.saturday ||
        date.weekday == DateTime.sunday;

    Color textColor = isWeekend ? muted : titleColor;
    if (isToday || isSelected) textColor = Colors.white;
    if (isStreak && !isSelected) textColor = const Color(0xFFF97316);

    BoxDecoration decoration;
    if (isToday) {
      decoration = const BoxDecoration(
        color: Color(0xFF6366F1),
        shape: BoxShape.circle,
      );
    } else if (isSelected) {
      decoration = BoxDecoration(
        color: isDark ? const Color(0xFF4B5563) : const Color(0xFF1F2937),
        shape: BoxShape.circle,
      );
    } else if (isStreak) {
      decoration = BoxDecoration(
        color: const Color(0xFFF97316).withOpacity(0.12),
        shape: BoxShape.circle,
      );
    } else {
      decoration = const BoxDecoration(shape: BoxShape.circle);
    }

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selectedDay = date);
      },
      child: SizedBox(
        height: 44,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 36,
            height: 36,
            decoration: decoration,
            alignment: Alignment.center,
            child: Text(
              '${date.day}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: isToday || isSelected || isStreak
                    ? FontWeight.w700
                    : FontWeight.w500,
                color: textColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationButton extends StatelessWidget {
  const _NotificationButton({
    required this.count,
    required this.isDark,
    required this.onTap,
  });

  final int count;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: isDark ? const Color(0xFF1F2937) : Colors.white,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: const SizedBox(
              width: 44,
              height: 44,
              child: Icon(
                Icons.notifications_rounded,
                color: Color(0xFF6366F1),
              ),
            ),
          ),
        ),
        if (count > 0)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444),
                borderRadius: BorderRadius.circular(10),
              ),
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              child: Text(
                count > 99 ? '99+' : '$count',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Color(0xFF9CA3AF),
          ),
        ),
      ],
    );
  }
}

class _Shortcut {
  const _Shortcut({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
}

class _StreakRingPainter extends CustomPainter {
  _StreakRingPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
  });

  final double progress;
  final Color trackColor;
  final Color progressColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) / 2) - 6;
    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    final arc = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, track);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(covariant _StreakRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.progressColor != progressColor ||
        oldDelegate.trackColor != trackColor;
  }
}

class _StudyFocusCard extends StatefulWidget {
  const _StudyFocusCard();

  @override
  State<_StudyFocusCard> createState() => _StudyFocusCardState();
}

class _StudyFocusCardState extends State<_StudyFocusCard> {
  static const _presets = [15, 25, 45];
  int _minutes = 25;
  int _remainingSeconds = 25 * 60;
  bool _running = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _timeLabel {
    final minutes = _remainingSeconds ~/ 60;
    final seconds = _remainingSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  double get _progress {
    final total = _minutes * 60;
    if (total <= 0) return 0;
    return 1 - (_remainingSeconds / total);
  }

  void _selectPreset(int minutes) {
    if (_running) return;
    setState(() {
      _minutes = minutes;
      _remainingSeconds = minutes * 60;
    });
  }

  void _toggle() {
    if (_running) {
      _timer?.cancel();
      setState(() => _running = false);
      return;
    }

    if (_remainingSeconds <= 0) {
      _remainingSeconds = _minutes * 60;
    }

    HapticFeedback.lightImpact();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_remainingSeconds <= 1) {
        _timer?.cancel();
        setState(() {
          _remainingSeconds = 0;
          _running = false;
        });
        HapticFeedback.mediumImpact();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Focus session complete. Nice work!'),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
        return;
      }
      setState(() => _remainingSeconds -= 1);
    });
    setState(() => _running = true);
  }

  void _reset() {
    _timer?.cancel();
    setState(() {
      _running = false;
      _remainingSeconds = _minutes * 60;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = isDark ? const Color(0xFF1F2937) : Colors.white;
    final title = isDark ? const Color(0xFFF9FAFB) : const Color(0xFF111827);
    final muted = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: _running
              ? const Color(0xFF6366F1).withOpacity(0.45)
              : (isDark ? const Color(0xFF374151) : const Color(0xFFF1F5F9)),
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.timer_rounded,
                  color: Color(0xFF6366F1),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Focus',
                      style: TextStyle(
                        color: title,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'A quiet timer for reading and revision',
                      style: TextStyle(color: muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                _timeLabel,
                style: TextStyle(
                  color: title,
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              if (_running || _remainingSeconds != _minutes * 60)
                IconButton(
                  onPressed: _reset,
                  icon: Icon(Icons.refresh_rounded, color: muted),
                ),
              GestureDetector(
                onTap: _toggle,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _running
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _running ? 'Pause' : 'Start',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: _progress,
              minHeight: 6,
              backgroundColor: isDark
                  ? const Color(0xFF374151)
                  : const Color(0xFFEEF2FF),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF6366F1),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: _presets.map((minutes) {
              final selected = _minutes == minutes;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => _selectPreset(minutes),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFF6366F1)
                          : (isDark
                              ? const Color(0xFF111827)
                              : const Color(0xFFF1F5F9)),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$minutes min',
                      style: TextStyle(
                        color: selected ? Colors.white : muted,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
