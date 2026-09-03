import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:url_launcher/url_launcher.dart';

import '../services/auth_service.dart';
import '../services/course_service.dart';
import '../services/notification_service.dart';
import '../ui/adaptive_layout.dart';
import 'create_notification_screen.dart';
import 'no_internet_screen.dart';
import 'notification_image_viewer.dart';
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
  final Set<String> _expandedIds = {};

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
        canCreateNotifications = !AuthService.isClientRole(role) &&
            (role != 'student' || isSystemAdmin);
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

  Future<void> _refreshNotifications() async {
    if (!await NoInternetScreen.ensureOnline(context)) return;
    await _loadNotifications();
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

  Future<void> _openCreateNotification() async {
    if (!await NoInternetScreen.ensureOnline(context)) return;
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CreateNotificationScreen()),
    );
    _loadNotifications();
  }

  double _fabNavLift(BuildContext context) {
    final nested =
        Navigator.of(context) != Navigator.of(context, rootNavigator: true);
    if (!nested) return 16;
    return MediaQuery.viewPaddingOf(context).bottom +
        kBottomNavigationBarHeight +
        12;
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

  void _openImage(AppNotification notification) {
    final url = notification.imageUrl;
    if (url == null || url.isEmpty) return;
    if (!notification.isRead) {
      _markAsRead(notification.id);
    }
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => NotificationImageViewer(
          imageUrl: url,
          heroTag: 'notification-image-${notification.id}',
          title: notification.title.trim().isNotEmpty
              ? notification.title.trim()
              : notification.senderName,
        ),
      ),
    );
  }

  Future<void> _openLink(String raw) async {
    var value = raw.replaceAll(RegExp(r'[.,;:!?)\]>]+$'), '');
    if (value.startsWith('www.')) {
      value = 'https://$value';
    }
    final uri = Uri.tryParse(value);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      _showSnack('Could not open link', _danger);
    }
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
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: sheet,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF374151)
                    : const Color(0xFFE5E7EB),
              ),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 6,
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [_accent, Color(0xFF8B5CF6)],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
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
                            DropdownMenuItem(
                              value: 'general',
                              child: Text('General'),
                            ),
                            DropdownMenuItem(
                              value: 'announcement',
                              child: Text('Announcement'),
                            ),
                            DropdownMenuItem(
                              value: 'assignment',
                              child: Text('Assignment'),
                            ),
                            DropdownMenuItem(
                              value: 'exam',
                              child: Text('Exam'),
                            ),
                            DropdownMenuItem(
                              value: 'event',
                              child: Text('Event'),
                            ),
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
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  side: BorderSide(
                                    color: muted.withOpacity(0.3),
                                  ),
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
                                    _showSnack(
                                      'Please enter a message',
                                      _danger,
                                    );
                                    return;
                                  }

                                  try {
                                    await NotificationService.instance.update(
                                      id: notification.id,
                                      title: titleController.text.trim(),
                                      message: messageController.text.trim(),
                                      type: selectedType,
                                    );

                                    if (context.mounted) {
                                      Navigator.of(context).pop();
                                    }
                                    if (!mounted) return;
                                    _loadNotifications();
                                    _showSnack(
                                      'Notification updated successfully',
                                      _success,
                                    );
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
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

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
        return const Color(0xFFF472B6);
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
        if (map[label]?.isNotEmpty == true) (label: label, items: map[label]!),
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
    final nested =
        Navigator.of(context) != Navigator.of(context, rootNavigator: true);
    final bottomPad = nested
        ? AdaptiveLayout.bottomClearance(context)
        : MediaQuery.viewPaddingOf(context).bottom + 24;

    return Scaffold(
      backgroundColor: background,
      floatingActionButton: canCreateNotifications
          ? Padding(
              padding: EdgeInsets.only(bottom: _fabNavLift(context)),
              child: FloatingActionButton(
                onPressed: _openCreateNotification,
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                elevation: isDark ? 0 : 4,
                tooltip: 'Create notification',
                child: const Icon(CupertinoIcons.add, size: 28),
              ),
            )
          : null,
      body: isLoading
          ? Center(
              child: CupertinoActivityIndicator(
                color: isDark ? Colors.white : _accent,
                radius: 14,
              ),
            )
          : RefreshIndicator(
              color: _accent,
              onRefresh: _refreshNotifications,
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
                          onPressed: _openCreateNotification,
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
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.4,
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
                      child: _buildCourseFilterBar(
                        card,
                        titleColor,
                        muted,
                        divider,
                      ),
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
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: bottomPad + (canCreateNotifications ? 72 : 0),
                    ),
                  ),
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
    final roleColor = _getRoleColor(notification.senderRole);
    final currentUserId = AuthService.instance.currentUser?.uid;
    final isOwnNotification = notification.senderId == currentUserId;
    final canDelete =
        isOwnNotification || currentUserRole == 'admin' || _isSystemAdmin;
    final canEdit = isOwnNotification;
    final hasImage =
        notification.imageUrl != null && notification.imageUrl!.isNotEmpty;
    final typeLabel =
        '${notification.type[0].toUpperCase()}${notification.type.substring(1)}';
    final inner = isDark ? const Color(0xFF111827) : const Color(0xFFF8FAFC);

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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            notification.senderName,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: titleColor,
                            ),
                          ),
                          Text(
                            '• ${_formatRole(notification.senderRole)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: roleColor,
                            ),
                          ),
                          if (!notification.isRead)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _accent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'NEW',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${timeago.format(notification.createdAt)}  ·  $typeLabel  ·  ${_audienceLabel(notification)}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: muted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (canEdit || canDelete)
                  _notificationMenu(
                    notification: notification,
                    canEdit: canEdit,
                    canDelete: canDelete,
                    isOwnNotification: isOwnNotification,
                    isDark: isDark,
                    muted: muted,
                    titleColor: titleColor,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: inner,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (notification.title.trim().isNotEmpty) ...[
                    Text(
                      notification.title.trim(),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: notification.isRead
                            ? FontWeight.w600
                            : FontWeight.w800,
                        letterSpacing: -0.2,
                        color: titleColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (notification.message.trim().isNotEmpty)
                    _ExpandableLinkedText(
                      text: notification.message.trim(),
                      color: titleColor.withOpacity(0.82),
                      linkColor: _accent,
                      moreColor: _accent,
                      expanded: _expandedIds.contains(notification.id),
                      onToggle: () {
                        setState(() {
                          if (_expandedIds.contains(notification.id)) {
                            _expandedIds.remove(notification.id);
                          } else {
                            _expandedIds.add(notification.id);
                          }
                        });
                        if (!notification.isRead) {
                          _markAsRead(notification.id);
                        }
                      },
                      onLinkTap: _openLink,
                    ),
                  if (hasImage) ...[
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: () => _openImage(notification),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          notification.imageUrl!,
                          height: 140,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => ColoredBox(
                            color: muted.withOpacity(0.15),
                            child: SizedBox(
                              height: 92,
                              child: Icon(CupertinoIcons.photo, color: muted),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _notificationMenu({
    required AppNotification notification,
    required bool canEdit,
    required bool canDelete,
    required bool isOwnNotification,
    required bool isDark,
    required Color muted,
    required Color titleColor,
  }) {
    final menu = isDark ? const Color(0xFF1F2937) : Colors.white;
    return PopupMenuButton<String>(
      tooltip: 'Notification options',
      padding: EdgeInsets.zero,
      offset: const Offset(0, 8),
      elevation: 10,
      color: menu,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.black.withOpacity(isDark ? 0.45 : 0.16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? const Color(0xFF374151) : const Color(0xFFE5E7EB),
        ),
      ),
      icon: Icon(CupertinoIcons.ellipsis, color: muted, size: 18),
      onSelected: (value) {
        if (value == 'edit') {
          _editNotification(notification);
        } else if (value == 'delete') {
          _confirmDelete(notification, isOwnNotification);
        }
      },
      itemBuilder: (context) => [
        if (canEdit)
          PopupMenuItem(
            value: 'edit',
            child: _menuRow(
              icon: CupertinoIcons.pencil,
              label: 'Edit',
              color: titleColor,
              accent: _accent,
            ),
          ),
        if (canDelete)
          PopupMenuItem(
            value: 'delete',
            child: _menuRow(
              icon: CupertinoIcons.trash,
              label: 'Delete',
              color: _danger,
              accent: _danger,
            ),
          ),
      ],
    );
  }

  Widget _menuRow({
    required IconData icon,
    required String label,
    required Color color,
    required Color accent,
  }) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: accent.withOpacity(0.12),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 15, color: accent),
        ),
        const SizedBox(width: 12),
        Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(
    AppNotification notification,
    bool isOwnNotification,
  ) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = isDark ? const Color(0xFF1F2937) : Colors.white;
    final titleColor =
        isDark ? const Color(0xFFF9FAFB) : const Color(0xFF111827);
    final muted = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
        actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: _danger.withOpacity(isDark ? 0.18 : 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                CupertinoIcons.trash_fill,
                color: _danger,
                size: 24,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Delete notification?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
                color: titleColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isOwnNotification
                  ? 'This notification will be removed for everyone who received it.'
                  : 'You are about to delete ${notification.senderName}\'s notification.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, height: 1.4, color: muted),
            ),
          ],
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: titleColor,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    side: BorderSide(
                      color: isDark
                          ? const Color(0xFF374151)
                          : const Color(0xFFE5E7EB),
                    ),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _danger,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Delete',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (confirmed == true) {
      _deleteNotification(notification.id);
    }
  }
}

