import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/course_service.dart';
import '../ui/adaptive_layout.dart';

class CourseMembersScreen extends StatefulWidget {
  const CourseMembersScreen({super.key});

  @override
  State<CourseMembersScreen> createState() => _CourseMembersScreenState();
}

class _CourseMembersScreenState extends State<CourseMembersScreen> {
  static const _accent = Color(0xFF6366F1);
  static const _danger = Color(0xFFEF4444);
  static const _success = Color(0xFF10B981);

  final _firestore = FirebaseFirestore.instance;

  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _filteredMembers = [];
  bool _isLoading = true;
  bool _isAdmin = false;
  String _searchQuery = '';
  String _roleFilter = 'all';
  String? _currentUserId;
  String? _courseName;
  String? _coursePrefix;

  static const _memberRoles = {
    'student',
    'class_rep',
    'assistant_class_rep',
  };

  static const _assignableRoles = [
    'student',
    'class_rep',
    'assistant_class_rep',
  ];

  static const _roleColors = {
    'class_rep': Color(0xFFF59E0B),
    'assistant_class_rep': Color(0xFF06B6D4),
    'student': Color(0xFF10B981),
  };

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    setState(() => _isLoading = true);

    try {
      final user = AuthService.instance.currentUser;
      if (user == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      _currentUserId = user.uid;
      final myDoc = await _firestore.collection('profiles').doc(user.uid).get();
      final myData = myDoc.data() ?? {};
      _isAdmin = (myData['role'] as String?)?.toLowerCase() == 'admin';
      final admissionNumber = (myData['admission_number'] as String?) ?? '';

      final courses = await CourseService.instance.listCourses();
      final course =
          CourseService.instance.matchCourse(admissionNumber, courses);

      if (course == null) {
        if (!mounted) return;
        setState(() {
          _members = [];
          _filteredMembers = [];
          _courseName = null;
          _coursePrefix = null;
          _isLoading = false;
        });
        return;
      }

      _courseName = course.name;
      _coursePrefix = course.admissionPrefix;

      final snapshot = await _firestore.collection('profiles').get();
      final profiles = snapshot.docs.map((doc) {
        final data = Map<String, dynamic>.from(doc.data());
        data['id'] = doc.id;
        data['role'] = (data['role'] as String?) ?? 'student';
        data['full_name'] = data['full_name'] ?? 'Unknown user';
        data['username'] = data['username'] ?? '';
        data['email'] = data['email'] ?? '';
        data['admission_number'] = data['admission_number'] ?? '';
        data['avatar_url'] = data['avatar_url'] ?? '';
        return data;
      }).toList();

      final members = CourseService.instance
          .profilesForCourse(course, profiles, courses: courses)
          .where((profile) {
            final role = profile['role'].toString().toLowerCase();
            return _memberRoles.contains(role);
          })
          .toList()
        ..sort((a, b) {
          final rank = (Map<String, dynamic> user) {
            switch (user['role'].toString()) {
              case 'class_rep':
                return 0;
              case 'assistant_class_rep':
                return 1;
              default:
                return 2;
            }
          };
          final byRole = rank(a).compareTo(rank(b));
          if (byRole != 0) return byRole;
          return a['full_name']
              .toString()
              .toLowerCase()
              .compareTo(b['full_name'].toString().toLowerCase());
        });

      if (!mounted) return;
      setState(() {
        _members = members;
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading course members: $e'),
          backgroundColor: _danger,
        ),
      );
    }
  }

