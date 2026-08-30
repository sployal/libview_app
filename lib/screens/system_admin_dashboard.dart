import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/auth_service.dart';
import '../services/client_service.dart';
import '../services/course_service.dart';
import '../services/upload_service.dart';
import 'client_editor_dialog.dart';
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

class _SystemAdminDashboardState extends State<SystemAdminDashboard> {
  final _firestore = FirebaseFirestore.instance;

  int _peopleTab = 0;

  List<Map<String, dynamic>> _profiles = [];
  List<Map<String, dynamic>> _filteredUsers = [];
  List<Map<String, dynamic>> _filteredStaff = [];
  List<Map<String, dynamic>> _filteredSuspended = [];
  List<Course> _courses = [];
  List<ClientWorkspace> _clients = [];
  bool _isLoading = true;
  bool _isLoadingCourses = true;
  bool _isLoadingClients = true;
  bool _isLoadingStorage = true;
  bool _isStatsExpanded = true;
  bool _isStorageExpanded = false;
  DriveStorageSnapshot? _storage;
  String? _storageError;
  String _userSearchQuery = '';
  String _staffSearchQuery = '';
  String _suspendedSearchQuery = '';
  String _userRoleFilter = 'all';
  String _staffRoleFilter = 'all';
  String _userCourseFilter = 'all';
  String _staffCourseFilter = 'all';
  bool _allowNewAccounts = true;
  String _restrictionMessage = AuthService.defaultSignupRestrictionMessage;
  bool _savingAccountPolicy = false;

