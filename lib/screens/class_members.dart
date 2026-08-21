import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/course_service.dart';

class ClassMembersScreen extends StatefulWidget {
  const ClassMembersScreen({super.key});

  @override
  State<ClassMembersScreen> createState() => _ClassMembersScreenState();
}

class _ClassMembersScreenState extends State<ClassMembersScreen> {
  final _firestore = FirebaseFirestore.instance;

  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _filteredMembers = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _roleFilter = 'all';
  String? _currentUserId;
  String? _currentRole;
  String? _registrationNumber;
  String? _classLabel;

  static const _memberRoles = {
    'student',
    'class_rep',
    'assistant_class_rep',
  };

  static const _roleColors = {
    'class_rep': Color(0xFFF59E0B),
    'assistant_class_rep': Color(0xFF06B6D4),
    'student': Color(0xFF10B981),
  };

  bool get _isClassRep => (_currentRole ?? '').toLowerCase() == 'class_rep';

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
      _currentRole = (myData['role'] as String?) ?? 'student';
      _registrationNumber =
          (myData['registration_number'] as String?) ?? '';

      final prefix = Course.admissionPrefixFromSample(_registrationNumber ?? '');
      final suffix = Course.classSuffixFromSample(_registrationNumber ?? '');
      _classLabel = prefix.isNotEmpty && suffix.isNotEmpty
          ? '$prefix / $suffix'
          : null;

      if (prefix.isEmpty || suffix.isEmpty) {
        if (!mounted) return;
        setState(() {
          _members = [];
          _filteredMembers = [];
          _isLoading = false;
        });
        return;
      }

      final snapshot = await _firestore.collection('profiles').get();
      final members = snapshot.docs.map((doc) {
        final data = Map<String, dynamic>.from(doc.data());
        data['id'] = doc.id;
        data['role'] = (data['role'] as String?) ?? 'student';
        data['full_name'] = data['full_name'] ?? 'Unknown user';
        data['username'] = data['username'] ?? '';
        data['email'] = data['email'] ?? '';
        data['registration_number'] = data['registration_number'] ?? '';
        data['avatar_url'] = data['avatar_url'] ?? '';
        return data;
      }).where((profile) {
        final role = profile['role'].toString().toLowerCase();
        if (!_memberRoles.contains(role)) return false;
        return Course.isSameClass(
          _registrationNumber ?? '',
          profile['registration_number'].toString(),
        );
      }).toList()
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
          content: Text('Error loading class members: $e'),
          backgroundColor: const Color(0xFFEF4444),
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
          member['registration_number'].toString().toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _updateRole(Map<String, dynamic> member, String newRole) async {
    if (!_isClassRep) return;
    if (member['id'] == _currentUserId) return;

    final current = member['role'].toString();
    final allowed = (current == 'student' && newRole == 'assistant_class_rep') ||
        (current == 'assistant_class_rep' && newRole == 'student');
    if (!allowed) return;

    try {
      await _firestore.collection('profiles').doc(member['id']).update({
        'role': newRole,
        'updated_at': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newRole == 'assistant_class_rep'
                ? '${member['full_name']} is now Assistant Class Rep'
                : '${member['full_name']} is now a student',
          ),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _loadMembers();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update role: $e'),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
    }
  }

  void _showRoleActions(Map<String, dynamic> member) {
    final role = member['role'].toString();
    final isSelf = member['id'] == _currentUserId;
    final canChange = _isClassRep &&
        !isSelf &&
        (role == 'student' || role == 'assistant_class_rep');

    showModalBottomSheet(
      context: context,
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
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                member['full_name'].toString(),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                member['registration_number'].toString(),
                style: const TextStyle(color: Color(0xFF6B7280)),
              ),
              const SizedBox(height: 8),
              _roleChip(role),
              const SizedBox(height: 20),
              if (!canChange)
                Text(
                  isSelf
                      ? 'You cannot change your own role.'
                      : !_isClassRep
                          ? 'Only the class rep can change member roles.'
                          : 'This member’s role cannot be changed here.',
                  style: const TextStyle(color: Color(0xFF6B7280)),
                )
              else if (role == 'student')
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.group_outlined,
                    color: Color(0xFF06B6D4),
                  ),
                  title: const Text('Make Assistant Class Rep'),
                  onTap: () {
                    Navigator.pop(context);
                    _updateRole(member, 'assistant_class_rep');
                  },
                )
              else
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.person_rounded,
                    color: Color(0xFF10B981),
                  ),
                  title: const Text('Change back to Student'),
                  onTap: () {
                    Navigator.pop(context);
                    _updateRole(member, 'student');
                  },
                ),
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
        return Icons.people_rounded;
      case 'assistant_class_rep':
        return Icons.group_outlined;
      default:
        return Icons.person_rounded;
    }
  }

  Widget _roleChip(String role) {
    final color = _roleColors[role] ?? const Color(0xFF6366F1);
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
      backgroundColor: const Color(0xFF6366F1),
      child: Text(
        _initials(name),
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    final selected = _roleFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) {
          setState(() {
            _roleFilter = value;
            _applyFilters();
          });
        },
        backgroundColor: Colors.white,
        selectedColor: const Color(0xFF6366F1).withValues(alpha: 0.2),
        labelStyle: TextStyle(
          color: selected ? const Color(0xFF6366F1) : const Color(0xFF6B7280),
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        ),
        side: BorderSide(
          color: selected ? const Color(0xFF6366F1) : const Color(0xFFE5E7EB),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final students =
        _members.where((m) => m['role'] == 'student').length;
    final assistants =
        _members.where((m) => m['role'] == 'assistant_class_rep').length;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Class Members',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadMembers,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
              ),
            )
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _classLabel == null
                            ? 'Add a registration number like EB24/56171/21 to identify your class.'
                            : 'Class $_classLabel · ${_members.length} member${_members.length == 1 ? '' : 's'}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$students student${students == 1 ? '' : 's'} · $assistants assistant${assistants == 1 ? '' : 's'}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF9CA3AF),
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
                        decoration: InputDecoration(
                          hintText: 'Search members...',
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
                            _filterChip('All', 'all'),
                            _filterChip('Students', 'student'),
                            _filterChip('Class Reps', 'class_rep'),
                            _filterChip(
                              'Assistants',
                              'assistant_class_rep',
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
                              _classLabel == null
                                  ? 'Your registration number needs a class year after the last /, for example /21.'
                                  : 'No class members found.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredMembers.length,
                          itemBuilder: (context, index) {
                            final member = _filteredMembers[index];
                            final role = member['role'].toString();
                            final isSelf = member['id'] == _currentUserId;
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
                                leading: _avatar(member),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        member['full_name'].toString(),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
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
                                          color: const Color(0xFF6366F1)
                                              .withValues(alpha: 0.1),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: const Text(
                                          'YOU',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF6366F1),
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
                                      member['registration_number'].toString(),
                                      style: const TextStyle(
                                        color: Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    _roleChip(role),
                                  ],
                                ),
                                trailing: const Icon(Icons.chevron_right_rounded),
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
