import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final ScrollController _scrollController = ScrollController();
  bool _pendingScrollToLatest = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
    _checkUserRole();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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
      _scrollToLatestIfNeeded();
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
    final map = <String, List<AppNotification>>{};
    for (final item in items) {
      map.putIfAbsent(_sectionFor(item.createdAt), () => []).add(item);
    }
    const chatOrder = ['Earlier', 'This Week', 'Yesterday', 'Today'];
    return [
      for (final label in chatOrder)
        if (map[label]?.isNotEmpty == true)
          (
            label: label,
            items: [...map[label]!]
              ..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
          ),
    ];
  }

  void _scrollToLatestIfNeeded() {
    if (!_pendingScrollToLatest) return;
    void jump() {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      jump();
      Future<void>.delayed(const Duration(milliseconds: 280), () {
        jump();
        _pendingScrollToLatest = false;
      });
    });
  }

  void _openImage(AppNotification notification) {
    final url = notification.imageUrl;
    if (url == null || url.isEmpty) return;
    if (!notification.isRead) {
      _markAsRead(notification.id);
    }
    Navigator.of(context).push(
      MaterialPageRoute(
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
    } catch (e) {
      if (!mounted) return;
      _showSnack('Could not open link', _danger);
    }
  }

  Future<void> _copyMessage(AppNotification notification) async {
    await Clipboard.setData(ClipboardData(text: notification.message));
    if (!mounted) return;
    _showSnack('Message copied', _success);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background =
        isDark ? const Color(0xFF0B141A) : const Color(0xFFEFE7DD);
    final barColor =
        isDark ? const Color(0xFF202C33) : const Color(0xFF075E54);
    final muted = isDark ? const Color(0xFF8696A0) : const Color(0xFF667781);

    final visible = _visibleNotifications;
    final unreadCount = visible.where((n) => !n.isRead).length;
    final groups = _grouped(visible);

    return Scaffold(
      backgroundColor: background,
      body: isLoading
          ? Center(
              child: CupertinoActivityIndicator(
                color: isDark ? Colors.white : const Color(0xFF075E54),
                radius: 14,
              ),
            )
          : RefreshIndicator(
              color: const Color(0xFF25D366),
              onRefresh: _refreshNotifications,
              child: CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: [
                  SliverAppBar(
                    pinned: true,
                    elevation: 0,
                    scrolledUnderElevation: 0,
                    backgroundColor: barColor,
                    foregroundColor: Colors.white,
                    systemOverlayStyle: SystemUiOverlayStyle.light,
                    leading: IconButton(
                      icon: const Icon(CupertinoIcons.back, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    title: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Notifications',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          unreadCount > 0
                              ? '$unreadCount unread'
                              : 'You\'re all caught up',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withOpacity(0.72),
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      if (unreadCount > 0)
                        TextButton(
                          onPressed: _markAllAsRead,
                          child: const Text(
                            'Read all',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      if (canCreateNotifications)
                        IconButton(
                          onPressed: () async {
                            if (!await NoInternetScreen.ensureOnline(context)) {
                              return;
                            }
                            if (!context.mounted) return;
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (ctx) =>
                                    const CreateNotificationScreen(),
                              ),
                            );
                            _pendingScrollToLatest = true;
                            _loadNotifications();
                          },
                          icon: const Icon(
                            CupertinoIcons.add_circled_solid,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                      const SizedBox(width: 4),
                    ],
                  ),
                  if (_isSystemAdmin)
                    SliverToBoxAdapter(
                      child: ColoredBox(
                        color: barColor,
                        child: _buildCourseFilterBar(),
                      ),
                    ),
                  if (visible.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _buildEmptyState(
                        isDark ? Colors.white : const Color(0xFF111B21),
                        muted,
                      ),
                    )
                  else
                    ...groups.expand((group) {
                      return [
                        SliverToBoxAdapter(
                          child: _DateChip(label: group.label, isDark: isDark),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
                          sliver: SliverToBoxAdapter(
                            child: Column(
                              children: [
                                for (final item in group.items)
                                  _buildNotificationRow(
                                    item,
                                    titleColor: isDark
                                        ? const Color(0xFFE9EDEF)
                                        : const Color(0xFF111B21),
                                    muted: muted,
                                    isDark: isDark,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ];
                    }),
                  const SliverToBoxAdapter(child: SizedBox(height: 28)),
                ],
              ),
            ),
    );
  }

  Widget _buildCourseFilterBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: SizedBox(
        height: 36,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            _buildFilterChip('All', 'all'),
            ..._courses.map(
              (course) => _buildFilterChip(course.name, course.id),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _courseFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _courseFilter = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF25D366)
                : Colors.white.withOpacity(0.14),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isSelected ? const Color(0xFF111B21) : Colors.white,
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
  }) {
    final typeColor = _getTypeColor(notification.type);
    final roleColor = _getRoleColor(notification.senderRole);
    final currentUserId = AuthService.instance.currentUser?.uid;
    final isOwn = notification.senderId == currentUserId;
    final canDelete =
        isOwn || currentUserRole == 'admin' || _isSystemAdmin;
    final canEdit = isOwn;
    final bubble = isOwn
        ? (isDark ? const Color(0xFF005C4B) : const Color(0xFFD9FDD3))
        : (isDark ? const Color(0xFF1F2C34) : Colors.white);
    final timeColor = isOwn
        ? (isDark ? const Color(0xFF8EB9B0) : const Color(0xFF667781))
        : muted;
    final linkColor =
        isDark ? const Color(0xFF53BDEB) : const Color(0xFF027EB5);
    final moreColor =
        isDark ? const Color(0xFF53BDEB) : const Color(0xFF027EB5);
    final hasImage =
        notification.imageUrl != null && notification.imageUrl!.isNotEmpty;
    final hasTitle = notification.title.trim().isNotEmpty;
    final typeLabel =
        '${notification.type[0].toUpperCase()}${notification.type.substring(1)}';
    final initial = notification.senderName.trim().isNotEmpty
        ? notification.senderName.trim()[0].toUpperCase()
        : '?';

    final bubbleRadius = BorderRadius.only(
      topLeft: Radius.circular(isOwn ? 18 : 4),
      topRight: Radius.circular(isOwn ? 4 : 18),
      bottomLeft: const Radius.circular(18),
      bottomRight: const Radius.circular(18),
    );

    final messageBubble = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.78,
      ),
      child: Material(
        color: bubble,
        elevation: isOwn ? 0 : 0.6,
        shadowColor: Colors.black26,
        borderRadius: bubbleRadius,
        child: InkWell(
          onTap: () {
            if (!notification.isRead) {
              _markAsRead(notification.id);
            }
          },
          onLongPress: () => _showMessageActions(
            notification,
            canEdit: canEdit,
            canDelete: canDelete,
            isOwnNotification: isOwn,
          ),
          borderRadius: bubbleRadius,
          child: Padding(
            padding: EdgeInsets.fromLTRB(hasImage ? 4 : 10, 6, 8, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(hasImage ? 8 : 2, 2, 4, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          isOwn
                              ? 'You · ${_formatRole(notification.senderRole)}'
                              : '${notification.senderName} · ${_formatRole(notification.senderRole)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: roleColor,
                          ),
                        ),
                      ),
                      if (canEdit || canDelete)
                        _notificationMenu(
                          notification: notification,
                          canEdit: canEdit,
                          canDelete: canDelete,
                          isOwnNotification: isOwn,
                          isDark: isDark,
                          muted: timeColor,
                          titleColor: titleColor,
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(hasImage ? 8 : 2, 0, 4, 4),
                  child: Text(
                    '$typeLabel · ${_audienceLabel(notification)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: typeColor,
                    ),
                  ),
                ),
                if (hasImage)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: GestureDetector(
                      onTap: () => _openImage(notification),
                      child: Hero(
                        tag: 'notification-image-${notification.id}',
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: AspectRatio(
                            aspectRatio: 4 / 3,
                            child: Image.network(
                              notification.imageUrl!,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              errorBuilder: (_, __, ___) => ColoredBox(
                                color: Colors.black12,
                                child: Icon(
                                  CupertinoIcons.photo,
                                  color: muted,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (hasTitle)
                  Padding(
                    padding: EdgeInsets.fromLTRB(hasImage ? 8 : 2, 0, 4, 4),
                    child: Text(
                      notification.title.trim(),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: titleColor,
                        height: 1.25,
                      ),
                    ),
                  ),
                if (notification.message.trim().isNotEmpty)
                  Padding(
                    padding: EdgeInsets.fromLTRB(hasImage ? 8 : 2, 0, 4, 2),
                    child: _ExpandableLinkedText(
                      text: notification.message.trim(),
                      color: titleColor,
                      linkColor: linkColor,
                      moreColor: moreColor,
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
                  ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(hasImage ? 8 : 2, 2, 2, 0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _bubbleTime(notification.createdAt),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: timeColor,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          notification.isRead
                              ? Icons.done_all
                              : Icons.done,
                          size: 14,
                          color: notification.isRead
                              ? const Color(0xFF53BDEB)
                              : timeColor,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment:
            isOwn ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isOwn) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: roleColor,
              child: Text(
                initial,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(child: messageBubble),
          if (isOwn) const SizedBox(width: 4),
        ],
      ),
    );
  }

  String _bubbleTime(DateTime date) {
    final local = date.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final suffix = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  Future<void> _showMessageActions(
    AppNotification notification, {
    required bool canEdit,
    required bool canDelete,
    required bool isOwnNotification,
  }) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheet = isDark ? const Color(0xFF1F2C34) : Colors.white;
    final titleColor =
        isDark ? const Color(0xFFE9EDEF) : const Color(0xFF111B21);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: _sheetBottomInset(ctx)),
        child: Container(
          decoration: BoxDecoration(
            color: sheet,
            borderRadius: BorderRadius.circular(20),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                ListTile(
                  leading: const Icon(CupertinoIcons.doc_on_doc),
                  title: Text('Copy', style: TextStyle(color: titleColor)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _copyMessage(notification);
                  },
                ),
                if (canEdit)
                  ListTile(
                    leading: const Icon(CupertinoIcons.pencil),
                    title: Text('Edit', style: TextStyle(color: titleColor)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _editNotification(notification);
                    },
                  ),
                if (canDelete)
                  ListTile(
                    leading: const Icon(
                      CupertinoIcons.trash,
                      color: _danger,
                    ),
                    title: const Text(
                      'Delete',
                      style: TextStyle(color: _danger),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _confirmDelete(notification, isOwnNotification);
                    },
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
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
      iconSize: 18,
      splashRadius: 16,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
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
        if (value == 'copy') {
          _copyMessage(notification);
        } else if (value == 'edit') {
          _editNotification(notification);
        } else if (value == 'delete') {
          _confirmDelete(notification, isOwnNotification);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'copy',
          child: _menuRow(
            icon: CupertinoIcons.doc_on_doc,
            label: 'Copy',
            color: titleColor,
            accent: _accent,
          ),
        ),
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

class _DateChip extends StatelessWidget {
  const _DateChip({required this.label, required this.isDark});

  final String label;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF182229) : const Color(0xFFE1F2FA),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.25 : 0.06),
                blurRadius: 6,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? const Color(0xFF8696A0) : const Color(0xFF54656F),
            ),
          ),
        ),
      ),
    );
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
          style: TextStyle(
            fontSize: 15.5,
            height: 1.35,
            color: color,
          ),
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
                fontSize: 15.5,
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