  void _applyFilters() {
    _filteredMembers = _members.where((member) {
      final matchesRole =
          _roleFilter == 'all' || member['role'] == _roleFilter;
      if (!matchesRole) return false;
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return member['full_name'].toString().toLowerCase().contains(q) ||
          member['username'].toString().toLowerCase().contains(q) ||
          member['email'].toString().toLowerCase().contains(q) ||
          member['admission_number'].toString().toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _updateRole(Map<String, dynamic> member, String newRole) async {
    if (!_isAdmin) return;
    if (member['id'] == _currentUserId) return;
    if (!_assignableRoles.contains(newRole)) return;
    if (member['role'] == newRole) return;

    try {
      await _firestore.collection('profiles').doc(member['id']).update({
        'role': newRole,
        'updated_at': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${member['full_name']} is now ${_formatRole(newRole)}',
          ),
          backgroundColor: _success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _loadMembers();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update role: $e'),
          backgroundColor: _danger,
        ),
      );
    }
  }

  void _showRoleActions(Map<String, dynamic> member) {
    final role = member['role'].toString();
    final isSelf = member['id'] == _currentUserId;
    final canChange = _isAdmin && !isSelf && _assignableRoles.contains(role);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheet = isDark ? const Color(0xFF1F2937) : Colors.white;
    final primaryText =
        isDark ? const Color(0xFFF9FAFB) : const Color(0xFF111827);
    final secondaryText =
        isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
    final handle = isDark ? const Color(0xFF4B5563) : const Color(0xFFD1D5DB);

    showModalBottomSheet(
      context: context,
      backgroundColor: sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: handle,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                member['full_name'].toString(),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: primaryText,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                member['admission_number'].toString(),
                style: TextStyle(color: secondaryText),
              ),
              const SizedBox(height: 8),
              _roleChip(role),
              const SizedBox(height: 20),
              if (!canChange)
                Text(
                  isSelf
                      ? 'You cannot change your own role.'
                      : !_isAdmin
                          ? 'Only admins can change member roles.'
                          : 'This member’s role cannot be changed here.',
                  style: TextStyle(color: secondaryText),
                )
              else
                ..._assignableRoles.map((option) {
                  final isCurrent = option == role;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      _roleIcon(option),
                      color: _roleColors[option],
                    ),
                    title: Text(
                      'Make ${_formatRole(option)}',
                      style: TextStyle(color: primaryText),
                    ),
                    trailing: isCurrent
                        ? const Icon(
                            CupertinoIcons.check_mark,
                            color: Color(0xFF10B981),
                          )
                        : null,
                    enabled: !isCurrent,
                    onTap: isCurrent
                        ? null
                        : () {
                            Navigator.pop(context);
                            _updateRole(member, option);
                          },
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  String _formatRole(String role) {
    switch (role.toLowerCase()) {
      case 'class_rep':
        return 'Class Rep';
      case 'assistant_class_rep':
        return 'Assistant Class Rep';
      default:
        return 'Student';
    }
  }

  IconData _roleIcon(String role) {
    switch (role.toLowerCase()) {
      case 'class_rep':
        return CupertinoIcons.person_2_fill;
      case 'assistant_class_rep':
        return CupertinoIcons.person_2;
      default:
        return CupertinoIcons.person_fill;
    }
  }

  Widget _roleChip(String role) {
    final color = _roleColors[role] ?? _accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_roleIcon(role), size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            _formatRole(role),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.isEmpty || parts.first.isEmpty) return 'U';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts.last[0]}'.toUpperCase();
  }

  Widget _avatar(Map<String, dynamic> member) {
    final url = member['avatar_url'].toString();
    final name = member['full_name'].toString();
    if (url.isNotEmpty) {
      return CircleAvatar(backgroundImage: NetworkImage(url));
    }
    return CircleAvatar(
      backgroundColor: _accent,
      child: Text(
        _initials(name),
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required String value,
    required Color card,
    required Color secondaryText,
    required Color divider,
  }) {
    final selected = _roleFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        showCheckmark: false,
        label: Text(label),
        selected: selected,
        onSelected: (_) {
          setState(() {
            _roleFilter = value;
            _applyFilters();
          });
        },
        backgroundColor: card,
        selectedColor: _accent.withValues(alpha: 0.18),
        labelStyle: TextStyle(
          color: selected ? _accent : secondaryText,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        ),
        side: BorderSide(color: selected ? _accent : divider),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background =
        isDark ? const Color(0xFF111827) : const Color(0xFFF8FAFC);
    final card = isDark ? const Color(0xFF1F2937) : Colors.white;
    final primaryText =
        isDark ? const Color(0xFFF9FAFB) : const Color(0xFF111827);
    final secondaryText =
        isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
    final divider = isDark ? const Color(0xFF374151) : const Color(0xFFE5E7EB);
    final pagePad = AdaptiveLayout.pagePadding(context);
    final tablet = AdaptiveLayout.isTablet(context);

    final students = _members.where((m) => m['role'] == 'student').length;
    final classReps = _members.where((m) => m['role'] == 'class_rep').length;
    final assistants =
        _members.where((m) => m['role'] == 'assistant_class_rep').length;

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        foregroundColor: primaryText,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(CupertinoIcons.back, color: primaryText),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: Text(
          'Course Members',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: tablet ? 22 : 20,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(CupertinoIcons.refresh, color: primaryText),
            onPressed: _loadMembers,
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: CupertinoActivityIndicator(
                color: isDark
                    ? const Color(0xFFF9FAFB)
                    : const Color(0xFF6B7280),
              ),
            )
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  color: card,
                  padding: EdgeInsets.fromLTRB(
                    pagePad.left,
                    16,
                    pagePad.right,
                    8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _courseName == null
                            ? 'Add an admission number that matches your course so members can be listed.'
                            : '$_courseName · ${_coursePrefix ?? ''} · ${_members.length} member${_members.length == 1 ? '' : 's'}',
                        style: TextStyle(
                          fontSize: 13,
                          color: secondaryText,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$students student${students == 1 ? '' : 's'} · $classReps class rep${classReps == 1 ? '' : 's'} · $assistants assistant${assistants == 1 ? '' : 's'}',
                        style: TextStyle(
                          fontSize: 12,
                          color: secondaryText.withOpacity(0.85),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        onChanged: (value) {
                          setState(() {
                            _searchQuery = value;
                            _applyFilters();
                          });
                        },
                        style: TextStyle(color: primaryText),
                        cursorColor: _accent,
                        decoration: InputDecoration(
                          hintText: 'Search members...',
                          hintStyle: TextStyle(color: secondaryText),
                          prefixIcon: Icon(
                            CupertinoIcons.search,
                            color: secondaryText,
                          ),
                          filled: true,
                          fillColor: background,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: divider),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                const BorderSide(color: _accent, width: 1.5),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _filterChip(
                              label: 'All',
                              value: 'all',
                              card: background,
                              secondaryText: secondaryText,
                              divider: divider,
                            ),
                            _filterChip(
                              label: 'Students',
                              value: 'student',
                              card: background,
                              secondaryText: secondaryText,
                              divider: divider,
                            ),
                            _filterChip(
                              label: 'Class Reps',
                              value: 'class_rep',
                              card: background,
                              secondaryText: secondaryText,
                              divider: divider,
                            ),
                            _filterChip(
                              label: 'Assistants',
                              value: 'assistant_class_rep',
                              card: background,
                              secondaryText: secondaryText,
                              divider: divider,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _filteredMembers.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text(
                              _courseName == null
                                  ? 'Your admission number must match a course admission code, for example EB24/56171/21.'
                                  : 'No course members found.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16,
                                color: secondaryText,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: EdgeInsets.fromLTRB(
                            pagePad.left,
                            16,
                            pagePad.right,
                            24 + MediaQuery.viewPaddingOf(context).bottom,
                          ),
                          itemCount: _filteredMembers.length,
                          itemBuilder: (context, index) {
                            final member = _filteredMembers[index];
                            final role = member['role'].toString();
                            final isSelf = member['id'] == _currentUserId;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: card,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: divider),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.all(16),
                                leading: _avatar(member),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        member['full_name'].toString(),
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: primaryText,
                                        ),
                                      ),
                                    ),
                                    if (isSelf)
                                      Container(
                                        margin: const EdgeInsets.only(left: 8),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _accent.withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: const Text(
                                          'YOU',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: _accent,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    Text(
                                      member['admission_number'].toString(),
                                      style: TextStyle(color: secondaryText),
                                    ),
                                    const SizedBox(height: 6),
                                    _roleChip(role),
                                  ],
                                ),
                                trailing: Icon(
                                  CupertinoIcons.chevron_right,
                                  color: secondaryText,
                                ),
                                onTap: () => _showRoleActions(member),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
