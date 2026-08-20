import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'course_addition.dart';

class SuperAdminDashboard extends StatefulWidget {
  const SuperAdminDashboard({super.key});

  static const allowedEmail = 'muigaid91@gmail.com';

  static bool get isCurrentUserSuperAdmin {
    final email = AuthService.instance.currentUser?.email;
    return email?.toLowerCase() == allowedEmail;
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
  bool _isLoading = true;
  bool _isStatsExpanded = true;
  String _userSearchQuery = '';
  String _staffSearchQuery = '';
  String _userRoleFilter = 'all';
  String _staffRoleFilter = 'all';

  static const _userRoles = ['student', 'class_rep'];
  static const _staffRoles = ['lecturer', 'admin'];
  static const _allRoles = ['student', 'class_rep', 'lecturer', 'admin'];

  final Map<String, Color> _roleColors = {
    'admin': const Color(0xFFEF4444),
    'lecturer': const Color(0xFF8B5CF6),
    'class_rep': const Color(0xFFF59E0B),
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
  int get _totalLecturers =>
      _profiles.where((p) => p['role'] == 'lecturer').length;
  int get _totalAdmins => _profiles.where((p) => p['role'] == 'admin').length;

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
    if (!SuperAdminDashboard.isCurrentUserSuperAdmin) {
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
      return _matchesSearch(user, _userSearchQuery);
    }).toList();

    _filteredStaff = _profiles.where((user) {
      if (!_staffRoles.contains(user['role'])) return false;
      if (_staffRoleFilter != 'all' && user['role'] != _staffRoleFilter) {
        return false;
      }
      return _matchesSearch(user, _staffSearchQuery);
    }).toList();
  }

  bool _matchesSearch(Map<String, dynamic> user, String query) {
    if (query.trim().isEmpty) return true;
    final q = query.toLowerCase();
    return user['full_name'].toString().toLowerCase().contains(q) ||
        user['username'].toString().toLowerCase().contains(q) ||
        user['email'].toString().toLowerCase().contains(q) ||
        user['registration_number'].toString().toLowerCase().contains(q);
  }

  DateTime? _parseDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  Future<void> _updateUserRole(String userId, String newRole) async {
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
                      color: _roleColors[role]!.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isCurrentRole
                            ? _roleColors[role]!
                            : _roleColors[role]!.withOpacity(0.3),
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
          colors: [color, color.withOpacity(0.7)],
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
      case 'admin':
        return Icons.admin_panel_settings_rounded;
      case 'lecturer':
        return Icons.school_rounded;
      case 'class_rep':
        return Icons.people_rounded;
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

  Future<void> _openCourseAddition() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CourseAdditionScreen(),
      ),
    );
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
            color: const Color(0xFF0F172A).withOpacity(0.25),
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
                  color: Colors.white.withOpacity(0.2),
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
                  backgroundColor: Colors.white.withOpacity(0.2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildAddCourseButton(onDark: true),
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
                  color: color.withOpacity(0.1),
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

  Widget _buildFilterChip(String label, String value, bool isUserTab) {
    final isSelected = isUserTab
        ? _userRoleFilter == value
        : _staffRoleFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) {
          setState(() {
            if (isUserTab) {
              _userRoleFilter = value;
            } else {
              _staffRoleFilter = value;
            }
            _filterLists();
          });
        },
        backgroundColor: Colors.white,
        selectedColor: const Color(0xFF6366F1).withOpacity(0.2),
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
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: roleColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: roleColor.withOpacity(0.3)),
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

  Widget _buildListTab({
    required bool isUserTab,
    required List<Map<String, dynamic>> items,
    required String searchHint,
    required List<String> roles,
  }) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Column(
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
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? _buildEmptyState(
                  isUserTab ? 'No users found' : 'No staff found',
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  itemBuilder: (context, index) => _buildUserCard(items[index]),
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
            onPressed: _loadProfiles,
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
          : Column(
              children: [
                _buildStatisticsSection(),
                Expanded(
                  child: TabBarView(
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
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCourseAddition,
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Course'),
      ),
    );
  }
}