class _ExpandableLinkedText extends StatelessWidget {
  const _ExpandableLinkedText({
    required this.text,
    required this.color,
    required this.linkColor,
    required this.moreColor,
    required this.expanded,
    required this.onToggle,
    required this.onLinkTap,
  });

  static const collapseLength = 160;
  static final _linkPattern = RegExp(
    r'((?:https?:\/\/|www\.)[^\s<]+)',
    caseSensitive: false,
  );

  final String text;
  final Color color;
  final Color linkColor;
  final Color moreColor;
  final bool expanded;
  final VoidCallback onToggle;
  final ValueChanged<String> onLinkTap;

  @override
  Widget build(BuildContext context) {
    final needsCollapse = text.length > collapseLength;
    final visible = !needsCollapse || expanded
        ? text
        : '${text.substring(0, collapseLength).trimRight()}...';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(children: _spans(visible)),
          style: TextStyle(fontSize: 15, height: 1.35, color: color),
        ),
        if (needsCollapse)
          GestureDetector(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                expanded ? 'Read less' : 'Read more',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: moreColor,
                ),
              ),
            ),
          ),
      ],
    );
  }

  List<InlineSpan> _spans(String source) {
    final spans = <InlineSpan>[];
    var start = 0;
    for (final match in _linkPattern.allMatches(source)) {
      if (match.start > start) {
        spans.add(TextSpan(text: source.substring(start, match.start)));
      }
      final link = match.group(0)!;
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: GestureDetector(
            onTap: () => onLinkTap(link),
            child: Text(
              link,
              style: TextStyle(
                fontSize: 15,
                height: 1.35,
                color: linkColor,
                decoration: TextDecoration.underline,
                decorationColor: linkColor,
              ),
            ),
          ),
        ),
      );
      start = match.end;
    }
    if (start < source.length) {
      spans.add(TextSpan(text: source.substring(start)));
    }
    return spans;
  }
}
