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
  String? _editingNotificationId;
  final Map<String, TextEditingController> _editTitleControllers = {};
  final Map<String, TextEditingController> _editMessageControllers = {};
  final Map<String, String> _editTypes = {};

  @override
  void initState() {
    super.initState();
    _checkUserRole();
    _loadNotifications();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    for (final controller in _editTitleControllers.values) {
      controller.dispose();
    }
    for (final controller in _editMessageControllers.values) {
      controller.dispose();
    }
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
      final canCreate = !AuthService.isClientRole(role) &&
          (role != 'student' || isSystemAdmin);
      setState(() {
        currentUserRole = role;
        _isSystemAdmin = isSystemAdmin;
        _courses = courses;
        canCreateNotifications = canCreate;
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
    setState(() => isLoading = true);

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
      setState(() => isLoading = false);
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
      final unread = _visibleNotifications.where((n) => !n.isRead).toList();
      if (unread.isEmpty) return;
      await NotificationService.instance.markAllAsRead(
        unread.map((n) => n.id).toList(),
      );
      if (!mounted) return;
      setState(() {
        notifications = [
          for (final item in notifications) item.copyWith(isRead: true),
        ];
      });
      _showSnack('All notifications marked as read', _success);
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _openComposer() async {
    if (!await NoInternetScreen.ensureOnline(context)) return;
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CreateNotificationScreen()),
    );
    _loadNotifications();
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

  void _startEditing(AppNotification notification) {
    _cancelEditing(_editingNotificationId);
    setState(() {
      _editingNotificationId = notification.id;
      _editTitleControllers[notification.id] =
          TextEditingController(text: notification.title);
      _editMessageControllers[notification.id] =
          TextEditingController(text: notification.message);
      _editTypes[notification.id] = notification.type;
    });
  }

  void _cancelEditing(String? notificationId) {
    if (notificationId == null) return;
    _editTitleControllers[notificationId]?.dispose();
    _editMessageControllers[notificationId]?.dispose();
    _editTitleControllers.remove(notificationId);
    _editMessageControllers.remove(notificationId);
    _editTypes.remove(notificationId);
    if (_editingNotificationId == notificationId) {
      setState(() => _editingNotificationId = null);
    }
  }

  Future<void> _saveEdited(AppNotification notification) async {
    final title = _editTitleControllers[notification.id]?.text.trim() ?? '';
    final message =
        _editMessageControllers[notification.id]?.text.trim() ?? '';
    final type = _editTypes[notification.id] ?? notification.type;
    if (message.isEmpty) {
      _showSnack('Please enter a message', _danger);
      return;
    }
    try {
      await NotificationService.instance.update(
        id: notification.id,
        title: title,
        message: message,
        type: type,
      );
      _cancelEditing(notification.id);
      await _loadNotifications();
      if (mounted) {
        _showSnack('Notification updated successfully!', _success);
      }
    } catch (e) {
      _showSnack('Failed to update notification: $e', _danger);
    }
  }

  Future<void> _deleteNotification(String notificationId) async {
    try {
      await NotificationService.instance.delete(notificationId);
      _cancelEditing(notificationId);
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

  String _getTimeAgo(DateTime dateTime) {
    final difference = DateTime.now().difference(dateTime);
    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inHours < 1) return '${difference.inMinutes}m ago';
    if (difference.inDays < 1) return '${difference.inHours}h ago';
    if (difference.inDays < 7) return '${difference.inDays}d ago';
    if (difference.inDays < 30) {
      return '${(difference.inDays / 7).floor()}w ago';
    }
    return '${(difference.inDays / 30).floor()}mo ago';
  }

  Future<void> _confirmDelete(
    AppNotification notification,
    bool isOwnNotification,
  ) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = isDark ? const Color(0xFF1F2937) : Colors.white;
    final titleColor =
        isDark ? const Color(0xFFF9FAFB) : const Color(0xFF1E293B);
    final preview = notification.message.length > 50
        ? '${notification.message.substring(0, 50)}...'
        : notification.message;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Delete Notification',
          style: TextStyle(fontWeight: FontWeight.bold, color: titleColor),
        ),
        content: Text(
          isOwnNotification
              ? 'Are you sure you want to delete this notification?\n\n"$preview"'
              : 'You are about to delete ${notification.senderName}\'s notification.\n\n"$preview"',
          style: TextStyle(color: titleColor.withOpacity(0.8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      _deleteNotification(notification.id);
    }
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
    final nested =
        Navigator.of(context) != Navigator.of(context, rootNavigator: true);
    final bottomPad = nested
        ? AdaptiveLayout.bottomClearance(context)
        : MediaQuery.viewPaddingOf(context).bottom + 24;

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
                    backgroundColor: background,
                    systemOverlayStyle: isDark
                        ? SystemUiOverlayStyle.light
                        : SystemUiOverlayStyle.dark,
                    leading: IconButton(
                      icon: Icon(CupertinoIcons.back, color: titleColor),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    actions: [
                      if (unreadCount > 0)
                        TextButton(
                          onPressed: _markAllAsRead,
                          child: const Text(
                            'Read all',
                            style: TextStyle(
                              color: _accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      if (canCreateNotifications)
                        IconButton(
                          onPressed: _openComposer,
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
                        divider,
                      ),
                    ),
                  if (visible.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _buildEmptyState(titleColor, muted),
                    )
                  else
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, bottomPad),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            return _buildNotificationCard(
                              visible[index],
                              isDark: isDark,
                              titleColor: titleColor,
                              muted: muted,
                              card: card,
                            );
                          },
                          childCount: visible.length,
                        ),
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
    Color divider,
  ) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        children: [
          _filterChip('All', 'all', card, titleColor, divider),
          ..._courses.map(
            (course) => _filterChip(
              course.name,
              course.id,
              card,
              titleColor,
              divider,
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(
    String label,
    String value,
    Color card,
    Color titleColor,
    Color divider,
  ) {
    final selected = _courseFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _courseFilter = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? _accent : card,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: selected ? _accent : divider),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : titleColor,
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
            Icon(CupertinoIcons.bell_slash, size: 56, color: muted.withOpacity(0.7)),
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
              canCreateNotifications
                  ? 'Tap + to send your first notification.'
                  : 'When something new arrives, it will show up here.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: muted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationCard(
    AppNotification notification, {
    required bool isDark,
    required Color titleColor,
    required Color muted,
    required Color card,
  }) {
    final currentUserId = AuthService.instance.currentUser?.uid;
    final isOwn = notification.senderId == currentUserId;
    final canDelete =
        isOwn || currentUserRole == 'admin' || _isSystemAdmin;
    final canEdit = isOwn;
    final typeColor = _getTypeColor(notification.type);
    final roleColor = _getRoleColor(notification.senderRole);
    final typeLabel =
        '${notification.type[0].toUpperCase()}${notification.type.substring(1)}';
    final hasImage =
        notification.imageUrl != null && notification.imageUrl!.isNotEmpty;
    final isEditing = _editingNotificationId == notification.id;
    final inner = isDark ? const Color(0xFF111827) : const Color(0xFFF8FAFC);
    final cardColor = notification.isRead
        ? card
        : Color.alphaBlend(
            _accent.withOpacity(isDark ? 0.16 : 0.08),
            card,
          );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
        ],
        border: Border.all(
          color: notification.isRead
              ? (isDark ? const Color(0xFF374151) : const Color(0xFFE5E7EB))
              : _accent.withOpacity(0.35),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: typeColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _getTypeIcon(notification.type),
                    color: Colors.white,
                    size: 20,
                  ),
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
                              color: roleColor,
                              fontWeight: FontWeight.w600,
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
                        '${_getTimeAgo(notification.createdAt)}  ·  $typeLabel  ·  ${_audienceLabel(notification)}',
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                    ],
                  ),
                ),
                if (canEdit || canDelete)
                  PopupMenuButton<String>(
                    color: card,
                    surfaceTintColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    onSelected: (value) {
                      if (value == 'edit') {
                        _startEditing(notification);
                      } else if (value == 'delete') {
                        _confirmDelete(notification, isOwn);
                      }
                    },
                    itemBuilder: (context) => [
                      if (canEdit)
                        PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              const Icon(
                                CupertinoIcons.pencil,
                                color: _accent,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Edit',
                                style: TextStyle(color: titleColor),
                              ),
                            ],
                          ),
                        ),
                      if (canDelete)
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(
                                CupertinoIcons.trash,
                                color: _danger,
                                size: 18,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Delete',
                                style: TextStyle(color: _danger),
                              ),
                            ],
                          ),
                        ),
                    ],
                    child: Icon(CupertinoIcons.ellipsis, color: muted, size: 18),
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
              child: isEditing
                  ? _buildInlineEditor(notification, isDark, titleColor, muted)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (notification.title.trim().isNotEmpty) ...[
                          Text(
                            notification.title.trim(),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: titleColor,
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        if (notification.message.trim().isNotEmpty)
                          _ExpandableLinkedText(
                            text: notification.message.trim(),
                            color: titleColor.withOpacity(0.88),
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
                            },
                            onLinkTap: _openLink,
                          ),
                        if (hasImage) ...[
                          const SizedBox(height: 12),
                          GestureDetector(
                            onTap: () => _openImage(notification),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: AspectRatio(
                                aspectRatio: 16 / 10,
                                child: Image.network(
                                  notification.imageUrl!,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  errorBuilder: (_, __, ___) => ColoredBox(
                                    color: muted.withOpacity(0.15),
                                    child: Icon(
                                      CupertinoIcons.photo,
                                      color: muted,
                                    ),
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

  Widget _buildInlineEditor(
    AppNotification notification,
    bool isDark,
    Color titleColor,
    Color muted,
  ) {
    final fill = isDark ? const Color(0xFF1F2937) : Colors.white;
    InputDecoration decoration(String hint) {
      return InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: muted),
        filled: true,
        fillColor: fill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _accent, width: 1.5),
        ),
        contentPadding: const EdgeInsets.all(12),
      );
    }

    return Column(
      children: [
        TextField(
          controller: _editTitleControllers[notification.id],
          style: TextStyle(fontSize: 15, color: titleColor),
          decoration: decoration('Title (optional)'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _editMessageControllers[notification.id],
          maxLines: 4,
          style: TextStyle(fontSize: 15, height: 1.5, color: titleColor),
          decoration: decoration('Edit your notification...'),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _editTypes[notification.id] ?? notification.type,
          dropdownColor: fill,
          style: TextStyle(color: titleColor, fontSize: 15),
          decoration: decoration('Type'),
          items: const [
            DropdownMenuItem(value: 'general', child: Text('General')),
            DropdownMenuItem(
              value: 'announcement',
              child: Text('Announcement'),
            ),
            DropdownMenuItem(value: 'assignment', child: Text('Assignment')),
            DropdownMenuItem(value: 'exam', child: Text('Exam')),
            DropdownMenuItem(value: 'event', child: Text('Event')),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() => _editTypes[notification.id] = value);
          },
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => _cancelEditing(notification.id),
              child: Text('Cancel', style: TextStyle(color: muted)),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: () => _saveEdited(notification),
              icon: const Icon(CupertinoIcons.checkmark_alt, size: 16),
              label: const Text('Save'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ],
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
          style: TextStyle(fontSize: 15, height: 1.5, color: color),
        ),
        if (needsCollapse)
          GestureDetector(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
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
                height: 1.5,
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
