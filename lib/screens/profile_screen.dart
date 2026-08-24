import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../services/download_service.dart';
import '../services/theme_controller.dart';
import '../ui/adaptive_layout.dart';
import 'class_members.dart';
import 'course_members.dart';
import 'downloads_screen.dart';
import 'edit_profile.dart';
import 'help_and_support.dart';
import 'no_internet_screen.dart';
import 'notifications_screen.dart';
import 'system_admin_dashboard.dart';
import 'users_feedback.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _firestore = FirebaseFirestore.instance;
  String? _fullName;
  String? _email;
  String? _username;
  String? _registrationNumber;
  String? _avatarUrl;
  String? _role;
  bool _isLoading = true;
  int _downloadsStorageBytes = 0;
  int _downloadedFileCount = 0;
  int _uniqueSubjectsCount = 0;
  int _thisWeekDownloadCount = 0;
  int _pdfCount = 0;

  bool get _isAdmin {
    final role = (_role ?? '').toLowerCase();
    return role == 'admin';
  }

  bool get _isSystemAdmin {
    final email = _email ?? AuthService.instance.currentUser?.email;
    if (SystemAdminDashboard.isAllowedEmail(email)) return true;
    return SystemAdminDashboard.isSystemAdminRole(_role);
  }

  bool get _canOpenClassMembers {
    final role = (_role ?? '').toLowerCase();
    return role == 'class_rep' || role == 'assistant_class_rep';
  }

  @override
  void initState() {
    super.initState();
    _loadUserData();
    DownloadService.listVersion.addListener(_loadStorageUsage);
    _loadStorageUsage();
  }

  @override
  void dispose() {
    DownloadService.listVersion.removeListener(_loadStorageUsage);
    super.dispose();
  }

  Future<void> _loadStorageUsage() async {
    final downloads = await DownloadService.getDownloads();
    final bytes = downloads.fold<int>(0, (sum, item) => sum + item.size);
    final subjects = downloads
        .map((item) => item.subject.trim())
        .where((subject) => subject.isNotEmpty)
        .toSet()
        .length;
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    final thisWeek = downloads.where((item) {
      final date = DateTime.tryParse(item.date);
      return date != null && date.isAfter(weekAgo);
    }).length;
    final pdfs =
        downloads.where((item) => item.type.toUpperCase() == 'PDF').length;
    if (!mounted) return;
    if (bytes == _downloadsStorageBytes &&
        downloads.length == _downloadedFileCount &&
        subjects == _uniqueSubjectsCount &&
        thisWeek == _thisWeekDownloadCount &&
        pdfs == _pdfCount) {
      return;
    }
    setState(() {
      _downloadsStorageBytes = bytes;
      _downloadedFileCount = downloads.length;
      _uniqueSubjectsCount = subjects;
      _thisWeekDownloadCount = thisWeek;
      _pdfCount = pdfs;
    });
  }

  Future<void> _loadUserData() async {
    try {
      final user = AuthService.instance.currentUser;
      if (user != null) {
        final profileDoc =
            await _firestore.collection('profiles').doc(user.uid).get();

        final profileData = profileDoc.data() ?? {};

        setState(() {
          _email = user.email;
          _fullName = profileData['full_name'] as String?;
          _username = profileData['username'] as String?;
          _registrationNumber = profileData['registration_number'] as String?;
          _role = profileData['role'] as String?;
          _avatarUrl = profileData['avatar_url'] as String?;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading profile: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  Future<void> _refreshProfile() async {
    if (!await NoInternetScreen.ensureOnline(context)) return;
    await _loadUserData();
  }

  Future<void> _openOnlinePage(Widget page) async {
    if (!await NoInternetScreen.ensureOnline(context)) return;
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  Future<void> _openEditProfile() async {
    if (!await NoInternetScreen.ensureOnline(context)) return;
    if (!mounted) return;
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => const EditProfileScreen(),
      ),
    );
    if (result == true) {
      _loadUserData();
    }
  }

  Future<void> _signOut() async {
    final shouldSignOut = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (shouldSignOut == true) {
      try {
        await AuthService.instance.signOut();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error signing out: $e'),
              backgroundColor: const Color(0xFFEF4444),
            ),
          );
        }
      }
    }
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
    final separator =
        isDark ? const Color(0xFF374151) : const Color(0xFFF1F5F9);
    final chevron =
        isDark ? const Color(0xFF6B7280) : const Color(0xFF9CA3AF);
    const accent = Color(0xFF6366F1);
    final pagePad = AdaptiveLayout.pagePadding(context);
    final bottomPad = AdaptiveLayout.bottomClearance(context);
    final tablet = AdaptiveLayout.isTablet(context);

    return Scaffold(
      backgroundColor: background,
      body: _isLoading
          ? Center(
              child: CupertinoActivityIndicator(
                color: isDark ? const Color(0xFFF9FAFB) : const Color(0xFF6B7280),
              ),
            )
          : RefreshIndicator(
              color: accent,
              backgroundColor: card,
              onRefresh: _refreshProfile,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: [
                  compactSliverAppBar(
                    backgroundColor: background,
                    foregroundColor: primaryText,
                    title: Text(
                      'Profile',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: tablet ? 22 : 20,
                      ),
                    ),
                    actions: [
                      CupertinoButton(
                        padding: const EdgeInsets.only(right: 8),
                        onPressed: _openEditProfile,
                        child: const Text(
                          'Edit',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF6366F1),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SliverPadding(
                    padding: pagePad.copyWith(top: 4, bottom: bottomPad),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        _profileHero(
                          card: card,
                          primaryText: primaryText,
                          secondaryText: secondaryText,
                          isDark: isDark,
                        ),
                        const SizedBox(height: 16),
                        _sectionLabel('Library', secondaryText),
                        _groupedCard(
                          color: card,
                          children: [
                            _statsStrip(
                              primaryText: primaryText,
                              secondaryText: secondaryText,
                              separator: separator,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _sectionLabel('Preferences', secondaryText),
                        _groupedCard(
                          color: card,
                          children: [
                            _settingsRow(
                              title: 'Notifications',
                              icon: CupertinoIcons.bell_fill,
                              iconColor: const Color(0xFFF59E0B),
                              chevron: chevron,
                              primaryText: primaryText,
                              showDivider: true,
                              separator: separator,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                _openOnlinePage(const NotificationsScreen());
                              },
                            ),
                            _appearanceRow(
                              primaryText: primaryText,
                              secondaryText: secondaryText,
                              isDark: isDark,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _sectionLabel('Storage', secondaryText),
                        _groupedCard(
                          color: card,
                          children: [
                            _settingsRow(
                              title: 'Storage Usage',
                              icon: CupertinoIcons.folder_fill,
                              iconColor: const Color(0xFF10B981),
                              chevron: chevron,
                              primaryText: primaryText,
                              trailing: DownloadService.formatFileSize(
                                _downloadsStorageBytes,
                              ),
                              trailingColor: secondaryText,
                              onTap: _showStorageUsage,
                            ),
                          ],
                        ),
                        if (_hasAccountTools) ...[
                          const SizedBox(height: 16),
                          _sectionLabel('Account tools', secondaryText),
                          _groupedCard(
                            color: card,
                            children: [
                              if (_isAdmin)
                                _settingsRow(
                                  title: 'Course Members',
                                  subtitle: 'Admin only',
                                  icon: CupertinoIcons.book_fill,
                                  iconColor: const Color(0xFF0EA5E9),
                                  chevron: chevron,
                                  primaryText: primaryText,
                                  secondaryText: secondaryText,
                                  showDivider: _canOpenClassMembers ||
                                      _isSystemAdmin,
                                  separator: separator,
                                  onTap: () {
                                    _openOnlinePage(const CourseMembersScreen());
                                  },
                                ),
                              if (_canOpenClassMembers)
                                _settingsRow(
                                  title: 'Class Members',
                                  subtitle: 'View and manage your class',
                                  icon: CupertinoIcons.person_2_fill,
                                  iconColor: const Color(0xFFF59E0B),
                                  chevron: chevron,
                                  primaryText: primaryText,
                                  secondaryText: secondaryText,
                                  showDivider: _isSystemAdmin,
                                  separator: separator,
                                  onTap: () {
                                    _openOnlinePage(const ClassMembersScreen());
                                  },
                                ),
                              if (_isSystemAdmin)
                                _settingsRow(
                                  title: 'User Feedback',
                                  subtitle: 'Messages from Help & Support',
                                  icon: CupertinoIcons.chat_bubble_2_fill,
                                  iconColor: const Color(0xFF10B981),
                                  chevron: chevron,
                                  primaryText: primaryText,
                                  secondaryText: secondaryText,
                                  showDivider: true,
                                  separator: separator,
                                  onTap: () {
                                    _openOnlinePage(const UsersFeedbackScreen());
                                  },
                                ),
                              if (_isSystemAdmin)
                                _settingsRow(
                                  title: 'System Admin',
                                  subtitle: 'Users and staff',
                                  icon: CupertinoIcons.shield_lefthalf_fill,
                                  iconColor: const Color(0xFF6366F1),
                                  chevron: chevron,
                                  primaryText: primaryText,
                                  secondaryText: secondaryText,
                                  onTap: () {
                                    _openOnlinePage(const SystemAdminDashboard());
                                  },
                                ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 16),
                        _sectionLabel('Support', secondaryText),
                        _groupedCard(
                          color: card,
                          children: [
                            _settingsRow(
                              title: 'Help & Support',
                              icon: CupertinoIcons.question_circle_fill,
                              iconColor: const Color(0xFF6366F1),
                              chevron: chevron,
                              primaryText: primaryText,
                              showDivider: true,
                              separator: separator,
                              onTap: () {
                                _openOnlinePage(const HelpAndSupportScreen());
                              },
                            ),
                            _settingsRow(
                              title: 'About',
                              icon: CupertinoIcons.info_circle_fill,
                              iconColor: const Color(0xFF6B7280),
                              chevron: chevron,
                              primaryText: primaryText,
                              onTap: _showAboutDialog,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _groupedCard(
                          color: card,
                          children: [
                            _settingsRow(
                              title: 'Sign Out',
                              icon: CupertinoIcons.square_arrow_right,
                              iconColor: const Color(0xFFEF4444),
                              chevron: chevron,
                              primaryText: const Color(0xFFEF4444),
                              showChevron: false,
                              onTap: _signOut,
                            ),
                          ],
                        ),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  bool get _hasAccountTools =>
      _isAdmin || _canOpenClassMembers || _isSystemAdmin;

  Widget _profileHero({
    required Color card,
    required Color primaryText,
    required Color secondaryText,
    required bool isDark,
  }) {
    final tablet = AdaptiveLayout.isTablet(context);
    final avatarRadius = tablet ? 42.0 : 32.0;
    final identity = Column(
      crossAxisAlignment:
          tablet ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        Text(
          _fullName ?? 'User Name',
          textAlign: tablet ? TextAlign.start : TextAlign.center,
          style: TextStyle(
            fontSize: tablet ? 26 : 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.6,
            color: primaryText,
          ),
        ),
        if (_username != null && _username!.trim().isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            '@$_username',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: secondaryText,
            ),
          ),
        ],
        const SizedBox(height: 2),
        Text(
          _email ?? 'email@example.com',
          style: TextStyle(
            fontSize: 14,
            color: secondaryText,
          ),
        ),
        if (_registrationNumber != null || _role != null) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment:
                tablet ? WrapAlignment.start : WrapAlignment.center,
            children: [
              if (_registrationNumber != null)
                _pill(
                  icon: CupertinoIcons.tag_fill,
                  label: _registrationNumber!,
                  color: const Color(0xFF6366F1),
                  isDark: isDark,
                ),
              if (_role != null)
                _pill(
                  icon: _getRoleIcon(_role!),
                  label: _formatRole(_role!),
                  color: _getRoleColor(_role!),
                  isDark: isDark,
                ),
            ],
          ),
        ],
      ],
    );

    final avatar = Container(
      padding: const EdgeInsets.all(3),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: card,
        ),
        child: _avatarUrl != null && _avatarUrl!.isNotEmpty
            ? CircleAvatar(
                radius: avatarRadius,
                backgroundImage: NetworkImage(_avatarUrl!),
                backgroundColor:
                    isDark ? const Color(0xFF374151) : const Color(0xFFF1F5F9),
              )
            : CircleAvatar(
                radius: avatarRadius,
                backgroundColor: const Color(0xFF6366F1),
                child: Text(
                  _getInitials(_fullName ?? 'User'),
                  style: TextStyle(
                    fontSize: tablet ? 26 : 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
      ),
    );

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        tablet ? 24 : 16,
        tablet ? 20 : 14,
        tablet ? 24 : 16,
        tablet ? 20 : 14,
      ),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
        ],
      ),
      child: tablet
          ? Row(
              children: [
                avatar,
                const SizedBox(width: 20),
                Expanded(child: identity),
              ],
            )
          : Column(
              children: [
                avatar,
                const SizedBox(height: 12),
                identity,
              ],
            ),
    );
  }

  Widget _pill({
    required IconData icon,
    required String label,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.18 : 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.4,
          color: color,
        ),
      ),
    );
  }

  Widget _groupedCard({
    required Color color,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          if (Theme.of(context).brightness != Brightness.dark)
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(children: children),
      ),
    );
  }

  Widget _statsStrip({
    required Color primaryText,
    required Color secondaryText,
    required Color separator,
  }) {
    final cells = [
      _statCell('$_downloadedFileCount', 'Downloads', primaryText, secondaryText),
      _statCell('$_uniqueSubjectsCount', 'Subjects', primaryText, secondaryText),
      _statCell('$_pdfCount', 'PDFs', primaryText, secondaryText),
      _statCell('$_thisWeekDownloadCount', 'This week', primaryText, secondaryText),
    ];

    Widget row(List<Widget> items) {
      return IntrinsicHeight(
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0)
                VerticalDivider(width: 1, thickness: 0.5, color: separator),
              items[i],
            ],
          ],
        ),
      );
    }

    final tablet = AdaptiveLayout.isTablet(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: tablet
          ? row(cells)
          : Column(
              children: [
                row(cells.sublist(0, 2)),
                Divider(height: 1, thickness: 0.5, color: separator),
                row(cells.sublist(2)),
              ],
            ),
    );
  }

  Widget _statCell(
    String value,
    String label,
    Color primaryText,
    Color secondaryText,
  ) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
              color: primaryText,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: secondaryText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _appearanceRow({
    required Color primaryText,
    required Color secondaryText,
    required bool isDark,
  }) {
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) {
        final mode = ThemeController.instance.mode;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _iconTile(
                    CupertinoIcons.moon_stars_fill,
                    const Color(0xFF8B5CF6),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Appearance',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w400,
                            color: primaryText,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          mode == ThemeMode.system
                              ? 'Matches your phone'
                              : 'Using ${ThemeController.labelFor(mode).toLowerCase()} mode',
                          style: TextStyle(
                            fontSize: 13,
                            color: secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _themeOption(
                    mode: ThemeMode.system,
                    selected: mode,
                    label: 'Auto',
                    icon: CupertinoIcons.circle_lefthalf_fill,
                    isDark: isDark,
                    primaryText: primaryText,
                    secondaryText: secondaryText,
                  ),
                  const SizedBox(width: 8),
                  _themeOption(
                    mode: ThemeMode.light,
                    selected: mode,
                    label: 'Light',
                    icon: CupertinoIcons.sun_max_fill,
                    isDark: isDark,
                    primaryText: primaryText,
                    secondaryText: secondaryText,
                  ),
                  const SizedBox(width: 8),
                  _themeOption(
                    mode: ThemeMode.dark,
                    selected: mode,
                    label: 'Dark',
                    icon: CupertinoIcons.moon_fill,
                    isDark: isDark,
                    primaryText: primaryText,
                    secondaryText: secondaryText,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _themeOption({
    required ThemeMode mode,
    required ThemeMode selected,
    required String label,
    required IconData icon,
    required bool isDark,
    required Color primaryText,
    required Color secondaryText,
  }) {
    final isSelected = mode == selected;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          ThemeController.instance.setMode(mode);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF6366F1).withOpacity(isDark ? 0.22 : 0.12)
                : (isDark ? const Color(0xFF374151) : const Color(0xFFF1F5F9)),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF6366F1)
                  : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected ? const Color(0xFF6366F1) : secondaryText,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? const Color(0xFF6366F1) : primaryText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _settingsRow({
    required String title,
    required IconData icon,
    required Color iconColor,
    required Color chevron,
    required Color primaryText,
    Color? secondaryText,
    String? subtitle,
    String? trailing,
    Color? trailingColor,
    bool showDivider = false,
    Color? separator,
    bool showChevron = true,
    VoidCallback? onTap,
  }) {
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              child: Row(
                children: [
                  _iconTile(icon, iconColor),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w400,
                            color: primaryText,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 13,
                              color: secondaryText,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Text(
                        trailing,
                        style: TextStyle(
                          fontSize: 16,
                          color: trailingColor,
                        ),
                      ),
                    ),
                  if (showChevron)
                    Icon(
                      CupertinoIcons.chevron_forward,
                      size: 16,
                      color: chevron,
                    ),
                ],
              ),
            ),
          ),
        ),
        if (showDivider)
          Padding(
            padding: const EdgeInsets.only(left: 68),
            child: Divider(
              height: 0.5,
              thickness: 0.5,
              color: separator,
            ),
          ),
      ],
    );
  }

  Widget _iconTile(IconData icon, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.2 : 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: 18),
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.isEmpty) return 'U';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[parts.length - 1][0]}'.toUpperCase();
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
        return const Color(0xFF0EA5E9);
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

  Future<void> _showStorageUsage() async {
    await _loadStorageUsage();
    if (!mounted) return;

    final sizeLabel = DownloadService.formatFileSize(_downloadsStorageBytes);
    final fileLabel = _downloadedFileCount == 1
        ? '1 downloaded file'
        : '$_downloadedFileCount downloaded files';

    await showCupertinoDialog<void>(
      context: context,
      builder: (context) {
        return CupertinoAlertDialog(
          title: const Text('Storage Usage'),
          content: Text('This app is using $sizeLabel for $fileLabel.'),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            CupertinoDialogAction(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const DownloadsScreen(),
                  ),
                ).then((_) => _loadStorageUsage());
              },
              child: const Text('View Downloads'),
            ),
          ],
        );
      },
    );
  }

  void _showAboutDialog() {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Edupal'),
        content: const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'Version 4.36\n\nYour Academic Companion. Edupal helps you organize and access your study materials seamlessly. Created and maintained by David Muigai.',
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
