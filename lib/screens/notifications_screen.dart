import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../services/auth_service.dart';
import '../services/course_service.dart';
import '../services/notification_service.dart';
import '../ui/adaptive_layout.dart';
import 'create_notification_screen.dart';
import 'system_admin_dashboard.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  static const _accent = Color(0xFF6366F1);
  static const _danger = Color(0xFFEF4444);
  static const _success = Color(0xFF10B981);

  List<AppNotification> notifications = [];
  List<Course> _courses = [];
  bool isLoading = true;
  bool canCreateNotifications = false;
  bool _isSystemAdmin = false;
  String? currentUserRole;
  String _courseFilter = 'all';

  @override
  void initState() {
    super.initState();
    _loadNotifications();
    _checkUserRole();
  }

  Future<void> _checkUserRole() async {
    try {
      final role = await AuthService.instance.currentRole();
      final isSystemAdmin =
          await SystemAdminDashboard.isCurrentUserSystemAdmin();
      List<Course> courses = [];
      if (isSystemAdmin) {
        courses = await CourseService.instance.listCourses();
        courses.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      }
      if (!mounted) return;
      setState(() {
        currentUserRole = role;
        _isSystemAdmin = isSystemAdmin;
        _courses = courses;
        canCreateNotifications = role != 'student' || isSystemAdmin;
      });
    } catch (e) {
      debugPrint('Error checking user role: $e');
    }
  }

  List<AppNotification> get _visibleNotifications {
    if (!_isSystemAdmin || _courseFilter == 'all') {
      return notifications;
    }
    Course? selected;
    for (final course in _courses) {
      if (course.id == _courseFilter) {
        selected = course;
        break;
      }
    }
    if (selected == null) return notifications;
    final course = selected;
    return notifications
        .where((item) => NotificationService.matchesCourse(item, course))
        .toList();
  }

  Future<void> _loadNotifications() async {
    setState(() {
      isLoading = true;
    });

    try {
      final notificationsList =
          await NotificationService.instance.listForCurrentUser();

      if (!mounted) return;
      setState(() {
        notifications = notificationsList;
        isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading notifications: $e');
      if (mounted) {
        _showSnack('Error loading notifications: $e', _danger);
      }
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _markAsRead(String notificationId) async {
    try {
      await NotificationService.instance.markAsRead(notificationId);

      setState(() {
        final index = notifications.indexWhere((n) => n.id == notificationId);
        if (index != -1) {
          notifications[index] = notifications[index].copyWith(isRead: true);
        }
      });
    } catch (e) {
      debugPrint('Error marking notification as read: $e');
    }
  }

  Future<void> _markAllAsRead() async {
    try {
      await NotificationService.instance.markAllAsRead(
        _visibleNotifications.map((n) => n.id).toList(),
      );

      _loadNotifications();

      if (mounted) {
        _showSnack('All notifications marked as read', _success);
      }
    } catch (e) {
      debugPrint('Error marking all as read: $e');
    }
  }

  void _showSnack(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _editNotification(AppNotification notification) async {
    final titleController = TextEditingController(text: notification.title);
    final messageController = TextEditingController(text: notification.message);
    String selectedType = notification.type;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheet = isDark ? const Color(0xFF1F2937) : Colors.white;
    final titleColor =
        isDark ? const Color(0xFFF9FAFB) : const Color(0xFF111827);
    final muted = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(bottom: _sheetBottomInset(context)),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            decoration: BoxDecoration(
              color: sheet,
              borderRadius: BorderRadius.circular(28),
            ),
            child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 5,
                    decoration: BoxDecoration(
                      color: muted.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Edit Notification',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    color: titleColor,
                  ),
                ),
                const SizedBox(height: 20),
                _iosField(
                  controller: titleController,
                  label: 'Title',
                  titleColor: titleColor,
                  muted: muted,
                  isDark: isDark,
                ),
                const SizedBox(height: 12),
                _iosField(
                  controller: messageController,
                  label: 'Message',
                  titleColor: titleColor,
                  muted: muted,
                  isDark: isDark,
                  maxLines: 4,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedType,
                  style: TextStyle(color: titleColor, fontSize: 16),
                  dropdownColor: sheet,
                  decoration: _fieldDecoration('Type', muted, isDark),
                  items: const [
                    DropdownMenuItem(value: 'general', child: Text('General')),
                    DropdownMenuItem(
                        value: 'announcement', child: Text('Announcement')),
                    DropdownMenuItem(
                        value: 'assignment', child: Text('Assignment')),
                    DropdownMenuItem(value: 'exam', child: Text('Exam')),
                    DropdownMenuItem(value: 'event', child: Text('Event')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setModalState(() => selectedType = value);
                    }
                  },
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: titleColor,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          side: BorderSide(color: muted.withOpacity(0.3)),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          if (messageController.text.trim().isEmpty) {
                            _showSnack('Please enter a message', _danger);
                            return;
                          }

                          try {
                            await NotificationService.instance.update(
                              id: notification.id,
                              title: titleController.text.trim(),
                              message: messageController.text.trim(),
                              type: selectedType,
                            );

                            Navigator.of(context).pop();
                            _loadNotifications();

                            if (mounted) {
                              _showSnack(
                                'Notification updated successfully',
                                _success,
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              _showSnack('Error updating: $e', _danger);
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accent,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Update',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          ),
        ),
      ),
    );
  }

  /// Lift sheets above [MainScreen]'s nav when this screen is in a nested
  /// navigator (Home). From Profile the root route already covers the nav.
  double _sheetBottomInset(BuildContext sheetContext) {
    final keyboard = MediaQuery.viewInsetsOf(sheetContext).bottom;
    final host = context;
    final nested =
        Navigator.of(host) != Navigator.of(host, rootNavigator: true);
    final navClearance = nested
        ? AdaptiveLayout.bottomClearance(host)
        : MediaQuery.viewPaddingOf(host).bottom;
    return keyboard > navClearance ? keyboard : navClearance;
  }

  InputDecoration _fieldDecoration(String label, Color muted, bool isDark) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: muted),
      filled: true,
      fillColor: isDark ? const Color(0xFF111827) : const Color(0xFFF8FAFC),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _accent, width: 1.5),
      ),
    );
  }

  Widget _iosField({
    required TextEditingController controller,
    required String label,
    required Color titleColor,
    required Color muted,
    required bool isDark,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: TextStyle(color: titleColor, fontSize: 16),
      decoration: _fieldDecoration(label, muted, isDark),
    );
  }

  Future<void> _deleteNotification(String notificationId) async {
    try {
      await NotificationService.instance.delete(notificationId);
      _loadNotifications();
      if (mounted) {
        _showSnack('Notification deleted', _success);
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Error deleting notification: $e', _danger);
      }
    }
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'assignment':
        return const Color(0xFF3B82F6);
      case 'exam':
        return const Color(0xFFEF4444);
      case 'event':
        return const Color(0xFF8B5CF6);
      case 'announcement':
        return const Color(0xFFF59E0B);
      case 'general':
        return _accent;
      default:
        return _accent;
    }
  }

  IconData _getTypeIcon(String type) {
    switch (type) {
      case 'assignment':
        return CupertinoIcons.doc_text_fill;
      case 'exam':
        return CupertinoIcons.pencil_ellipsis_rectangle;
      case 'event':
        return CupertinoIcons.calendar;
      case 'announcement':
        return CupertinoIcons.speaker_2_fill;
      case 'general':
      default:
        return CupertinoIcons.bell_fill;
    }
  }

  Color _getRoleColor(String role) {
    switch (role.toLowerCase()) {
      case 'system_admin':
      case 'super_admin':
        return const Color(0xFF0F172A);
      case 'admin':
        return const Color(0xFFEF4444);
      case 'lecturer':
        return const Color(0xFF8B5CF6);
      case 'class_rep':
        return const Color(0xFFF59E0B);
      case 'assistant_class_rep':
        return const Color(0xFF06B6D4);
      case 'student':
      default:
        return const Color(0xFF10B981);
    }
  }

  IconData _getRoleIcon(String role) {
    switch (role.toLowerCase()) {
      case 'system_admin':
      case 'super_admin':
        return CupertinoIcons.shield_lefthalf_fill;
      case 'admin':
        return CupertinoIcons.gear_alt_fill;
      case 'lecturer':
        return CupertinoIcons.book_fill;
      case 'class_rep':
        return CupertinoIcons.person_2_fill;
      case 'assistant_class_rep':
        return CupertinoIcons.group_solid;
      case 'student':
      default:
        return CupertinoIcons.person_fill;
    }
  }

  String _formatRole(String role) {
    switch (role.toLowerCase()) {
      case 'system_admin':
      case 'super_admin':
        return 'System Admin';
      case 'class_rep':
        return 'Class Rep';
      case 'assistant_class_rep':
        return 'Assistant Class Rep';
      default:
        return role[0].toUpperCase() + role.substring(1);
    }
  }

  String _audienceLabel(AppNotification notification) {
    switch (notification.audience) {
      case 'class':
        if (notification.admissionPrefix.isNotEmpty &&
            notification.classSuffix.isNotEmpty) {
          return 'Class ${notification.admissionPrefix} / ${notification.classSuffix}';
        }
        return 'Class only';
      case 'course':
        if (notification.courseName.isNotEmpty) {
          return notification.courseName;
        }
        return 'Entire course';
      default:
        return 'Everyone';
    }
  }

  String _sectionFor(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return 'This Week';
    return 'Earlier';
  }

  List<({String label, List<AppNotification> items})> _grouped(
    List<AppNotification> items,
  ) {
    const order = ['Today', 'Yesterday', 'This Week', 'Earlier'];
    final map = <String, List<AppNotification>>{};
    for (final item in items) {
      map.putIfAbsent(_sectionFor(item.createdAt), () => []).add(item);
    }
    return [
      for (final label in order)
        if (map[label]?.isNotEmpty == true)
          (label: label, items: map[label]!),
    ];
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
    final divider = isDark ? const Color(0xFF374151) : const Color(0xFFE5E7EB);

    final visible = _visibleNotifications;
    final unreadCount = visible.where((n) => !n.isRead).length;
    final groups = _grouped(visible);

    return Scaffold(
      backgroundColor: background,
      body: isLoading
          ? Center(
              child: CupertinoActivityIndicator(
                color: isDark ? Colors.white : _accent,
                radius: 14,
              ),
            )
          : RefreshIndicator(
              color: _accent,
              onRefresh: _loadNotifications,
              child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                SliverAppBar(
                  pinned: true,
                  stretch: true,
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  backgroundColor: background,
                  systemOverlayStyle: isDark
                      ? SystemUiOverlayStyle.light
                      : SystemUiOverlayStyle.dark,
                  leading: IconButton(
                    icon: Icon(
                      CupertinoIcons.back,
                      color: titleColor,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  actions: [
                    if (unreadCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: TextButton(
                          onPressed: _markAllAsRead,
                          child: const Text(
                            'Clear All',
                            style: TextStyle(
                              color: _accent,
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    if (canCreateNotifications)
                      IconButton(
                        onPressed: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (ctx) =>
                                  const CreateNotificationScreen(),
                            ),
                          );
                          _loadNotifications();
                        },
                        icon: const Icon(
                          CupertinoIcons.add_circled_solid,
                          color: _accent,
                          size: 26,
                        ),
                      ),
                    const SizedBox(width: 8),
                  ],
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Notifications',
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.8,
                            color: titleColor,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          unreadCount > 0
                              ? '$unreadCount unread'
                              : 'You\'re all caught up',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_isSystemAdmin)
                  SliverToBoxAdapter(
                    child: _buildCourseFilterBar(card, titleColor, muted, divider),
                  ),
                if (visible.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _buildEmptyState(titleColor, muted),
                  )
                else
                  ...groups.expand((group) {
                    return [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(28, 22, 20, 8),
                          child: Text(
                            group.label.toUpperCase(),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.6,
                              color: muted,
                            ),
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverToBoxAdapter(
                          child: Column(
                            children: [
                              for (final item in group.items)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _buildNotificationRow(
                                    item,
                                    titleColor: titleColor,
                                    muted: muted,
                                    isDark: isDark,
                                    card: card,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ];
                  }),
                const SliverToBoxAdapter(child: SizedBox(height: 40)),
              ],
            ),
            ),
    );
  }

  Widget _buildCourseFilterBar(
    Color card,
    Color titleColor,
    Color muted,
    Color divider,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: SizedBox(
        height: 36,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            _buildFilterChip('All', 'all', card, titleColor, muted, divider),
            ..._courses.map(
              (course) => _buildFilterChip(
                course.name,
                course.id,
                card,
                titleColor,
                muted,
                divider,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(
    String label,
    String value,
    Color card,
    Color titleColor,
    Color muted,
    Color divider,
  ) {
    final isSelected = _courseFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _courseFilter = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? _accent : card,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: isSelected ? _accent : divider,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isSelected ? Colors.white : titleColor,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(Color titleColor, Color muted) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.bell_slash,
              size: 56,
              color: muted.withOpacity(0.7),
            ),
            const SizedBox(height: 16),
            Text(
              _isSystemAdmin && _courseFilter != 'all'
                  ? 'No notifications for this course'
                  : 'No Notifications',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
                color: titleColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isSystemAdmin && _courseFilter != 'all'
                  ? 'Try All to see campus-wide posts as well'
                  : 'When something new arrives, it will show up here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                height: 1.4,
                color: muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationRow(
    AppNotification notification, {
    required Color titleColor,
    required Color muted,
    required bool isDark,
    required Color card,
  }) {
    final typeColor = _getTypeColor(notification.type);
    final currentUserId = AuthService.instance.currentUser?.uid;
    final isOwnNotification = notification.senderId == currentUserId;
    final canDelete =
        isOwnNotification || currentUserRole == 'admin' || _isSystemAdmin;
    final canEdit = isOwnNotification;

    return Material(
      color: notification.isRead
          ? card
          : Color.alphaBlend(
              _accent.withOpacity(isDark ? 0.16 : 0.08),
              card,
            ),
      elevation: isDark ? 0 : 1,
      shadowColor: Colors.black.withOpacity(0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showNotificationDetails(notification),
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: typeColor,
                      borderRadius: BorderRadius.circular(13),
                      boxShadow: [
                        BoxShadow(
                          color: typeColor.withOpacity(0.28),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(
                      _getTypeIcon(notification.type),
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  if (!notification.isRead)
                    Positioned(
                      right: -1,
                      top: -1,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: _accent,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF1F2937)
                                : Colors.white,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            notification.displayTitle,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: notification.isRead
                                  ? FontWeight.w600
                                  : FontWeight.w800,
                              letterSpacing: -0.2,
                              color: titleColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          timeago.format(notification.createdAt),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: muted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: notification.senderName,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _getRoleColor(notification.senderRole),
                            ),
                          ),
                          TextSpan(
                            text: '  ·  ${_formatRole(notification.senderRole)}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: muted,
                            ),
                          ),
                          TextSpan(
                            text: '  ·  ${_audienceLabel(notification)}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: muted,
                            ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notification.message,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.35,
                        color: titleColor.withOpacity(0.82),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (notification.imageUrl != null &&
                        notification.imageUrl!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          notification.imageUrl!,
                          height: 92,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (canEdit || canDelete)
                PopupMenuButton<String>(
                  icon: Icon(
                    CupertinoIcons.ellipsis,
                    color: muted,
                    size: 18,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  onSelected: (value) {
                    if (value == 'edit') {
                      _editNotification(notification);
                    } else if (value == 'delete') {
                      _confirmDelete(notification, isOwnNotification);
                    }
                  },
                  itemBuilder: (context) => [
                    if (canEdit)
                      const PopupMenuItem(
                        value: 'edit',
                        child: Text('Edit'),
                      ),
                    if (canDelete)
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text(
                          'Delete',
                          style: TextStyle(color: _danger),
                        ),
                      ),
                  ],
                )
              else
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 4),
                  child: Icon(
                    CupertinoIcons.chevron_forward,
                    size: 14,
                    color: muted.withOpacity(0.6),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    AppNotification notification,
    bool isOwnNotification,
  ) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Delete Notification'),
        content: Text(
          isOwnNotification
              ? 'This notification will be removed for everyone who received it.'
              : 'You are about to delete ${notification.senderName}\'s notification.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      _deleteNotification(notification.id);
    }
  }

  void _showNotificationDetails(AppNotification notification) {
    if (!notification.isRead) {
      _markAsRead(notification.id);
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheet = isDark ? const Color(0xFF1F2937) : Colors.white;
    final titleColor =
        isDark ? const Color(0xFFF9FAFB) : const Color(0xFF111827);
    final muted = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
    final typeColor = _getTypeColor(notification.type);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: _sheetBottomInset(context)),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.86,
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        decoration: BoxDecoration(
          color: sheet,
          borderRadius: BorderRadius.circular(28),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 5,
                  decoration: BoxDecoration(
                    color: muted.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: typeColor,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(
                      _getTypeIcon(notification.type),
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          notification.displayTitle,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            color: titleColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${notification.type[0].toUpperCase()}${notification.type.substring(1)}  ·  ${_audienceLabel(notification)}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                notification.message,
                style: TextStyle(
                  fontSize: 17,
                  height: 1.45,
                  color: titleColor,
                ),
              ),
              if (notification.imageUrl != null &&
                  notification.imageUrl!.isNotEmpty) ...[
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.network(
                    notification.imageUrl!,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF111827)
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Icon(
                      _getRoleIcon(notification.senderRole),
                      size: 20,
                      color: _getRoleColor(notification.senderRole),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            notification.senderName,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: titleColor,
                            ),
                          ),
                          Text(
                            _formatRole(notification.senderRole),
                            style: TextStyle(
                              fontSize: 13,
                              color: muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      timeago.format(notification.createdAt),
                      style: TextStyle(fontSize: 13, color: muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Done',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
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
}
