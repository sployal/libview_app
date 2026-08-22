import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/auth_service.dart';
import '../services/course_service.dart';
import 'course_addition.dart';

class SuperAdminDashboard extends StatefulWidget {
  const SuperAdminDashboard({super.key});

  static const allowedEmail = 'muigaid91@gmail.com';
  static const superAdminRole = 'super_admin';

  static bool isAllowedEmail(String? email) =>
      email?.toLowerCase() == allowedEmail;

  /// Owner email or users with the `super_admin` role.
  static Future<bool> isCurrentUserSuperAdmin() async {
    final email = AuthService.instance.currentUser?.email;
    if (isAllowedEmail(email)) return true;
    final role = await AuthService.instance.currentRole();
    return role == superAdminRole;
  }

  @override
  State<SuperAdminDashboard> createState() => _SuperAdminDashboardState();
}

class _SuperAdminDashboardState extends State<SuperAdminDashboard>
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
  static const _staffRoles = ['lecturer', 'admin', 'super_admin'];
  static const _allRoles = [
    'student',
    'class_rep',
    'assistant_class_rep',
    'lecturer',
    'admin',
    'super_admin',
  ];

  final Map<String, Color> _roleColors = {
    'super_admin': const Color(0xFF0F172A),
    'admin': const Color(0xFFEF4444),
    'lecturer': const Color(0xFF8B5CF6),
    'class_rep': const Color(0xFFF59E0B),
    'assistant_class_rep': const Color(0xFF06B6D4),
    'student': const Color(0xFF10B981),
  };

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
  int get _totalSuperAdmins =>
      _profiles.where((p) => p['role'] == 'super_admin').length;

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
    _guardAndLoad();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _guardAndLoad() async {
    final hasAccess = await SuperAdminDashboard.isCurrentUserSuperAdmin();
    if (!hasAccess) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You do not have access to Super Admin.'),
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
        data['role'] = (data['role'] as String?) ?? 'student';
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
              Icon(Icons.check_circle, color: Colors.white),
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

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          'Change User Role',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              user['full_name'].toString(),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
            if ((user['email'] as String).isNotEmpty)
              Text(
                user['email'].toString(),
                style: const TextStyle(fontSize: 14, color: Colors.black87),
              ),
            const SizedBox(height: 20),
            const Text(
              'Select new role:',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            ..._allRoles.map((role) {
              final isCurrentRole = user['role'] == role;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: isCurrentRole
                      ? null
                      : () {
                          Navigator.pop(context);
                          _updateUserRole(user['id'], role);
                        },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _roleColors[role]!.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isCurrentRole
                            ? _roleColors[role]!
                            : _roleColors[role]!.withValues(alpha: 0.3),
                        width: isCurrentRole ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _getRoleIcon(role),
                          color: _roleColors[role],
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _formatRole(role),
                          style: TextStyle(
                            color: _roleColors[role],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        if (isCurrentRole)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _roleColors[role],
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Current',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
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
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Column(
                        children: [
                          _buildAvatar(user, radius: 50),
                          const SizedBox(height: 16),
                          Text(
                            user['full_name'].toString(),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                          if ((user['username'] as String).isNotEmpty)
                            Text(
                              '@${user['username']}',
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.black87,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    _buildDetailRow(
                      'Email',
                      (user['email'] as String).isEmpty
                          ? 'Not stored'
                          : user['email'].toString(),
                      Icons.email_rounded,
                    ),
                    const SizedBox(height: 16),
                    _buildDetailRow(
                      'Registration Number',
                      (user['registration_number'] as String).isEmpty
                          ? 'N/A'
                          : user['registration_number'].toString(),
                      Icons.badge_rounded,
                    ),
                    const SizedBox(height: 16),
                    _buildDetailRow(
                      'Course',
                      _courseForProfile(user)?.name ?? 'Unassigned',
                      Icons.menu_book_rounded,
                    ),
                    const SizedBox(height: 16),
                    _buildDetailRow(
                      'Role',
                      _formatRole(user['role'].toString()),
                      _getRoleIcon(user['role'].toString()),
                      valueColor: _roleColors[user['role']],
                    ),
                    const SizedBox(height: 16),
                    _buildDetailRow(
                      'Member Since',
                      _formatDate(user['created_at']),
                      Icons.calendar_today_rounded,
                    ),
                    const SizedBox(height: 32),
                    if (_isCurrentUser(user))
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'You cannot change your own role.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    else
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _showRoleChangeDialog(user);
                          },
                          icon: const Icon(Icons.edit_rounded),
                          label: const Text('Change Role'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6366F1),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
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

  Widget _buildDetailRow(String label, String value, IconData icon,
      {Color? valueColor}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20, color: const Color(0xFF6366F1)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: valueColor ?? Colors.black,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.isEmpty || parts.first.isEmpty) return 'U';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts.last[0]}'.toUpperCase();
  }

  String _formatRole(String role) {
    return role.split('_').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1);
    }).join(' ');
  }

  IconData _getRoleIcon(String role) {
    switch (role.toLowerCase()) {
      case 'super_admin':
        return Icons.shield_rounded;
      case 'admin':
        return Icons.admin_panel_settings_rounded;
      case 'lecturer':
        return Icons.school_rounded;
      case 'class_rep':
        return Icons.people_rounded;
      case 'assistant_class_rep':
        return Icons.group_outlined;
      case 'student':
      default:
        return Icons.person_rounded;
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Text(
                'Delete course',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'This will remove "${course.name}" from the database and permanently delete its Drive folder, including year / semester folders and files inside it.',
                    style: const TextStyle(color: Color(0xFF1F2937)),
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
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0F172A)),
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

  Widget _buildAddCourseButton({bool onDark = false}) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _openCourseAddition,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Add Course',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: onDark ? Colors.white : const Color(0xFF0F172A),
          foregroundColor: onDark ? const Color(0xFF0F172A) : Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildCourseCard(Course course) {
    final semesterCount = course.semesters.length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  course.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              if (course.id != 'engineering' &&
                  course.name.toLowerCase() != 'engineering')
                PopupMenuButton<String>(
                  tooltip: 'Course options',
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  icon: const Icon(
                    Icons.more_vert_rounded,
                    color: Color(0xFF0F172A),
                  ),
                  onSelected: (value) {
                    if (value == 'edit') {
                      _openCourseAddition(course: course);
                    } else if (value == 'delete') {
                      _showDeleteCourseDialog(course);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_rounded, size: 18),
                          SizedBox(width: 10),
                          Text('Edit course'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_rounded,
                            size: 18,
                            color: Color(0xFFEF4444),
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Delete course',
                            style: TextStyle(color: Color(0xFFEF4444)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${course.years} ${course.years == 1 ? 'year' : 'years'}  •  $semesterCount semester folders',
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF475569),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Admission: ${course.admissionPrefix.isEmpty ? (course.sampleAdmissionNumber.isEmpty ? '—' : course.sampleAdmissionNumber) : course.admissionPrefix}',
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF475569),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvailableCourses() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Available courses',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.white.withValues(alpha: 0.95),
          ),
        ),
        const SizedBox(height: 10),
        if (_isLoadingCourses)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ),
          )
        else if (_courses.isEmpty)
          Text(
            'No courses yet. Add one to create Drive folders.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 13,
            ),
          )
        else
          Column(
            children: [
              for (var i = 0; i < _courses.length; i++) ...[
                _buildCourseCard(_courses[i]),
                if (i < _courses.length - 1) const SizedBox(height: 8),
              ],
            ],
          ),
      ],
    );
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Token refresh',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.white.withValues(alpha: 0.95),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _openRefreshTokenInChrome,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text(
              'Refresh token',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF0F172A),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatisticsSection() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF334155)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.25),
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
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.shield_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Overview',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              IconButton(
                onPressed: () {
                  setState(() {
                    _isStatsExpanded = !_isStatsExpanded;
                  });
                },
                icon: AnimatedRotation(
                  turns: _isStatsExpanded ? 0 : 0.5,
                  duration: const Duration(milliseconds: 300),
                  child: const Icon(
                    Icons.keyboard_arrow_up_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildAddCourseButton(onDark: true),
          const SizedBox(height: 20),
          _buildAvailableCourses(),
          const SizedBox(height: 20),
          _buildTokenRefreshSection(),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: _isStatsExpanded
                ? Column(
                    children: [
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: _buildMainStatCard(
                              'Users',
                              _totalUsers.toString(),
                              Icons.people_rounded,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildMainStatCard(
                              'Staff',
                              _totalStaff.toString(),
                              Icons.badge_rounded,
                            ),
                          ),
                        ],
                      ),
                      if (_newThisWeek > 0) ...[
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '+$_newThisWeek new this week',
                            style: const TextStyle(
                              color: Color(0xFF86EFAC),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _buildRoleStatCard(
                              'Students',
                              _totalStudents.toString(),
                              _roleColors['student']!,
                              Icons.person_rounded,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildRoleStatCard(
                              'Class Reps',
                              _totalClassReps.toString(),
                              _roleColors['class_rep']!,
                              Icons.people_rounded,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildRoleStatCard(
                              'Asst. Class Reps',
                              _totalAssistantClassReps.toString(),
                              _roleColors['assistant_class_rep']!,
                              Icons.group_outlined,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(child: SizedBox()),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildRoleStatCard(
                              'Lecturers',
                              _totalLecturers.toString(),
                              _roleColors['lecturer']!,
                              Icons.school_rounded,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildRoleStatCard(
                              'Admins',
                              _totalAdmins.toString(),
                              _roleColors['admin']!,
                              Icons.admin_panel_settings_rounded,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildRoleStatCard(
                              'Super Admins',
                              _totalSuperAdmins.toString(),
                              _roleColors['super_admin']!,
                              Icons.shield_rounded,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(child: SizedBox()),
                        ],
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildMainStatCard(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF0F172A), size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: Colors.black54,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleStatCard(
      String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const Spacer(),
              Text(
                value,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black54,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
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
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) {
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
        backgroundColor: Colors.white,
        selectedColor: const Color(0xFF6366F1).withValues(alpha: 0.2),
        labelStyle: TextStyle(
          color: isSelected ? const Color(0xFF6366F1) : const Color(0xFF6B7280),
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
        side: BorderSide(
          color: isSelected ? const Color(0xFF6366F1) : const Color(0xFFE5E7EB),
        ),
      ),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    final role = user['role'].toString();
    final roleColor = _roleColors[role] ?? const Color(0xFF6366F1);
    final email = user['email'].toString();
    final username = user['username'].toString();
    final course = _courseForProfile(user);
    final registration = user['registration_number']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: _buildAvatar(user),
        title: Text(
          user['full_name'].toString(),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.black,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              email.isNotEmpty
                  ? email
                  : (username.isNotEmpty ? '@$username' : 'No email'),
              style: const TextStyle(color: Colors.black87),
            ),
            if (course != null || registration.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                course != null
                    ? (registration.isNotEmpty
                        ? '${course.name} · $registration'
                        : course.name)
                    : registration,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: roleColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: roleColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_getRoleIcon(role), size: 14, color: roleColor),
                  const SizedBox(width: 4),
                  Text(
                    _formatRole(role),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: roleColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => _showUserDetails(user),
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline_rounded, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
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
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
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
            decoration: InputDecoration(
              hintText: searchHint,
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Role',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
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
            const Text(
              'Course',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
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
      physics: const AlwaysScrollableScrollPhysics(),
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
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _buildUserCard(items[index]),
                childCount: items.length,
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Super Admin',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Add Course',
            icon: const Icon(Icons.add_rounded),
            onPressed: _openCourseAddition,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              _loadProfiles();
              _loadCourses();
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF0F172A),
          unselectedLabelColor: const Color(0xFF6B7280),
          indicatorColor: const Color(0xFF0F172A),
          tabs: [
            Tab(text: 'Users ($_totalUsers)'),
            Tab(text: 'Staff ($_totalStaff)'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0F172A)),
              ),
            )
          : NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) {
                return [
                  SliverToBoxAdapter(child: _buildStatisticsSection()),
                ];
              },
              body: TabBarView(
                controller: _tabController,
                children: [
                  _buildListTab(
                    isUserTab: true,
                    items: _filteredUsers,
                    searchHint: 'Search users...',
                    roles: _userRoles,
                  ),
                  _buildListTab(
                    isUserTab: false,
                    items: _filteredStaff,
                    searchHint: 'Search staff...',
                    roles: _staffRoles,
                  ),
                ],
              ),
            ),
    );
  }
}
