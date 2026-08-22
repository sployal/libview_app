import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../services/auth_service.dart';
import '../services/download_service.dart';
import '../services/notification_service.dart';
import '../services/streak_service.dart';
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
  AppNotification? _latestNotification;

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
      _loadLatestNotification();
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
      _loadLatestNotification(),
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

  Future<void> _loadLatestNotification() async {
    try {
      final list = await NotificationService.instance.listForCurrentUser();
      if (!mounted) return;
      setState(() {
        _latestNotification = list.isEmpty ? null : list.first;
      });
    } catch (e) {
      debugPrint('Error loading latest notification: $e');
    }
  }

  String _greetingTitle() {
    final hour = DateTime.now().hour;
    final name = _firstName;
    if (hour < 12) {
      return name == null ? 'Good morning ☀️' : 'Good morning, $name ☀️';
    }
    if (hour < 17) {
      return name == null ? 'Good afternoon 👋' : 'Good afternoon, $name 👋';
    }
    return name == null ? 'Good evening 🌙' : 'Good evening, $name 🌙';
  }

  String _greetingSubtitle() {
    if (currentStreak > 0) {
      return 'You\'re on a $currentStreak-day streak. Keep going.';
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
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _greetingTitle(),
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1F2937),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _greetingSubtitle(),
                              style: const TextStyle(
                                fontSize: 15,
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
                  if (_latestNotification != null) ...[
                    const SizedBox(height: 20),
                    _buildLatestUpdate(),
                  ],
                  const SizedBox(height: 20),
                  const _StudyFocusCard(),
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

  Widget _buildLatestUpdate() {
    final notification = _latestNotification;
    if (notification == null) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (ctx) => const NotificationsScreen(),
          ),
        );
        _loadUnreadNotificationCount();
        _loadLatestNotification();
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: (notification.isRead
                        ? const Color(0xFF6366F1)
                        : const Color(0xFFF59E0B))
                    .withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                notification.isRead
                    ? Icons.campaign_rounded
                    : Icons.mark_email_unread_rounded,
                color: notification.isRead
                    ? const Color(0xFF6366F1)
                    : const Color(0xFFF59E0B),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        notification.isRead ? 'Latest update' : 'New update',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF6B7280),
                          letterSpacing: 0.3,
                        ),
                      ),
                      if (!notification.isRead) ...[
                        const SizedBox(width: 8),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFFEF4444),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notification.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${notification.senderName} · ${timeago.format(notification.createdAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFF9CA3AF),
            ),
          ],
        ),
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
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionCard(
                'Browse Files',
                Icons.folder_rounded,
                const Color(0xFF6366F1),
                () {
                  const SwitchMainTabNotification(1).dispatch(context);
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionCard(
                'Ask AI',
                Icons.auto_awesome_rounded,
                const Color(0xFF8B5CF6),
                () {
                  const SwitchMainTabNotification(2).dispatch(context);
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
        padding: const EdgeInsets.all(14),
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
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
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
              borderRadius: BorderRadius.circular(10),
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
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0EA5E9), Color(0xFF6366F1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0EA5E9).withOpacity(0.28),
            blurRadius: 20,
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
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.timer_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Focus session',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'A quiet timer for reading and revision',
                      style: TextStyle(
                        color: Color(0xE6FFFFFF),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Text(
                _timeLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
              const Spacer(),
              if (_running || _remainingSeconds != _minutes * 60)
                IconButton(
                  onPressed: _reset,
                  icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: _toggle,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _running
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: const Color(0xFF6366F1),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _running ? 'Pause' : 'Start',
                        style: const TextStyle(
                          color: Color(0xFF6366F1),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: _progress,
              minHeight: 7,
              backgroundColor: Colors.white.withOpacity(0.22),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          const SizedBox(height: 16),
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
                          ? Colors.white
                          : Colors.white.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$minutes min',
                      style: TextStyle(
                        color: selected
                            ? const Color(0xFF4F46E5)
                            : Colors.white,
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