  static const _userRoles = [
    'student',
    'class_rep',
    'assistant_class_rep',
    AuthService.clientRole,
  ];
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
    'system_admin': const Color(0xFFF472B6),
    'admin': const Color(0xFFEF4444),
    'lecturer': const Color(0xFF8B5CF6),
    'class_rep': const Color(0xFFF59E0B),
    'assistant_class_rep': const Color(0xFF0EA5E9),
    'student': const Color(0xFF10B981),
    'client': const Color(0xFF0EA5E9),
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
  int get _totalSuspended =>
      _profiles.where((p) => p['suspended'] == true).length;
  int get _totalClients =>
      _profiles.where((p) => AuthService.isClientRole(p['role'] as String?)).length;

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
    _guardAndLoad();
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
    await _loadClients();
    await _loadStorage();
    await _loadAccountCreationSettings();
  }

  Future<void> _loadProfiles({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final snapshot = await _firestore.collection('profiles').get();
      final authPhotos = await AuthService.instance.fetchAuthPhotoUrls();
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
        final storedGoogle = (data['google_photo_url'] as String?)?.trim() ?? '';
        final fromAuth = authPhotos[doc.id] ?? '';
        data['google_photo_url'] =
            fromAuth.isNotEmpty ? fromAuth : storedGoogle;
        data['suspended'] = data['suspended'] == true;
        data['suspension_message'] = data['suspension_message'] ?? '';
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
      if (silent) return;
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

    _filteredSuspended = _profiles.where((user) {
      if (user['suspended'] != true) return false;
      return _matchesSearch(user, _suspendedSearchQuery);
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
      final updates = <String, dynamic>{
        'role': newRole,
        'updated_at': FieldValue.serverTimestamp(),
      };
      if (!AuthService.isClientRole(newRole)) {
        updates['client_id'] = FieldValue.delete();
        final profile = await _firestore.collection('profiles').doc(userId).get();
        final previousClientId =
            (profile.data()?['client_id'] as String?)?.trim() ?? '';
        if (previousClientId.isNotEmpty) {
          await _firestore.collection('clients').doc(previousClientId).set({
            'member_uids': FieldValue.arrayRemove([userId]),
            'updated_at': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      }
      await _firestore.collection('profiles').doc(userId).update(updates);

      if (!mounted) return;
      _applyLocalRoleChange(userId, newRole);
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
      _loadProfiles(silent: true);
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

  void _applyLocalRoleChange(String userId, String newRole) {
    final normalized = SystemAdminDashboard.isSystemAdminRole(newRole)
        ? SystemAdminDashboard.systemAdminRole
        : newRole.toLowerCase();
    final movedToStaff = _staffRoles.contains(normalized);

    setState(() {
      final index = _profiles.indexWhere((p) => p['id'] == userId);
      if (index != -1) {
        _profiles[index]['role'] = normalized;
      }

      _peopleTab = movedToStaff ? 1 : 0;
      if (movedToStaff) {
        if (_staffRoleFilter != 'all' && _staffRoleFilter != normalized) {
          _staffRoleFilter = 'all';
        }
      } else if (_userRoleFilter != 'all' && _userRoleFilter != normalized) {
        _userRoleFilter = 'all';
      }
      _filterLists();
    });
  }

  bool _canSuspend(Map<String, dynamic> user) {
    if (_isCurrentUser(user)) return false;
    if (SystemAdminDashboard.isAllowedEmail(user['email'] as String?)) {
      return false;
    }
    return true;
  }

  bool _canDelete(Map<String, dynamic> user) => _canSuspend(user);

  Future<void> _suspendUser(Map<String, dynamic> user) async {
    if (!_canSuspend(user)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You cannot suspend this account.'),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
      return;
    }

    final message = await _promptRestrictionMessage(
      initial: AuthService.defaultSuspensionMessage,
      title: 'Suspend account',
      description:
          'This person will see this message and cannot use the app until you restore the account.',
      hintText: AuthService.defaultSuspensionMessage,
    );
    if (message == null || !mounted) return;

    try {
      await AuthService.instance.suspendAccount(
        userId: user['id'].toString(),
        message: message,
      );
      if (!mounted) return;
      setState(() {
        final index = _profiles.indexWhere((p) => p['id'] == user['id']);
        if (index != -1) {
          _profiles[index]['suspended'] = true;
          _profiles[index]['suspension_message'] = message;
        }
        _peopleTab = 2;
        _filterLists();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(CupertinoIcons.pause_circle_fill, color: Colors.white),
              SizedBox(width: 12),
              Text('Account suspended'),
            ],
          ),
          backgroundColor: Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not suspend account: $e'),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
    }
  }

  Future<void> _unsuspendUser(Map<String, dynamic> user) async {
    try {
      await AuthService.instance.unsuspendAccount(user['id'].toString());
      if (!mounted) return;
      setState(() {
        final index = _profiles.indexWhere((p) => p['id'] == user['id']);
        if (index != -1) {
          _profiles[index]['suspended'] = false;
          _profiles[index]['suspension_message'] = '';
        }
        _filterLists();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(CupertinoIcons.checkmark_circle_fill, color: Colors.white),
              SizedBox(width: 12),
              Text('Account restored'),
            ],
          ),
          backgroundColor: Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not restore account: $e'),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
    }
  }

  Future<void> _deleteUser(Map<String, dynamic> user) async {
    if (!_canDelete(user)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You cannot delete this account.'),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
      return;
    }

    final name = user['full_name']?.toString().trim() ?? '';
    final email = user['email']?.toString().trim() ?? '';
    final label = name.isNotEmpty ? name : (email.isNotEmpty ? email : 'this user');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: _card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Text(
            'Delete user',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
              color: _titleColor,
            ),
          ),
          content: Text(
            'This permanently removes $label from the app. They will need a new account to sign in again.',
            style: TextStyle(
              fontSize: 15,
              color: _muted,
              height: 1.35,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: TextStyle(color: _muted)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text(
                'Delete',
                style: TextStyle(
                  color: Color(0xFFEF4444),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    try {
      await AuthService.instance.deleteAccount(user['id'].toString());
      if (!mounted) return;
      setState(() {
        _profiles.removeWhere((p) => p['id'] == user['id']);
        _filterLists();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(CupertinoIcons.trash_fill, color: Colors.white),
              SizedBox(width: 12),
              Text('User deleted'),
            ],
          ),
          backgroundColor: Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not delete user: $e'),
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

    _showThemedActionSheet(
      title: 'Change Role',
      message: (user['email'] as String).isNotEmpty
          ? '${user['full_name']}\n${user['email']}'
          : user['full_name'].toString(),
      actions: [
        for (final role in _allRoles)
          _ThemedSheetAction(
            label: user['role'] == role
                ? '${_formatRole(role)} (Current)'
                : _formatRole(role),
            color: _roleColors[role] ?? const Color(0xFF6366F1),
            onTap: () {
              if (user['role'] != role) {
                _updateUserRole(user['id'], role);
              }
            },
          ),
      ],
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
                        'Status',
                        user['suspended'] == true ? 'Suspended' : 'Active',
                        user['suspended'] == true
                            ? CupertinoIcons.pause_circle_fill
                            : CupertinoIcons.checkmark_seal_fill,
                        valueColor: user['suspended'] == true
                            ? const Color(0xFFEF4444)
                            : const Color(0xFF10B981),
                      ),
                      if (user['suspended'] == true)
                        _buildDetailRow(
                          'Message',
                          AuthService.suspensionMessageFor(user),
                          CupertinoIcons.chat_bubble_text_fill,
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
                            'You cannot change, suspend, or delete your own account.',
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
                          showDivider: true,
                          onTap: () {
                            Navigator.pop(context);
                            _showRoleChangeDialog(user);
                          },
                        ),
                        if (user['suspended'] == true)
                          _settingsRow(
                            icon: CupertinoIcons.play_circle_fill,
                            iconColor: const Color(0xFF10B981),
                            title: 'Restore Account',
                            titleColor: const Color(0xFF10B981),
                            showDivider: true,
                            onTap: () {
                              Navigator.pop(context);
                              _unsuspendUser(user);
                            },
                          )
                        else if (_canSuspend(user))
                          _settingsRow(
                            icon: CupertinoIcons.pause_circle_fill,
                            iconColor: const Color(0xFFEF4444),
                            title: 'Suspend Account',
                            titleColor: const Color(0xFFEF4444),
                            showDivider: true,
                            onTap: () {
                              Navigator.pop(context);
                              _suspendUser(user);
                            },
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            child: Text(
                              'This account cannot be suspended or deleted.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _muted,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        if (_canDelete(user))
                          _settingsRow(
                            icon: CupertinoIcons.trash_fill,
                            iconColor: const Color(0xFFEF4444),
                            title: 'Delete User',
                            titleColor: const Color(0xFFEF4444),
                            onTap: () {
                              Navigator.pop(context);
                              _deleteUser(user);
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
    final avatarUrl = AuthService.displayAvatarUrl(
          avatarUrl: user['avatar_url']?.toString(),
          googlePhotoUrl: user['google_photo_url']?.toString(),
        ) ??
        '';
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: children),
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
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
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
      case 'client':
        return CupertinoIcons.folder_fill;
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

  Future<void> _loadClients() async {
    setState(() => _isLoadingClients = true);
    try {
      final clients = await ClientService.instance.listClients();
      if (!mounted) return;
      setState(() {
        _clients = clients;
        _isLoadingClients = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingClients = false);
    }
  }

  Map<String, dynamic>? _profileById(String uid) {
    for (final profile in _profiles) {
      if (profile['id']?.toString() == uid) return profile;
    }
    return null;
  }

  String _profileLabel(String uid) {
    final profile = _profileById(uid);
    if (profile == null) return uid;
    final name = profile['full_name']?.toString().trim() ?? '';
    if (name.isNotEmpty) return name;
    final email = profile['email']?.toString().trim() ?? '';
    return email.isNotEmpty ? email : uid;
  }

  Future<void> _showCreateClientDialog() async {
    final created = await showClientEditorDialog(context: context);
    if (created == null || !mounted) return;
    final name = created.name;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(18),
          ),
          child: const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
          ),
        ),
      ),
    );

    try {
      await ClientService.instance.createClient(
        name: name,
        email: created.email,
        storageLimitBytes: created.storageLimitBytes,
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Created client "$name"'),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _loadClients();
      await _loadStorage(refresh: true);
    } catch (error) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not create client: $error'),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _showEditClientDialog(ClientWorkspace client) async {
    final edited = await showClientEditorDialog(
      context: context,
      client: client,
    );
    if (edited == null || !mounted) return;
    try {
      await ClientService.instance.updateClient(
        client: client,
        name: edited.name,
        email: edited.email,
        storageLimitBytes: edited.storageLimitBytes,
      );
      if (!mounted) return;
      await _loadClients();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Client updated'),
          backgroundColor: Color(0xFF10B981),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update client: $error'),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
    }
  }

  Future<void> _confirmDeleteClient(ClientWorkspace client) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: _card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Text(
            'Delete client',
            style: TextStyle(fontWeight: FontWeight.w700, color: _titleColor),
          ),
          content: Text(
            'This permanently deletes "${client.name}", its Drive folder under Edupal/clients, and attached users. They will need a new account to sign in again.',
            style: TextStyle(color: _muted, height: 1.35),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text(
                'Delete',
                style: TextStyle(
                  color: Color(0xFFEF4444),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    try {
      final deletedUsers = await ClientService.instance.deleteClient(client);
      if (!mounted) return;
      await _loadClients();
      await _loadProfiles(silent: true);
      await _loadStorage(refresh: true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            deletedUsers > 0
                ? 'Deleted ${client.name} and $deletedUsers attached user${deletedUsers == 1 ? '' : 's'}'
                : 'Deleted ${client.name}',
          ),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not delete client: $error'),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
    }
  }

  void _showClientActions(ClientWorkspace client) {
    HapticFeedback.selectionClick();
    _showThemedActionSheet(
      title: client.name,
      message: client.ownerUid.isEmpty
          ? 'No user attached yet'
          : 'Owner: ${_profileLabel(client.ownerUid)}',
      actions: [
        _ThemedSheetAction(
          label: 'Edit client',
          color: const Color(0xFF8B5CF6),
          onTap: () => _showEditClientDialog(client),
        ),
        _ThemedSheetAction(
          label: 'Delete client',
          color: const Color(0xFFEF4444),
          onTap: () => _confirmDeleteClient(client),
        ),
      ],
    );
  }

  Widget _buildAddClientButton() {
    return _settingsRow(
      icon: CupertinoIcons.person_badge_plus,
      iconColor: const Color(0xFF0EA5E9),
      title: 'Add Client',
      showDivider: true,
      onTap: _showCreateClientDialog,
    );
  }

  Widget _buildClientCard(ClientWorkspace client, {required bool showDivider}) {
    final owner = client.ownerUid.isEmpty
        ? (client.inviteEmail.isEmpty ? 'Unassigned' : client.inviteEmail)
        : _profileLabel(client.ownerUid);
    final extra = client.memberUids.length > 1
        ? ' • ${client.memberUids.length} members'
        : '';
    return _settingsRow(
      icon: CupertinoIcons.folder_fill,
      iconColor: const Color(0xFF0EA5E9),
      title: client.name,
      subtitle:
          '$owner$extra • ${ClientWorkspace.formatStorage(client.storageLimitBytes)} limit',
      showChevron: true,
      showDivider: showDivider,
      onTap: () => _showClientActions(client),
    );
  }

  Widget _buildAvailableClients() {
    if (_isLoadingClients) {
      return _groupedCard([
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: Center(child: CupertinoActivityIndicator()),
        ),
      ]);
    }
    if (_clients.isEmpty) {
      return _groupedCard([
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Text(
            'No clients yet. Add one to create a folder under Edupal/clients.',
            style: TextStyle(color: _muted, fontSize: 15),
          ),
        ),
      ]);
    }
    return _groupedCard([
      for (var i = 0; i < _clients.length; i++)
        _buildClientCard(
          _clients[i],
          showDivider: i < _clients.length - 1,
        ),
    ]);
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
      await _loadStorage(refresh: true);
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
                borderRadius: BorderRadius.circular(18),
              ),
              title: Text(
                'Delete course',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                  color: _titleColor,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'This will remove "${course.name}" from the database and permanently delete its Drive folder, including year / semester folders and files inside it.',
                    style: TextStyle(
                      fontSize: 15,
                      color: _muted,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 16),
                  CheckboxListTile(
                    value: deleteUsers,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: const Color(0xFFEF4444),
                    checkColor: Colors.white,
                    side: BorderSide(color: _muted),
                    title: Text(
                      associated.isEmpty
                          ? 'Also delete users linked to this course'
                          : 'Also delete ${associated.length} user${associated.length == 1 ? '' : 's'} linked to this course',
                      style: TextStyle(
                        color: _titleColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      'Removes matching profiles and their sign-in accounts. Your account and the owner account are skipped.',
                      style: TextStyle(color: _muted, fontSize: 13),
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
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Color(0xFF8E8E93)),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text(
                    'Delete',
                    style: TextStyle(
                      color: Color(0xFFEF4444),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
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
      builder: (context) => Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(18),
          ),
          child: const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
          ),
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
      await _loadStorage(refresh: true);
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
    final canEdit = course.id != 'engineering' &&
        course.name.toLowerCase() != 'engineering';
    _showThemedActionSheet(
      title: course.name,
      message: course.suspended
          ? (course.suspensionTopic.isEmpty
              ? 'This course is suspended'
              : course.suspensionTopic)
          : null,
      actions: [
        if (canEdit)
          _ThemedSheetAction(
            label: 'Edit Course',
            color: const Color(0xFF6366F1),
            onTap: () => _openCourseAddition(course: course),
          ),
        if (course.suspended)
          _ThemedSheetAction(
            label: 'Restore Course',
            color: const Color(0xFF10B981),
            onTap: () => _unsuspendCourse(course),
          )
        else
          _ThemedSheetAction(
            label: 'Suspend Course',
            color: const Color(0xFFF59E0B),
            onTap: () => _showSuspendCourseDialog(course),
          ),
        if (canEdit)
          _ThemedSheetAction(
            label: 'Delete Course',
            color: const Color(0xFFEF4444),
            onTap: () => _showDeleteCourseDialog(course),
          ),
      ],
    );
  }

  Future<void> _showSuspendCourseDialog(Course course) async {
    final notice = await _promptCourseSuspensionNotice(course);
    if (notice == null || !mounted) return;
    try {
      final updated = await CourseService.instance.suspendCourse(
        course: course,
        topic: notice.topic,
        message: notice.message,
      );
      if (!mounted) return;
      setState(() {
        final index = _courses.indexWhere((item) => item.id == course.id);
        if (index != -1) {
          _courses[index] = updated;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(CupertinoIcons.pause_circle_fill, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text('${course.name} suspended')),
            ],
          ),
          backgroundColor: const Color(0xFFF59E0B),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not suspend course: $e'),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
    }
  }

  Future<void> _unsuspendCourse(Course course) async {
    try {
      final updated = await CourseService.instance.unsuspendCourse(course);
      if (!mounted) return;
      setState(() {
        final index = _courses.indexWhere((item) => item.id == course.id);
        if (index != -1) {
          _courses[index] = updated;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(CupertinoIcons.checkmark_circle_fill, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text('${course.name} restored')),
            ],
          ),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not restore course: $e'),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
    }
  }

  Future<_CourseSuspensionNotice?> _promptCourseSuspensionNotice(
    Course course,
  ) async {
    final topicController = TextEditingController(
      text: course.suspensionTopic.isEmpty
          ? CourseService.defaultSuspensionTopic
          : course.suspensionTopic,
    );
    final messageController = TextEditingController(
      text: course.suspensionMessage.isEmpty
          ? CourseService.defaultSuspensionMessage
          : course.suspensionMessage,
    );
    try {
      return await showDialog<_CourseSuspensionNotice>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            backgroundColor: _card,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: Text(
              'Suspend ${course.name}',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
                color: _titleColor,
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Students in this course will not be able to use the app until you restore it. They will see this topic and message.',
                    style: TextStyle(fontSize: 14, color: _muted, height: 1.35),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Topic',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _titleColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: topicController,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: CourseService.defaultSuspensionTopic,
                      filled: true,
                      fillColor: _chip,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Message',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _titleColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: messageController,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: CourseService.defaultSuspensionMessage,
                      filled: true,
                      fillColor: _chip,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text('Cancel', style: TextStyle(color: _muted)),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop(
                    _CourseSuspensionNotice(
                      topic: topicController.text.trim().isEmpty
                          ? CourseService.defaultSuspensionTopic
                          : topicController.text.trim(),
                      message: messageController.text.trim().isEmpty
                          ? CourseService.defaultSuspensionMessage
                          : messageController.text.trim(),
                    ),
                  );
                },
                child: const Text(
                  'Suspend',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFF59E0B),
                  ),
                ),
              ),
            ],
          );
        },
      );
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        topicController.dispose();
        messageController.dispose();
      });
    }
  }

  Future<void> _showThemedActionSheet({
    required String title,
    String? message,
    required List<_ThemedSheetAction> actions,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 12,
            right: 12,
            bottom: MediaQuery.of(sheetContext).padding.bottom + 12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(sheetContext).size.height * 0.7,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: _card,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 10),
                        Container(
                          width: 36,
                          height: 5,
                          decoration: BoxDecoration(
                            color: _chip,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                          child: Column(
                            children: [
                              Text(
                                title,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.4,
                                  color: _titleColor,
                                ),
                              ),
                              if (message != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  message,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: _muted,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        for (var i = 0; i < actions.length; i++) ...[
                          if (i == 0)
                            Divider(height: 1, color: _chip)
                          else
                            Divider(height: 1, indent: 16, endIndent: 16, color: _chip),
                          InkWell(
                            onTap: () {
                              Navigator.pop(sheetContext);
                              actions[i].onTap();
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 16,
                              ),
                              child: Center(
                                child: Text(
                                  actions[i].label,
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                    color: actions[i].color,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Material(
                color: _card,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  onTap: () => Navigator.pop(sheetContext),
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: _titleColor,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCourseCard(Course course, {required bool showDivider}) {
    final semesterCount = course.semesters.length;
    final prefix = course.admissionPrefix.isEmpty
        ? (course.sampleAdmissionNumber.isEmpty
            ? '—'
            : course.sampleAdmissionNumber)
        : course.admissionPrefix;
    final status = course.suspended ? ' • Suspended' : '';
    return _settingsRow(
      icon: CupertinoIcons.book_fill,
      iconColor: course.suspended
          ? const Color(0xFFF59E0B)
          : const Color(0xFF6366F1),
      title: course.name,
      subtitle:
          '${course.years} ${course.years == 1 ? 'year' : 'years'} • $semesterCount semester folders • $prefix$status',
      showChevron: true,
      showDivider: showDivider,
      onTap: () => _showCourseActions(course),
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

  static const _storagePalette = [
    Color(0xFF6366F1),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFFEF4444),
    Color(0xFF0EA5E9),
    Color(0xFF8B5CF6),
    Color(0xFFEC4899),
    Color(0xFF14B8A6),
  ];

  Future<void> _loadStorage({bool refresh = false}) async {
    setState(() {
      _isLoadingStorage = true;
      _storageError = null;
    });
    try {
      final storage = await UploadService.instance.fetchDriveStorage(
        refresh: refresh,
      );
      if (!mounted) return;
      setState(() {
        _storage = storage;
        _isLoadingStorage = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _storageError = error.toString();
        _isLoadingStorage = false;
      });
    }
  }

  Future<void> _loadAccountCreationSettings() async {
    final settings = await AuthService.instance.fetchAccountCreationSettings();
    if (!mounted) return;
    setState(() {
      _allowNewAccounts = settings.allowNewAccounts;
      _restrictionMessage = settings.restrictionMessage;
    });
  }

  Future<void> _saveAccountCreationSettings({
    required bool allowNewAccounts,
    required String restrictionMessage,
  }) async {
    setState(() => _savingAccountPolicy = true);
    try {
      await AuthService.instance.saveAccountCreationSettings(
        allowNewAccounts: allowNewAccounts,
        restrictionMessage: restrictionMessage,
      );
      if (!mounted) return;
      setState(() {
        _allowNewAccounts = allowNewAccounts;
        _restrictionMessage = restrictionMessage.trim().isEmpty
            ? AuthService.defaultSignupRestrictionMessage
            : restrictionMessage.trim();
        _savingAccountPolicy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            allowNewAccounts
                ? 'New account creation is allowed'
                : 'New account creation is blocked',
          ),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingAccountPolicy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save account setting: $e'),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _onAllowNewAccountsChanged(bool allow) async {
    if (_savingAccountPolicy) return;
    if (allow) {
      await _saveAccountCreationSettings(
        allowNewAccounts: true,
        restrictionMessage: _restrictionMessage,
      );
      return;
    }

    final message = await _promptRestrictionMessage(
      initial: _restrictionMessage,
    );
    if (message == null || !mounted) return;
    await _saveAccountCreationSettings(
      allowNewAccounts: false,
      restrictionMessage: message,
    );
  }

  Future<void> _editRestrictionMessage() async {
    final message = await _promptRestrictionMessage(
      initial: _restrictionMessage,
      title: 'Restriction message',
    );
    if (message == null || !mounted) return;
    await _saveAccountCreationSettings(
      allowNewAccounts: _allowNewAccounts,
      restrictionMessage: message,
    );
  }

  Future<String?> _promptRestrictionMessage({
    required String initial,
    String title = 'Block new accounts',
    String description =
        'People who try to sign up will see this message.',
    String? hintText,
  }) async {
    final controller = TextEditingController(text: initial);
    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            backgroundColor: _card,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
                color: _titleColor,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  description,
                  style: TextStyle(fontSize: 14, color: _muted, height: 1.35),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  maxLines: 4,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: hintText ??
                        AuthService.defaultSignupRestrictionMessage,
                    filled: true,
                    fillColor: _chip,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text('Cancel', style: TextStyle(color: _muted)),
              ),
              TextButton(
                onPressed: () {
                  final value = controller.text.trim();
                  Navigator.of(dialogContext).pop(
                    value.isEmpty
                        ? AuthService.defaultSignupRestrictionMessage
                        : value,
                  );
                },
                child: const Text(
                  'Save',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6366F1),
                  ),
                ),
              ),
            ],
          );
        },
      );
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        controller.dispose();
      });
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    const units = ['KB', 'MB', 'GB', 'TB'];
    var value = bytes / 1024;
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit += 1;
    }
    final digits = value >= 10 ? 0 : 1;
    return '${value.toStringAsFixed(digits)} ${units[unit]}';
  }

  Color _storageColorForIndex(int index) =>
      _storagePalette[index % _storagePalette.length];

  Widget _buildStorageBar(List<_StorageSegment> segments) {
    final total = segments.fold<int>(0, (sum, item) => sum + item.bytes);
    if (total <= 0) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Container(
          height: 14,
          color: _isDark ? const Color(0xFF374151) : const Color(0xFFE2E8F0),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: SizedBox(
        height: 14,
        child: Row(
          children: [
            for (final segment in segments)
              if (segment.bytes > 0)
                Expanded(
                  flex: (segment.bytes / total * 10000).round().clamp(1, 10000),
                  child: ColoredBox(color: segment.color),
                ),
          ],
        ),
      ),
    );
  }

  Widget _storageLegendRow({
    required Color color,
    required String label,
    required int bytes,
    required int total,
    bool showDivider = true,
  }) {
    final percent = total <= 0 ? 0.0 : (bytes / total) * 100;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: _titleColor,
                  ),
                ),
              ),
              Text(
                '${_formatBytes(bytes)}${total > 0 ? '  ${percent.toStringAsFixed(percent >= 10 ? 0 : 1)}%' : ''}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _muted,
                ),
              ),
            ],
          ),
        ),
        if (showDivider) _hairline(indent: 36),
      ],
    );
  }

  Widget _buildStorageSection() {
    return _groupedCard([
      _settingsRow(
        icon: CupertinoIcons.chart_pie_fill,
        iconColor: const Color(0xFF6366F1),
        title: 'Storage',
        showChevron: false,
        trailing: Icon(
          _isStorageExpanded
              ? CupertinoIcons.chevron_up
              : CupertinoIcons.chevron_down,
          size: 16,
          color: _muted,
        ),
        onTap: () {
          setState(() => _isStorageExpanded = !_isStorageExpanded);
        },
      ),
      if (_isStorageExpanded) ..._storageExpandedChildren(),
    ]);
  }

  List<Widget> _storageExpandedChildren() {
    if (_isLoadingStorage && _storage == null) {
      return [
        _hairline(),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 22),
          child: Center(child: CupertinoActivityIndicator()),
        ),
      ];
    }

    if (_storageError != null && _storage == null) {
      return [
        _hairline(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            _storageError!,
            style: TextStyle(color: _muted, fontSize: 15),
          ),
        ),
        _settingsRow(
          icon: CupertinoIcons.refresh,
          iconColor: const Color(0xFF6366F1),
          title: 'Retry',
          showChevron: true,
          onTap: () => _loadStorage(refresh: true),
        ),
      ];
    }

    final storage = _storage;
    if (storage == null) {
      return [
        _hairline(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Text(
            'Drive storage is not available yet.',
            style: TextStyle(color: _muted, fontSize: 15),
          ),
        ),
      ];
    }

    final limit = storage.limitBytes;
    final barTotal = limit != null && limit > 0 ? limit : storage.usageBytes;
    final freeBytes =
        limit != null && limit > storage.usageBytes ? limit - storage.usageBytes : 0;
    final otherEdupalColor =
        _isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final otherDriveColor =
        _isDark ? const Color(0xFF6B7280) : const Color(0xFF94A3B8);
    final freeColor =
        _isDark ? const Color(0xFF374151) : const Color(0xFFE2E8F0);

    final segments = <_StorageSegment>[
      for (var i = 0; i < storage.courses.length; i++)
        _StorageSegment(
          label: storage.courses[i].name,
          bytes: storage.courses[i].bytes,
          color: _storageColorForIndex(i),
        ),
      if (storage.rootOtherBytes > 0)
        _StorageSegment(
          label: 'Other in ${storage.rootName ?? 'root'}',
          bytes: storage.rootOtherBytes,
          color: otherEdupalColor,
        ),
      if (storage.otherAccountBytes > 0)
        _StorageSegment(
          label: 'Rest of Drive',
          bytes: storage.otherAccountBytes,
          color: otherDriveColor,
        ),
      if (freeBytes > 0)
        _StorageSegment(
          label: 'Free',
          bytes: freeBytes,
          color: freeColor,
        ),
    ];

    final usedLabel = limit != null
        ? '${_formatBytes(storage.usageBytes)} of ${_formatBytes(limit)} used'
        : '${_formatBytes(storage.usageBytes)} used';
    final rootLabel = storage.rootName == null
        ? 'Root folder not configured'
        : '${storage.rootName}: ${_formatBytes(storage.rootBytes)}';

    return [
      _hairline(),
      _settingsRow(
        icon: CupertinoIcons.folder_fill,
        iconColor: const Color(0xFF6366F1),
        title: storage.accountEmail.isEmpty
            ? 'Google Drive'
            : storage.accountEmail,
        subtitle: rootLabel,
        showChevron: false,
        trailing: _isLoadingStorage
            ? const CupertinoActivityIndicator()
            : Icon(CupertinoIcons.refresh, size: 16, color: _muted),
        onTap: () => _loadStorage(refresh: true),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
        child: Text(
          usedLabel,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _titleColor,
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: _buildStorageBar(segments),
      ),
      _hairline(indent: 16),
      for (var i = 0; i < storage.courses.length; i++)
        _storageLegendRow(
          color: _storageColorForIndex(i),
          label: storage.courses[i].name,
          bytes: storage.courses[i].bytes,
          total: barTotal,
          showDivider: true,
        ),
      if (storage.rootOtherBytes > 0)
        _storageLegendRow(
          color: otherEdupalColor,
          label: 'Other in ${storage.rootName ?? 'root'}',
          bytes: storage.rootOtherBytes,
          total: barTotal,
        ),
      if (storage.otherAccountBytes > 0)
        _storageLegendRow(
          color: otherDriveColor,
          label: 'Rest of Drive',
          bytes: storage.otherAccountBytes,
          total: barTotal,
        ),
      _storageLegendRow(
        color: freeColor,
        label: limit == null ? 'Unlimited remaining' : 'Free',
        bytes: freeBytes,
        total: barTotal,
        showDivider: false,
      ),
    ];
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
          _sectionLabel('Access'),
          _groupedCard([
            _settingsRow(
              icon: CupertinoIcons.person_badge_plus,
              iconColor: const Color(0xFF10B981),
              title: 'New account creation',
              subtitle: _allowNewAccounts
                  ? 'Anyone can sign up'
                  : 'Sign up is blocked',
              showChevron: false,
              showDivider: !_allowNewAccounts,
              trailing: _savingAccountPolicy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : CupertinoSwitch(
                      value: _allowNewAccounts,
                      activeTrackColor: const Color(0xFF10B981),
                      onChanged: _onAllowNewAccountsChanged,
                    ),
            ),
            if (!_allowNewAccounts)
              _settingsRow(
                icon: CupertinoIcons.chat_bubble_text,
                iconColor: const Color(0xFFF59E0B),
                title: 'Restriction message',
                subtitle: _restrictionMessage,
                onTap: _editRestrictionMessage,
              ),
          ]),
          const SizedBox(height: 18),
          _sectionLabel('Management'),
          _groupedCard([
            _buildAddCourseButton(),
            _buildAddClientButton(),
            _buildTokenRefreshSection(),
          ]),
          const SizedBox(height: 18),
          _sectionLabel('Courses'),
          _buildAvailableCourses(),
          const SizedBox(height: 18),
          _sectionLabel('Clients'),
          _buildAvailableClients(),
          const SizedBox(height: 18),
          _buildStorageSection(),
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
                showDivider: true,
              ),
              _countRow(
                'Clients',
                '$_totalClients',
                _roleColors['client']!,
                _getRoleIcon('client'),
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
                        if (user['suspended'] == true)
                          const Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: Text(
                              'Suspended',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFEF4444),
                              ),
                            ),
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
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CupertinoSearchTextField(
            key: ValueKey(
              isUserTab
                  ? 'user-search'
                  : (_peopleTab == 2 ? 'suspended-search' : 'staff-search'),
            ),
            onChanged: (value) {
              setState(() {
                if (_peopleTab == 2) {
                  _suspendedSearchQuery = value;
                } else if (isUserTab) {
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
          if (_peopleTab != 2) ...[
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
        ],
      ),
    );
  }

  Widget _buildPeopleTabs() {
    Widget label(String text) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _titleColor,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: CupertinoSlidingSegmentedControl<int>(
        groupValue: _peopleTab,
        backgroundColor: _chip,
        thumbColor: _card,
        children: {
          0: label('Users ($_totalUsers)'),
          1: label('Staff ($_totalStaff)'),
          2: label('Suspended ($_totalSuspended)'),
        },
        onValueChanged: (value) {
          if (value == null) return;
          HapticFeedback.selectionClick();
          setState(() => _peopleTab = value);
        },
      ),
    );
  }

  Widget _buildPeopleSection() {
    final isSuspendedTab = _peopleTab == 2;
    final isUserTab = _peopleTab == 0;
    final items = isSuspendedTab
        ? _filteredSuspended
        : (isUserTab ? _filteredUsers : _filteredStaff);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFilterHeader(
          isUserTab: isUserTab,
          searchHint: isSuspendedTab
              ? 'Search suspended accounts'
              : (isUserTab ? 'Search users' : 'Search staff'),
          roles: isUserTab ? _userRoles : _staffRoles,
        ),
        if (items.isEmpty)
          SizedBox(
            height: 220,
            child: _buildEmptyState(
              isSuspendedTab
                  ? 'No suspended accounts'
                  : (isUserTab ? 'No users found' : 'No staff found'),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            child: _groupedCard([
              for (var i = 0; i < items.length; i++)
                _buildUserCard(
                  items[i],
                  showDivider: i < items.length - 1,
                ),
            ]),
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
          : CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverAppBar(
                  pinned: true,
                  floating: false,
                  snap: false,
                  toolbarHeight: 52,
                  automaticallyImplyLeading: true,
                  centerTitle: false,
                  backgroundColor: _bg,
                  foregroundColor: _titleColor,
                  surfaceTintColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  forceElevated: false,
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
                        _loadStorage(refresh: true);
                      },
                      child: const Icon(
                        CupertinoIcons.refresh,
                        color: Color(0xFF6366F1),
                      ),
                    ),
                  ],
                ),
                SliverToBoxAdapter(
                  child: ColoredBox(
                    color: _bg,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildStatisticsSection(),
                        _buildPeopleTabs(),
                        _buildPeopleSection(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _CourseSuspensionNotice {
  const _CourseSuspensionNotice({
    required this.topic,
    required this.message,
  });

  final String topic;
  final String message;
}

class _ThemedSheetAction {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ThemedSheetAction({
    required this.label,
    required this.color,
    required this.onTap,
  });
}

class _StorageSegment {
  final String label;
  final int bytes;
  final Color color;

  const _StorageSegment({
    required this.label,
    required this.bytes,
    required this.color,
  });
}
