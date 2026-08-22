import 'dart:async';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/download_service.dart';
import '../services/notification_service.dart';
import '../services/streak_service.dart';
import 'downloads_screen.dart';
import 'notifications_screen.dart';

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
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));
    _slideController.forward();
    WidgetsBinding.instance.addObserver(this);
    _loadRecentActivity();
    _loadUnreadNotificationCount();
    _setupNotificationSubscription();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    ]);
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

  String _getStreakEmoji(int streak) {
    return streak == 0 ? '📚' : '🔥';
  }

  String _getStreakMessage(int streak) {
    if (streak == 0) return 'Start your streak today!';
    if (streak == 1) return 'Great start! Keep it up!';
    if (streak < 7) return 'You\'re on fire!';
    if (streak < 14) return 'Amazing dedication!';
    if (streak < 30) return 'Unstoppable!';
    return 'Legendary streak!';
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
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  Color _getFileColor(String type) {
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

  IconData _getFileIcon(String type) {
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

  String _getTimeAgo(DownloadItem download) {
    try {
      final date = DateTime.parse(download.date);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays > 0) {
        return '${difference.inDays} ${difference.inDays == 1 ? 'day' : 'days'} ago';
      } else if (difference.inHours > 0) {
        return '${difference.inHours} ${difference.inHours == 1 ? 'hour' : 'hours'} ago';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes} ${difference.inMinutes == 1 ? 'minute' : 'minutes'} ago';
      } else {
        return 'Just now';
      }
    } catch (e) {
      return download.date;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: SlideTransition(
          position: _slideAnimation,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header with notification icon
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Welcome back! 👋',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1F2937),
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Continue your learning journey',
                              style: TextStyle(
                                fontSize: 16,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Notification Icon with Badge
                      Stack(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 10,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: IconButton(
                              icon: const Icon(
                                Icons.notifications_rounded,
                                color: Color(0xFF6366F1),
                                size: 28,
                              ),
                              onPressed: () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (ctx) => const NotificationsScreen(),
                                  ),
                                );
                                // Reload unread count when returning
                                _loadUnreadNotificationCount();
                              },
                            ),
                          ),
                          if (unreadNotificationCount > 0)
                            Positioned(
                              right: 8,
                              top: 8,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Color(0xFFEF4444),
                                  shape: BoxShape.circle,
                                ),
                                constraints: const BoxConstraints(
                                  minWidth: 18,
                                  minHeight: 18,
                                ),
                                child: Center(
                                  child: Text(
                                    unreadNotificationCount > 99
                                        ? '99+'
                                        : unreadNotificationCount.toString(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _buildStreakTracker(),
                  const SizedBox(height: 20),
                  _buildQuickStats(),
                  const SizedBox(height: 30),
                  _buildRecentActivity(),
                  const SizedBox(height: 30),
                  _buildQuickActions(),
                  const SizedBox(height: 30),
                  _buildCalendar(),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStreakTracker() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: currentStreak > 0
              ? [const Color(0xFFFF6B6B), const Color(0xFFFF8E53)]
              : [const Color(0xFF94A3B8), const Color(0xFF64748B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: (currentStreak > 0
                    ? const Color(0xFFFF6B6B)
                    : const Color(0xFF94A3B8))
                .withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _getStreakEmoji(currentStreak),
                  style: const TextStyle(fontSize: 28, height: 1),
                ),
                const SizedBox(height: 2),
                Text(
                  '$currentStreak',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Study Streak',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _getStreakMessage(currentStreak),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      Icons.emoji_events_rounded,
                      color: Colors.white.withOpacity(0.8),
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Best: $longestStreak ${longestStreak == 1 ? 'day' : 'days'}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStats() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your Progress',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  'Downloaded',
                  totalDownloads.toString(),
                  Icons.download_rounded,
                ),
              ),
              Container(
                height: 40,
                width: 1,
                color: Colors.white.withOpacity(0.3),
              ),
              Expanded(
                child: _buildStatItem(
                  'Recent',
                  recentDownloads.length.toString(),
                  Icons.history_rounded,
                ),
              ),
              Container(
                height: 40,
                width: 1,
                color: Colors.white.withOpacity(0.3),
              ),
              Expanded(
                child: _buildStatItem(
                  'Available',
                  totalDownloads.toString(),
                  Icons.folder_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 24),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildRecentActivity() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Recent Activity',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1F2937),
              ),
            ),
            if (recentDownloads.isNotEmpty)
              TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (ctx) => const DownloadsScreen(),
                    ),
                  );
                },
                child: const Text(
                  'View All',
                  style: TextStyle(
                    color: Color(0xFF6366F1),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (!_downloadsLoaded)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Color(0xFF6366F1),
                  ),
                ),
              ),
            ),
          )
        else if (recentDownloads.isEmpty)
          Container(
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    Icons.download_rounded,
                    size: 48,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No recent activity',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Downloaded files will appear here',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ...recentDownloads.map((download) => _buildActivityItem(download)),
      ],
    );
  }

  Widget _buildActivityItem(DownloadItem download) {
    final fileColor = _getFileColor(download.type);
    final fileIcon = _getFileIcon(download.type);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openFile(download),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: fileColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    fileIcon,
                    color: fileColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        download.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1F2937),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${download.subject} • ${_getTimeAgo(download)}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: fileColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    download.type,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: fileColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Actions',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1F2937),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildActionCard(
                'View Downloads',
                Icons.download_rounded,
                const Color(0xFF10B981),
                () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (ctx) => const DownloadsScreen(),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildActionCard(
                'Browse Files',
                Icons.folder_rounded,
                const Color(0xFF6366F1),
                () {
                  DefaultTabController.of(context).animateTo(1);
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

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

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  bool _isStreakDay(DateTime day) {
    if (currentStreak <= 0) return false;
    final date = DateTime(day.year, day.month, day.day);
    final start = _today.subtract(Duration(days: currentStreak - 1));
    return !date.isBefore(start) && !date.isAfter(_today);
  }

  void _changeMonth(int delta) {
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

  Widget _buildCalendar() {
    final year = _visibleMonth.year;
    final month = _visibleMonth.month;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final leadingEmpty = DateTime(year, month, 1).weekday % 7;
    final cellCount = leadingEmpty + daysInMonth;
    final rowCount = ((cellCount + 6) ~/ 7);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Calendar',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1F2937),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(8, 14, 8, 14),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => _changeMonth(-1),
                      icon: const Icon(
                        Icons.chevron_left_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            '${_monthNames[month - 1]} $year',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _selectedDayCaption(),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.85),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => _changeMonth(1),
                      icon: const Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
                child: Row(
                  children: _weekdayLabels
                      .map(
                        (label) => Expanded(
                          child: Text(
                            label,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF9CA3AF),
                              letterSpacing: 0.6,
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
                        final date = DateTime(year, month, dayNumber);
                        return Expanded(child: _buildCalendarDay(date));
                      }),
                    );
                  }),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
                child: Row(
                  children: [
                    _buildCalendarLegend(
                      color: const Color(0xFF6366F1),
                      label: 'Today',
                      filled: true,
                    ),
                    const SizedBox(width: 16),
                    _buildCalendarLegend(
                      color: const Color(0xFFFF6B6B),
                      label: 'Study streak',
                      filled: false,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCalendarLegend({
    required Color color,
    required String label,
    required bool filled,
  }) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
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

  Widget _buildCalendarDay(DateTime date) {
    final isToday = _isSameDay(date, _today);
    final isSelected = _isSameDay(date, _selectedDay);
    final isStreak = _isStreakDay(date) && !isToday;
    final isWeekend = date.weekday == DateTime.saturday ||
        date.weekday == DateTime.sunday;

    Color textColor = isWeekend
        ? const Color(0xFF9CA3AF)
        : const Color(0xFF1F2937);
    if (isToday || isSelected) textColor = Colors.white;
    if (isStreak && !isSelected) textColor = const Color(0xFFFF6B6B);

    BoxDecoration decoration;
    if (isToday) {
      decoration = BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withOpacity(0.4),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      );
    } else if (isSelected) {
      decoration = const BoxDecoration(
        color: Color(0xFF1F2937),
        shape: BoxShape.circle,
      );
    } else if (isStreak) {
      decoration = BoxDecoration(
        color: const Color(0xFFFF6B6B).withOpacity(0.12),
        shape: BoxShape.circle,
      );
    } else {
      decoration = const BoxDecoration(shape: BoxShape.circle);
    }

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedDay = date;
        });
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

  Widget _buildActionCard(
    String title,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1F2937),
              ),
            ),
          ],
        ),
      ),
    );
  }
}