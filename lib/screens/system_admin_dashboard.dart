import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/auth_service.dart';
import '../services/course_service.dart';
import 'course_addition.dart';

class SystemAdminDashboard extends StatefulWidget {
  const SystemAdminDashboard({super.key});

  static const allowedEmail = 'muigaid91@gmail.com';
  static const systemAdminRole = 'system_admin';

  static bool isAllowedEmail(String? email) =>
      email?.toLowerCase() == allowedEmail;

  static bool isSystemAdminRole(String? role) {
    final value = (role ?? '').toLowerCase();
    return value == systemAdminRole || value == 'super_admin';
  }

  /// Owner email or users with the `system_admin` role.
  static Future<bool> isCurrentUserSystemAdmin() async {
    final email = AuthService.instance.currentUser?.email;
    if (isAllowedEmail(email)) return true;
    final role = await AuthService.instance.currentRole();
    return isSystemAdminRole(role);
  }

  @override
  State<SystemAdminDashboard> createState() => _SystemAdminDashboardState();
}

class _SystemAdminDashboardState extends State<SystemAdminDashboard>
    with SingleTickerProviderStateMixin {
  final _firestore = FirebaseFirestore.instance;

  late final TabController _tabController;

  List<Map<String, dynamic>> _profiles = [];
  List<Map<String, dynamic>> _filteredUsers = [];
  List<Map<String, dynamic>> _filteredStaff = [];
  List<Course> _courses = [];
  bool _isLoading = true;
  bool _isLoadingCourses = true;
  bool _isStatsExpanded = true;
  String _userSearchQuery = '';
  String _staffSearchQuery = '';
  String _userRoleFilter = 'all';
  String _staffRoleFilter = 'all';
  String _userCourseFilter = 'all';
  String _staffCourseFilter = 'all';

  static const _userRoles = ['student', 'class_rep', 'assistant_class_rep'];
  static const _staffRoles = ['lecturer', 'admin', 'system_admin'];
  static const _allRoles = [
    'student',
    'class_rep',
    'assistant_class_rep',
    'lecturer',
    'admin',
    'system_admin',
  ];

  final Map<String, Color> _roleColors = {
    'system_admin': const Color(0xFF6366F1),
    'admin': const Color(0xFFEF4444),
    'lecturer': const Color(0xFF8B5CF6),
    'class_rep': const Color(0xFFF59E0B),
    'assistant_class_rep': const Color(0xFF0EA5E9),
    'student': const Color(0xFF10B981),
  };

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _bg =>
      _isDark ? const Color(0xFF111827) : const Color(0xFFF8FAFC);
  Color get _card => _isDark ? const Color(0xFF1F2937) : Colors.white;
  Color get _titleColor =>
      _isDark ? const Color(0xFFF9FAFB) : const Color(0xFF111827);
  Color get _muted =>
      _isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
  Color get _chip =>
      _isDark ? const Color(0xFF374151) : const Color(0xFFF1F5F9);

  int get _totalUsers =>
      _profiles.where((p) => _userRoles.contains(p['role'])).length;
  int get _totalStaff =>
      _profiles.where((p) => _staffRoles.contains(p['role'])).length;
  int get _totalStudents =>
      _profiles.where((p) => p['role'] == 'student').length;
  int get _totalClassReps =>
      _profiles.where((p) => p['role'] == 'class_rep').length;
  int get _totalAssistantClassReps =>
      _profiles.where((p) => p['role'] == 'assistant_class_rep').length;
  int get _totalLecturers =>
      _profiles.where((p) => p['role'] == 'lecturer').length;
  int get _totalAdmins => _profiles.where((p) => p['role'] == 'admin').length;
  int get _totalSystemAdmins => _profiles
      .where((p) => SystemAdminDashboard.isSystemAdminRole(p['role'] as String?))
      .length;

  int get _newThisWeek {
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    return _profiles.where((p) {
      final created = _parseDate(p['created_at']);
      return created != null && created.isAfter(weekAgo);
    }).length;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _guardAndLoad();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _guardAndLoad() async {
    final hasAccess = await SystemAdminDashboard.isCurrentUserSystemAdmin();
    if (!hasAccess) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You do not have access to System Admin.'),
            backgroundColor: Color(0xFFEF4444),
          ),
        );
        Navigator.pop(context);
      });
      return;
    }
    await _loadProfiles();
    await _loadCourses();
  }

  Future<void> _loadProfiles() async {
    setState(() => _isLoading = true);

    try {
      final snapshot = await _firestore.collection('profiles').get();
      final profiles = snapshot.docs.map((doc) {
        final data = Map<String, dynamic>.from(doc.data());
        data['id'] = doc.id;
        final role = ((data['role'] as String?) ?? 'student').toLowerCase();
        data['role'] = SystemAdminDashboard.isSystemAdminRole(role)
            ? SystemAdminDashboard.systemAdminRole
            : role;
        data['full_name'] = data['full_name'] ?? 'Unknown user';
        data['username'] = data['username'] ?? '';
        data['email'] = data['email'] ?? '';
        data['registration_number'] = data['registration_number'] ?? '';
        data['avatar_url'] = data['avatar_url'] ?? '';
        return data;
      }).toList()
        ..sort((a, b) {
          final aDate = _parseDate(a['created_at']) ?? DateTime(1970);
          final bDate = _parseDate(b['created_at']) ?? DateTime(1970);
          return bDate.compareTo(aDate);
        });

      if (!mounted) return;
      setState(() {
        _profiles = profiles;
        _filterLists();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading profiles: $e'),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
    }
  }

  void _filterLists() {
    _filteredUsers = _profiles.where((user) {
      if (!_userRoles.contains(user['role'])) return false;
      if (_userRoleFilter != 'all' && user['role'] != _userRoleFilter) {
        return false;
      }
      if (!_matchesCourseFilter(user, _userCourseFilter)) return false;
      return _matchesSearch(user, _userSearchQuery);
    }).toList();

    _filteredStaff = _profiles.where((user) {
      if (!_staffRoles.contains(user['role'])) return false;
      if (_staffRoleFilter != 'all' && user['role'] != _staffRoleFilter) {
        return false;
      }
      if (!_matchesCourseFilter(user, _staffCourseFilter)) return false;
      return _matchesSearch(user, _staffSearchQuery);
    }).toList();
  }

  bool _matchesCourseFilter(Map<String, dynamic> user, String courseFilter) {
    if (courseFilter == 'all') return true;
    final matched = _courseForProfile(user);
    return matched?.id == courseFilter;
  }

  Course? _courseForProfile(Map<String, dynamic> user) {
    final registration = user['registration_number']?.toString() ?? '';
    if (registration.isEmpty || _courses.isEmpty) return null;
    return CourseService.instance.matchCourse(registration, _courses);
  }

  bool _matchesSearch(Map<String, dynamic> user, String query) {
    if (query.trim().isEmpty) return true;
    final q = query.toLowerCase();
    final courseName = _courseForProfile(user)?.name.toLowerCase() ?? '';
    return user['full_name'].toString().toLowerCase().contains(q) ||
        user['username'].toString().toLowerCase().contains(q) ||
        user['email'].toString().toLowerCase().contains(q) ||
        user['registration_number'].toString().toLowerCase().contains(q) ||
        courseName.contains(q);
  }

  DateTime? _parseDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  bool _isCurrentUser(Map<String, dynamic> user) {
    final currentUid = AuthService.instance.currentUser?.uid;
    if (currentUid == null) return false;
    return user['id']?.toString() == currentUid;
  }

  Future<void> _updateUserRole(String userId, String newRole) async {
    if (userId == AuthService.instance.currentUser?.uid) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You cannot change your own role.'),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
      return;
    }

    try {
      await _firestore.collection('profiles').doc(userId).update({
        'role': newRole,
        'updated_at': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(CupertinoIcons.checkmark_circle_fill, color: Colors.white),
              SizedBox(width: 12),
              Text('Role updated successfully'),
            ],
          ),
          backgroundColor: Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
        ),
      );
      _loadProfiles();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating role: $e'),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
    }
  }

  void _showRoleChangeDialog(Map<String, dynamic> user) {
    if (_isCurrentUser(user)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You cannot change your own role.'),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
      return;
    }

    showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('Change Role'),
        message: Text(
          (user['email'] as String).isNotEmpty
              ? '${user['full_name']}\n${user['email']}'
              : user['full_name'].toString(),
        ),
        actions: [
          for (final role in _allRoles)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(context);
                if (user['role'] != role) {
                  _updateUserRole(user['id'], role);
                }
              },
              child: Text(
                user['role'] == role
                    ? '${_formatRole(role)} (Current)'
                    : _formatRole(role),
              ),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  void _showUserDetails(Map<String, dynamic> user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 36,
              height: 5,
              decoration: BoxDecoration(
                color: _chip,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                child: Column(
                  children: [
                    _buildAvatar(user, radius: 44),
                    const SizedBox(height: 14),
                    Text(
                      user['full_name'].toString(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                        color: _titleColor,
                      ),
                    ),
                    if ((user['username'] as String).isNotEmpty)
                      Text(
                        '@${user['username']}',
                        style: TextStyle(fontSize: 16, color: _muted),
                      ),
                    const SizedBox(height: 24),
                    _groupedCard([
                      _buildDetailRow(
                        'Email',
                        (user['email'] as String).isEmpty
                            ? 'Not stored'
                            : user['email'].toString(),
                        CupertinoIcons.mail_solid,
                      ),
                      _buildDetailRow(
                        'Registration',
                        (user['registration_number'] as String).isEmpty
                            ? 'N/A'
                            : user['registration_number'].toString(),
                        CupertinoIcons.number,
                      ),
                      _buildDetailRow(
                        'Course',
                        _courseForProfile(user)?.name ?? 'Unassigned',
                        CupertinoIcons.book_fill,
                      ),
                      _buildDetailRow(
                        'Role',
                        _formatRole(user['role'].toString()),
                        _getRoleIcon(user['role'].toString()),
                        valueColor: _roleColors[user['role']],
                      ),
                      _buildDetailRow(
                        'Member Since',
                        _formatDate(user['created_at']),
                        CupertinoIcons.calendar,
                        showDivider: false,
                      ),
                    ]),
                    const SizedBox(height: 22),
                    if (_isCurrentUser(user))
                      _groupedCard([
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          child: Text(
                            'You cannot change your own role.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _muted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ])
                    else
                      _groupedCard([
                        _settingsRow(
                          icon: CupertinoIcons.pencil,
                          iconColor: const Color(0xFF6366F1),
                          title: 'Change Role',
                          titleColor: const Color(0xFF6366F1),
                          onTap: () {
                            Navigator.pop(context);
                            _showRoleChangeDialog(user);
                          },
                        ),
                      ]),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(Map<String, dynamic> user, {double radius = 28}) {
    final avatarUrl = user['avatar_url']?.toString() ?? '';
    final role = user['role']?.toString() ?? 'student';
    final color = _roleColors[role] ?? const Color(0xFF6366F1);

    if (avatarUrl.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: NetworkImage(avatarUrl),
      );
    }

    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withValues(alpha: 0.7)],
        ),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          _getInitials(user['full_name'].toString()),
          style: TextStyle(
            fontSize: radius * 0.72,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(
    String label,
    String value,
    IconData icon, {
    Color? valueColor,
    bool showDivider = true,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(
            children: [
              _glyph(icon, const Color(0xFF6366F1)),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(fontSize: 17, color: _titleColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 17,
                    color: valueColor ?? _muted,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (showDivider) _hairline(),
      ],
    );
  }

  Widget _groupedCard(List<Widget> children) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ColoredBox(
        color: _card,
        child: Column(children: children),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.4,
          color: _muted,
        ),
      ),
    );
  }

  Widget _glyph(IconData icon, Color color) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: color.withValues(alpha: _isDark ? 0.2 : 0.12),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(icon, color: color, size: 17),
    );
  }

  Widget _hairline({double indent = 54}) {
    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: Divider(height: 0.5, thickness: 0.5, color: _chip),
    );
  }

  Widget _settingsRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    Color? titleColor,
    Widget? trailing,
    bool showChevron = true,
    bool showDivider = false,
    VoidCallback? onTap,
  }) {
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap == null
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    onTap();
                  },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              child: Row(
                children: [
                  _glyph(icon, iconColor),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 17,
                            color: titleColor ?? _titleColor,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: TextStyle(fontSize: 13, color: _muted),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) trailing,
                  if (showChevron)
                    Icon(
                      CupertinoIcons.chevron_forward,
                      size: 16,
                      color: _muted,
                    ),
                ],
              ),
            ),
          ),
        ),
        if (showDivider) _hairline(),
      ],
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.isEmpty || parts.first.isEmpty) return 'U';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts.last[0]}'.toUpperCase();
  }

  String _formatRole(String role) {
    if (SystemAdminDashboard.isSystemAdminRole(role)) return 'System Admin';
    return role.split('_').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1);
    }).join(' ');
  }

  IconData _getRoleIcon(String role) {
    switch (role.toLowerCase()) {
      case 'system_admin':
      case 'super_admin':
        return CupertinoIcons.shield_lefthalf_fill;
      case 'admin':
        return CupertinoIcons.checkmark_seal_fill;
      case 'lecturer':
        return CupertinoIcons.book_fill;
      case 'class_rep':
        return CupertinoIcons.person_2_fill;
      case 'assistant_class_rep':
        return CupertinoIcons.person_2;
      case 'student':
      default:
        return CupertinoIcons.person_fill;
    }
  }

  String _formatDate(dynamic dateValue) {
    final date = _parseDate(dateValue);
    if (date == null) return 'N/A';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  Future<void> _loadCourses() async {
    setState(() => _isLoadingCourses = true);
    try {
      final courses = await CourseService.instance.listCourses();
      courses.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      if (!mounted) return;
      setState(() {
        _courses = courses;
        _isLoadingCourses = false;
        final courseIds = courses.map((c) => c.id).toSet();
        if (_userCourseFilter != 'all' &&
            !courseIds.contains(_userCourseFilter)) {
          _userCourseFilter = 'all';
        }
        if (_staffCourseFilter != 'all' &&
            !courseIds.contains(_staffCourseFilter)) {
          _staffCourseFilter = 'all';
        }
        _filterLists();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingCourses = false);
    }
  }

  Future<void> _openCourseAddition({Course? course}) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => CourseAdditionScreen(course: course),
      ),
    );
    if (saved == true && mounted) {
      await _loadCourses();
    }
  }

  List<Map<String, dynamic>> _associatedProfiles(Course course) {
    return CourseService.instance.profilesForCourse(
      course,
      _profiles,
      courses: _courses,
    );
  }

  Future<void> _showDeleteCourseDialog(Course course) async {
    final associated = _associatedProfiles(course);
    var deleteUsers = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: _card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Text(
                'Delete course',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _titleColor,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'This will remove "${course.name}" from the database and permanently delete its Drive folder, including year / semester folders and files inside it.',
                    style: TextStyle(color: _muted),
                  ),
                  const SizedBox(height: 16),
                  CheckboxListTile(
                    value: deleteUsers,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: const Color(0xFFEF4444),
                    title: Text(
                      associated.isEmpty
                          ? 'Also delete users linked to this course'
                          : 'Also delete ${associated.length} user${associated.length == 1 ? '' : 's'} linked to this course',
                    ),
                    subtitle: const Text(
                      'Matches profiles whose admission number belongs to this course.',
                    ),
                    onChanged: (value) {
                      setDialogState(() {
                        deleteUsers = value ?? false;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Delete'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true || !mounted) return;
    await _deleteCourse(course, deleteAssociatedUsers: deleteUsers);
  }

  Future<void> _deleteCourse(
    Course course, {
    required bool deleteAssociatedUsers,
  }) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
        ),
      ),
    );

    try {
      final deletedUsers = await CourseService.instance.deleteCourse(
        course: course,
        deleteAssociatedUsers: deleteAssociatedUsers,
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            deletedUsers > 0
                ? 'Deleted ${course.name} and $deletedUsers associated user${deletedUsers == 1 ? '' : 's'}'
                : 'Deleted ${course.name}',
          ),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _loadCourses();
      if (deleteAssociatedUsers) {
        await _loadProfiles();
      }
    } catch (error) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not delete course: $error'),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildAddCourseButton() {
    return _settingsRow(
      icon: CupertinoIcons.add,
      iconColor: const Color(0xFF6366F1),
      title: 'Add Course',
      showDivider: true,
      onTap: _openCourseAddition,
    );
  }

  void _showCourseActions(Course course) {
    HapticFeedback.selectionClick();
    showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: Text(course.name),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              _openCourseAddition(course: course);
            },
            child: const Text('Edit Course'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.pop(context);
              _showDeleteCourseDialog(course);
            },
            child: const Text('Delete Course'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  Widget _buildCourseCard(Course course, {required bool showDivider}) {
    final semesterCount = course.semesters.length;
    final canManage = course.id != 'engineering' &&
        course.name.toLowerCase() != 'engineering';
    return _settingsRow(
      icon: CupertinoIcons.book_fill,
      iconColor: const Color(0xFF6366F1),
      title: course.name,
      subtitle:
          '${course.years} ${course.years == 1 ? 'year' : 'years'} • $semesterCount semester folders • ${course.admissionPrefix.isEmpty ? (course.sampleAdmissionNumber.isEmpty ? '—' : course.sampleAdmissionNumber) : course.admissionPrefix}',
      showChevron: canManage,
      showDivider: showDivider,
      onTap: canManage ? () => _showCourseActions(course) : null,
    );
  }

  Widget _buildAvailableCourses() {
    if (_isLoadingCourses) {
      return _groupedCard([
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: Center(child: CupertinoActivityIndicator()),
        ),
      ]);
    }
    if (_courses.isEmpty) {
      return _groupedCard([
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Text(
            'No courses yet. Add one to create Drive folders.',
            style: TextStyle(color: _muted, fontSize: 15),
          ),
        ),
      ]);
    }
    return _groupedCard([
      for (var i = 0; i < _courses.length; i++)
        _buildCourseCard(
          _courses[i],
          showDivider: i < _courses.length - 1,
        ),
    ]);
  }

  static const _googleAuthUrl = 'https://edupal-backend.onrender.com/auth/google';

  Future<void> _openRefreshTokenInChrome() async {
    try {
      var launched = false;

      if (Platform.isAndroid) {
        try {
          launched = await launchUrl(
            Uri.parse('googlechrome://navigate?url=$_googleAuthUrl'),
            mode: LaunchMode.externalApplication,
          );
        } catch (_) {
          launched = false;
        }
      } else if (Platform.isIOS) {
        final chromeUri = Uri.parse(
          'googlechromes://edupal-backend.onrender.com/auth/google',
        );
        if (await canLaunchUrl(chromeUri)) {
          launched = await launchUrl(
            chromeUri,
            mode: LaunchMode.externalApplication,
          );
        }
      }

      if (!launched) {
        launched = await launchUrl(
          Uri.parse(_googleAuthUrl),
          mode: LaunchMode.externalApplication,
        );
      }

      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open Google Chrome.'),
            backgroundColor: Color(0xFFEF4444),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open Google Chrome: $e'),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
    }
  }

  Widget _buildTokenRefreshSection() {
    return _settingsRow(
      icon: CupertinoIcons.refresh,
      iconColor: const Color(0xFF6366F1),
      title: 'Refresh Token',
      subtitle: 'Open Google sign-in in Chrome',
      showChevron: true,
      onTap: _openRefreshTokenInChrome,
    );
  }

  Widget _buildStatisticsSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('Management'),
          _groupedCard([
            _buildAddCourseButton(),
            _buildTokenRefreshSection(),
          ]),
          const SizedBox(height: 18),
          _sectionLabel('Courses'),
          _buildAvailableCourses(),
          const SizedBox(height: 18),
          _sectionLabel('Overview'),
          _groupedCard([
            _settingsRow(
              icon: CupertinoIcons.chart_bar_alt_fill,
              iconColor: const Color(0xFF6366F1),
              title: 'Statistics',
              subtitle: _newThisWeek > 0
                  ? '+$_newThisWeek new this week'
                  : 'People on the platform',
              showChevron: false,
              trailing: Icon(
                _isStatsExpanded
                    ? CupertinoIcons.chevron_up
                    : CupertinoIcons.chevron_down,
                size: 16,
                color: _muted,
              ),
              onTap: () {
                setState(() => _isStatsExpanded = !_isStatsExpanded);
              },
            ),
            if (_isStatsExpanded) ...[
              _hairline(),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: IntrinsicHeight(
                  child: Row(
                    children: [
                      _statCell(
                        '$_totalUsers',
                        'Users',
                        CupertinoIcons.person_2_fill,
                      ),
                      VerticalDivider(width: 1, thickness: 0.5, color: _chip),
                      _statCell(
                        '$_totalStaff',
                        'Staff',
                        CupertinoIcons.briefcase_fill,
                      ),
                    ],
                  ),
                ),
              ),
              _hairline(),
              _countRow(
                'Students',
                '$_totalStudents',
                _roleColors['student']!,
                _getRoleIcon('student'),
                showDivider: true,
              ),
              _countRow(
                'Class Reps',
                '$_totalClassReps',
                _roleColors['class_rep']!,
                _getRoleIcon('class_rep'),
                showDivider: true,
              ),
              _countRow(
                'Asst. Class Reps',
                '$_totalAssistantClassReps',
                _roleColors['assistant_class_rep']!,
                _getRoleIcon('assistant_class_rep'),
                showDivider: true,
              ),
              _countRow(
                'Lecturers',
                '$_totalLecturers',
                _roleColors['lecturer']!,
                _getRoleIcon('lecturer'),
                showDivider: true,
              ),
              _countRow(
                'Admins',
                '$_totalAdmins',
                _roleColors['admin']!,
                _getRoleIcon('admin'),
                showDivider: true,
              ),
              _countRow(
                'System Admins',
                '$_totalSystemAdmins',
                _roleColors['system_admin']!,
                _getRoleIcon('system_admin'),
              ),
            ],
          ]),
        ],
      ),
    );
  }

  Widget _statCell(String value, String label, IconData icon) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF6366F1)),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
              color: _titleColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _muted),
          ),
        ],
      ),
    );
  }

  Widget _countRow(
    String label,
    String value,
    Color color,
    IconData icon, {
    bool showDivider = false,
  }) {
    return _settingsRow(
      icon: icon,
      iconColor: color,
      title: label,
      trailing: Text(
        value,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
      showChevron: false,
      showDivider: showDivider,
    );
  }

  Widget _buildFilterChip(
    String label,
    String value,
    bool isUserTab, {
    bool isCourseFilter = false,
  }) {
    final isSelected = isCourseFilter
        ? (isUserTab
            ? _userCourseFilter == value
            : _staffCourseFilter == value)
        : (isUserTab
            ? _userRoleFilter == value
            : _staffRoleFilter == value);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() {
            if (isCourseFilter) {
              if (isUserTab) {
                _userCourseFilter = value;
              } else {
                _staffCourseFilter = value;
              }
            } else if (isUserTab) {
              _userRoleFilter = value;
            } else {
              _staffRoleFilter = value;
            }
            _filterLists();
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF6366F1).withValues(alpha: _isDark ? 0.22 : 0.12)
                : _chip,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF6366F1)
                  : (_isDark ? const Color(0xFF374151) : const Color(0xFFE5E7EB)),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: isSelected ? const Color(0xFF6366F1) : _muted,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user, {required bool showDivider}) {
    final role = user['role'].toString();
    final roleColor = _roleColors[role] ?? const Color(0xFF6366F1);
    final email = user['email'].toString();
    final username = user['username'].toString();
    final course = _courseForProfile(user);
    final registration = user['registration_number']?.toString() ?? '';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showUserDetails(user),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  _buildAvatar(user, radius: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user['full_name'].toString(),
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: _titleColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          email.isNotEmpty
                              ? email
                              : (username.isNotEmpty ? '@$username' : 'No email'),
                          style: TextStyle(fontSize: 13, color: _muted),
                        ),
                        if (course != null || registration.isNotEmpty)
                          Text(
                            course != null
                                ? (registration.isNotEmpty
                                    ? '${course.name} · $registration'
                                    : course.name)
                                : registration,
                            style: TextStyle(fontSize: 12, color: _muted),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    _formatRole(role),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: roleColor,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(CupertinoIcons.chevron_forward, size: 16, color: _muted),
                ],
              ),
            ),
            if (showDivider) _hairline(indent: 72),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(CupertinoIcons.person_2, size: 48, color: _muted),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: 18,
              color: _muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterHeader({
    required bool isUserTab,
    required String searchHint,
    required List<String> roles,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: _bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CupertinoSearchTextField(
            onChanged: (value) {
              setState(() {
                if (isUserTab) {
                  _userSearchQuery = value;
                } else {
                  _staffSearchQuery = value;
                }
                _filterLists();
              });
            },
            placeholder: searchHint,
            backgroundColor: _card,
            style: TextStyle(color: _titleColor, fontSize: 17),
            placeholderStyle: TextStyle(color: _muted, fontSize: 17),
            prefixIcon: Icon(CupertinoIcons.search, color: _muted, size: 18),
            itemColor: _muted,
          ),
          const SizedBox(height: 12),
          Text(
            'Role',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _muted,
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('All', 'all', isUserTab),
                ...roles.map(
                  (role) =>
                      _buildFilterChip(_formatRole(role), role, isUserTab),
                ),
              ],
            ),
          ),
          if (_courses.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Course',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _muted,
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip(
                    'All courses',
                    'all',
                    isUserTab,
                    isCourseFilter: true,
                  ),
                  ..._courses.map(
                    (course) => _buildFilterChip(
                      course.name,
                      course.id,
                      isUserTab,
                      isCourseFilter: true,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildListTab({
    required bool isUserTab,
    required List<Map<String, dynamic>> items,
    required String searchHint,
    required List<String> roles,
  }) {
    // CustomScrollView (not Column+Expanded) so NestedScrollView can give the
    // body near-zero height while Overview still fills the viewport without
    // overflowing the search/filter header.
    return CustomScrollView(
      key: PageStorageKey<String>(isUserTab ? 'users-tab' : 'staff-tab'),
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        SliverToBoxAdapter(
          child: _buildFilterHeader(
            isUserTab: isUserTab,
            searchHint: searchHint,
            roles: roles,
          ),
        ),
        if (items.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _buildEmptyState(
              isUserTab ? 'No users found' : 'No staff found',
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            sliver: SliverToBoxAdapter(
              child: _groupedCard([
                for (var i = 0; i < items.length; i++)
                  _buildUserCard(
                    items[i],
                    showDivider: i < items.length - 1,
                  ),
              ]),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: _isLoading
          ? Center(
              child: CupertinoActivityIndicator(
                color: _isDark ? const Color(0xFFF9FAFB) : const Color(0xFF6B7280),
              ),
            )
          : NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) {
                return [
                  SliverAppBar.large(
                    backgroundColor: _bg,
                    surfaceTintColor: Colors.transparent,
                    foregroundColor: _titleColor,
                    title: const Text(
                      'System Admin',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    actions: [
                      CupertinoButton(
                        padding: const EdgeInsets.only(right: 4),
                        onPressed: _openCourseAddition,
                        child: const Text(
                          'Add',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF6366F1),
                          ),
                        ),
                      ),
                      CupertinoButton(
                        padding: const EdgeInsets.only(right: 8),
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          _loadProfiles();
                          _loadCourses();
                        },
                        child: const Icon(
                          CupertinoIcons.refresh,
                          color: Color(0xFF6366F1),
                        ),
                      ),
                    ],
                  ),
                  SliverToBoxAdapter(child: _buildStatisticsSection()),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: CupertinoSlidingSegmentedControl<int>(
                        groupValue: _tabController.index,
                        backgroundColor: _chip,
                        thumbColor: _card,
                        children: {
                          0: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'Users ($_totalUsers)',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _titleColor,
                              ),
                            ),
                          ),
                          1: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'Staff ($_totalStaff)',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _titleColor,
                              ),
                            ),
                          ),
                        },
                        onValueChanged: (value) {
                          if (value == null) return;
                          HapticFeedback.selectionClick();
                          _tabController.animateTo(value);
                          setState(() {});
                        },
                      ),
                    ),
                  ),
                ];
              },
              body: ColoredBox(
                color: _bg,
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildListTab(
                      isUserTab: true,
                      items: _filteredUsers,
                      searchHint: 'Search users',
                      roles: _userRoles,
                    ),
                    _buildListTab(
                      isUserTab: false,
                      items: _filteredStaff,
                      searchHint: 'Search staff',
                      roles: _staffRoles,
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
