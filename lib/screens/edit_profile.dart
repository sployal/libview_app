import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/media_service.dart';
import '../ui/adaptive_layout.dart';
import 'system_admin_dashboard.dart';
import 'users_feedback.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  static const _accent = Color(0xFF6366F1);
  static const _danger = Color(0xFFEF4444);
  static const _success = Color(0xFF10B981);

  final _firestore = FirebaseFirestore.instance;
  final _formKey = GlobalKey<FormState>();

  final _fullNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _avatarUrlController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  String? _currentEmail;
  String? _currentRole;
  String? _admissionNumber;
  String? _avatarPublicId;
  Uint8List? _pendingAvatarBytes;
  String? _pendingAvatarFileName;
  String? _pendingAvatarMime;
  bool _removeAvatar = false;

  String _originalFullName = '';
  String _originalUsername = '';

  bool get _isSystemAdmin {
    return SystemAdminDashboard.isSystemAdminRole(_currentRole);
  }

  bool get _hasUnsavedChanges {
    if (_fullNameController.text.trim() != _originalFullName) return true;
    if (_usernameController.text.trim() != _originalUsername) return true;
    if (_pendingAvatarBytes != null) return true;
    if (_removeAvatar) return true;
    return false;
  }

  @override
  void initState() {
    super.initState();
    _fullNameController.addListener(_onFieldChanged);
    _usernameController.addListener(_onFieldChanged);
    _loadUserData();
  }

  @override
  void dispose() {
    _fullNameController.removeListener(_onFieldChanged);
    _usernameController.removeListener(_onFieldChanged);
    _fullNameController.dispose();
    _usernameController.dispose();
    _avatarUrlController.dispose();
    super.dispose();
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadUserData() async {
    try {
      final user = AuthService.instance.currentUser;
      if (user != null) {
        final profileDoc =
            await _firestore.collection('profiles').doc(user.uid).get();
        final profileData = profileDoc.data() ?? {};
        final fullName = (profileData['full_name'] as String? ?? '').trim();
        final username = (profileData['username'] as String? ?? '').trim();

        setState(() {
          _currentEmail = user.email;
          _currentRole = profileData['role'] as String?;
          _admissionNumber = profileData['admission_number'] as String?;
          _originalFullName = fullName;
          _originalUsername = username;
          _fullNameController.text = fullName;
          _usernameController.text = username;
          _avatarUrlController.text =
              profileData['avatar_url'] as String? ?? '';
          _avatarPublicId = profileData['avatar_public_id'] as String?;
          _pendingAvatarBytes = null;
          _pendingAvatarFileName = null;
          _pendingAvatarMime = null;
          _removeAvatar = false;
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
            backgroundColor: _danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final user = AuthService.instance.currentUser;
      if (user != null) {
        String avatarUrl = _avatarUrlController.text.trim();
        String? avatarPublicId = _avatarPublicId;
        final previousPublicId = _avatarPublicId;

        if (_pendingAvatarBytes != null && _pendingAvatarBytes!.isNotEmpty) {
          final uploaded = await MediaService.instance.uploadImage(
            bytes: _pendingAvatarBytes!,
            fileName: _pendingAvatarFileName ?? 'profile.jpg',
            mimeType: _pendingAvatarMime ?? 'image/jpeg',
            folder: MediaService.folderProfiles,
          );
          avatarUrl = uploaded.url;
          avatarPublicId = uploaded.publicId;

          if (previousPublicId != null &&
              previousPublicId.isNotEmpty &&
              previousPublicId != uploaded.publicId) {
            try {
              await MediaService.instance.deleteImage(previousPublicId);
            } catch (_) {}
          }
        } else if (_removeAvatar) {
          if (previousPublicId != null && previousPublicId.isNotEmpty) {
            try {
              await MediaService.instance.deleteImage(previousPublicId);
            } catch (_) {}
          }
          avatarUrl = '';
          avatarPublicId = null;
        }

        final username = _usernameController.text.trim();
        final resolvedAvatarUrl = avatarUrl.trim();
        await _firestore.collection('profiles').doc(user.uid).set({
          'full_name': _fullNameController.text.trim(),
          'username': username.isEmpty ? FieldValue.delete() : username,
          'avatar_url': resolvedAvatarUrl.isEmpty
              ? FieldValue.delete()
              : resolvedAvatarUrl,
          'avatar_public_id':
              (resolvedAvatarUrl.isEmpty ||
                      avatarPublicId == null ||
                      avatarPublicId.isEmpty)
                  ? FieldValue.delete()
                  : avatarPublicId,
          'updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profile updated successfully!'),
              backgroundColor: _success,
              behavior: SnackBarBehavior.floating,
            ),
          );
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating profile: $e'),
            backgroundColor: _danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _pickAvatar() async {
    if (_isSaving) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
      dialogTitle: 'Choose a profile photo',
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) return;

    const maxBytes = 8 * 1024 * 1024;
    if (bytes.length > maxBytes) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please choose an image smaller than 8 MB.'),
          backgroundColor: _danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _pendingAvatarBytes = bytes;
      _pendingAvatarFileName = file.name;
      _pendingAvatarMime = MediaService.mimeFromName(file.name, file.extension);
      _removeAvatar = false;
    });
  }

  void _markAvatarForRemoval() {
    if (_isSaving) return;
    setState(() {
      _pendingAvatarBytes = null;
      _pendingAvatarFileName = null;
      _pendingAvatarMime = null;
      _removeAvatar = true;
    });
  }

  Future<bool> _confirmDiscardIfNeeded() async {
    if (!_hasUnsavedChanges) return true;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = isDark ? const Color(0xFF1F2937) : Colors.white;
    final titleColor =
        isDark ? const Color(0xFFF9FAFB) : const Color(0xFF111827);
    final muted = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);

    final shouldPop = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          'Discard Changes?',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: titleColor,
          ),
        ),
        content: Text(
          'You have unsaved changes. Are you sure you want to leave?',
          style: TextStyle(
            fontSize: 15,
            color: muted,
            height: 1.35,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF8E8E93)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Discard',
              style: TextStyle(
                color: _danger,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    return shouldPop ?? false;
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

    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _confirmDiscardIfNeeded();
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: background,
        body: _isLoading
            ? Center(
                child: CupertinoActivityIndicator(
                  color: isDark
                      ? const Color(0xFFF9FAFB)
                      : const Color(0xFF6B7280),
                ),
              )
            : CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  compactSliverAppBar(
                    backgroundColor: background,
                    foregroundColor: primaryText,
                    automaticallyImplyLeading: false,
                    leading: IconButton(
                      icon: Icon(CupertinoIcons.back, color: primaryText),
                      onPressed: () => Navigator.maybePop(context),
                    ),
                    title: Text(
                      'Edit Profile',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: tablet ? 22 : 20,
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: _isSaving || !_hasUnsavedChanges
                            ? null
                            : _saveProfile,
                        child: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor:
                                      AlwaysStoppedAnimation<Color>(_accent),
                                ),
                              )
                            : Text(
                                'Save',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: _hasUnsavedChanges
                                      ? _accent
                                      : secondaryText,
                                ),
                              ),
                      ),
                    ],
                  ),
                  SliverPadding(
                    padding: pagePad.copyWith(
                      top: 8,
                      bottom: 40 + MediaQuery.viewPaddingOf(context).bottom,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Center(
                              child: Column(
                                children: [
                                  GestureDetector(
                                    onTap: _isSaving ? null : _pickAvatar,
                                    child: Stack(
                                      children: [
                                        _avatarPreview(
                                          card: card,
                                          divider: divider,
                                        ),
                                        Positioned(
                                          right: 0,
                                          bottom: 0,
                                          child: Container(
                                            width: 32,
                                            height: 32,
                                            decoration: BoxDecoration(
                                              color: _accent,
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: background,
                                                width: 3,
                                              ),
                                            ),
                                            child: const Icon(
                                              CupertinoIcons.camera_fill,
                                              color: Colors.white,
                                              size: 14,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Profile Picture',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: primaryText,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  TextButton(
                                    onPressed:
                                        _isSaving ? null : _pickAvatar,
                                    child: const Text(
                                      'Choose photo',
                                      style: TextStyle(
                                        color: _accent,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  if (_pendingAvatarBytes != null ||
                                      (!_removeAvatar &&
                                          _avatarUrlController
                                              .text.isNotEmpty))
                                    TextButton.icon(
                                      onPressed: _isSaving
                                          ? null
                                          : _markAvatarForRemoval,
                                      icon: const Icon(
                                        CupertinoIcons.trash,
                                        size: 16,
                                        color: _danger,
                                      ),
                                      label: const Text(
                                        'Remove profile picture',
                                        style: TextStyle(
                                          color: _danger,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 28),
                            _sectionLabel('Personal Information', secondaryText),
                            const SizedBox(height: 12),
                            _themedField(
                              controller: _fullNameController,
                              label: 'Full Name',
                              icon: CupertinoIcons.person_fill,
                              hint: 'Enter your full name',
                              primaryText: primaryText,
                              secondaryText: secondaryText,
                              card: card,
                              divider: divider,
                              enabled: !_isSaving,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter your full name';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            _themedField(
                              controller: _usernameController,
                              label: 'Username (optional)',
                              icon: CupertinoIcons.at,
                              hint: 'Enter a username if you want one',
                              primaryText: primaryText,
                              secondaryText: secondaryText,
                              card: card,
                              divider: divider,
                              enabled: !_isSaving,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return null;
                                }
                                if (value.contains(' ')) {
                                  return 'Username cannot contain spaces';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 24),
                            _sectionLabel('Account Information', secondaryText),
                            const SizedBox(height: 12),
                            _buildReadOnlyField(
                              label: 'Admission Number',
                              value: (_admissionNumber == null ||
                                      _admissionNumber!.trim().isEmpty)
                                  ? 'Not available'
                                  : _admissionNumber!,
                              icon: CupertinoIcons.creditcard_fill,
                              primaryText: primaryText,
                              secondaryText: secondaryText,
                              card: card,
                              divider: divider,
                            ),
                            const SizedBox(height: 12),
                            _buildReadOnlyField(
                              label: 'Email',
                              value: _currentEmail ?? 'Not available',
                              icon: CupertinoIcons.mail_solid,
                              primaryText: primaryText,
                              secondaryText: secondaryText,
                              card: card,
                              divider: divider,
                            ),
                            const SizedBox(height: 12),
                            _buildReadOnlyField(
                              label: 'Role',
                              value: _formatRole(_currentRole ?? 'student'),
                              icon: _getRoleIcon(_currentRole ?? 'student'),
                              primaryText: primaryText,
                              secondaryText: secondaryText,
                              card: card,
                              divider: divider,
                              accentColor:
                                  _getRoleColor(_currentRole ?? 'student'),
                            ),
                            const SizedBox(height: 28),
                            if (_isSystemAdmin) ...[
                              SizedBox(
                                width: double.infinity,
                                height: 54,
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            const UsersFeedbackScreen(),
                                      ),
                                    );
                                  },
                                  icon: const Icon(CupertinoIcons.chat_bubble_2),
                                  label: const Text(
                                    'User Feedback',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: primaryText,
                                    side: BorderSide(color: divider),
                                    backgroundColor: card,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                            SizedBox(
                              width: double.infinity,
                              height: 54,
                              child: ElevatedButton(
                                onPressed: _isSaving || !_hasUnsavedChanges
                                    ? null
                                    : _saveProfile,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _accent,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor:
                                      _accent.withOpacity(0.45),
                                  disabledForegroundColor:
                                      Colors.white.withOpacity(0.85),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  elevation: 0,
                                ),
                                child: _isSaving
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                            Colors.white,
                                          ),
                                        ),
                                      )
                                    : const Text(
                                        'Save Changes',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _avatarPreview({
    required Color card,
    required Color divider,
  }) {
    if (_pendingAvatarBytes != null) {
      return CircleAvatar(
        radius: 50,
        backgroundImage: MemoryImage(_pendingAvatarBytes!),
        backgroundColor: card,
      );
    }
    if (!_removeAvatar && _avatarUrlController.text.isNotEmpty) {
      return CircleAvatar(
        radius: 50,
        backgroundImage: NetworkImage(_avatarUrlController.text),
        backgroundColor: card,
        onBackgroundImageError: (_, __) {},
      );
    }
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_accent, Color(0xFF8B5CF6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(50),
        border: Border.all(color: divider, width: 0),
      ),
      child: Center(
        child: Text(
          _getInitials(_fullNameController.text),
          style: const TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String title, Color muted) {
    return Text(
      title.toUpperCase(),
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
        color: muted,
      ),
    );
  }

  Widget _themedField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required String hint,
    required Color primaryText,
    required Color secondaryText,
    required Color card,
    required Color divider,
    required bool enabled,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      validator: validator,
      style: TextStyle(
        color: primaryText,
        fontWeight: FontWeight.w500,
        fontSize: 16,
      ),
      cursorColor: _accent,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          color: secondaryText,
          fontWeight: FontWeight.w600,
        ),
        hintText: hint,
        hintStyle: TextStyle(color: secondaryText.withOpacity(0.7)),
        prefixIcon: Icon(icon, color: _accent, size: 20),
        filled: true,
        fillColor: card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: divider),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _danger, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }

  Widget _buildReadOnlyField({
    required String label,
    required String value,
    required IconData icon,
    required Color primaryText,
    required Color secondaryText,
    required Color card,
    required Color divider,
    Color? accentColor,
  }) {
    final iconColor = accentColor ?? secondaryText;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: divider),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: secondaryText,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    color: accentColor ?? primaryText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Icon(CupertinoIcons.lock_fill, color: secondaryText, size: 16),
        ],
      ),
    );
  }

  String _getInitials(String name) {
    if (name.trim().isEmpty) return 'U';
    final parts = name.trim().split(' ');
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
      case 'student':
      default:
        return const Color(0xFF10B981);
    }
  }

  IconData _getRoleIcon(String role) {
    switch (role.toLowerCase()) {
      case 'system_admin':
      case 'super_admin':
        return CupertinoIcons.shield_fill;
      case 'admin':
        return CupertinoIcons.person_crop_circle_badge_checkmark;
      case 'lecturer':
        return CupertinoIcons.book_fill;
      case 'class_rep':
        return CupertinoIcons.person_2_fill;
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
}
