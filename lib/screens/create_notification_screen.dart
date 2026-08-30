import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../services/course_service.dart';
import '../services/media_service.dart';
import '../services/notification_service.dart';
import '../ui/adaptive_layout.dart';
import 'system_admin_dashboard.dart';

class CreateNotificationScreen extends StatefulWidget {
  const CreateNotificationScreen({super.key});

  @override
  State<CreateNotificationScreen> createState() =>
      _CreateNotificationScreenState();
}

class _CreateNotificationScreenState extends State<CreateNotificationScreen> {
  static const _accent = Color(0xFF6366F1);
  static const _danger = Color(0xFFEF4444);
  static const _success = Color(0xFF10B981);

  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _messageController = TextEditingController();

  String _selectedType = 'general';
  String _audience = 'class';
  bool _isLoading = false;
  bool _isLoadingProfile = true;
  String _role = 'student';
  String _classLabel = '';
  String _courseName = '';
  List<Course> _courses = [];
  String? _selectedCourseId;
  Uint8List? _imageBytes;
  String? _imageName;
  String? _imageMime;

  static const _notificationTypes = <({
    String value,
    String label,
    IconData icon,
    Color color,
  })>[
    (
      value: 'general',
      label: 'General',
      icon: CupertinoIcons.bell_fill,
      color: _accent,
    ),
    (
      value: 'assignment',
      label: 'Assignment',
      icon: CupertinoIcons.doc_text_fill,
      color: Color(0xFF3B82F6),
    ),
    (
      value: 'exam',
      label: 'Exam',
      icon: CupertinoIcons.pencil_ellipsis_rectangle,
      color: Color(0xFFEF4444),
    ),
    (
      value: 'event',
      label: 'Event',
      icon: CupertinoIcons.calendar,
      color: Color(0xFF8B5CF6),
    ),
    (
      value: 'announcement',
      label: 'Announcement',
      icon: CupertinoIcons.speaker_2_fill,
      color: Color(0xFFF59E0B),
    ),
  ];

  bool get _isClassLeadership =>
      _role == 'class_rep' || _role == 'assistant_class_rep';

  bool get _isSystemAdmin => SystemAdminDashboard.isSystemAdminRole(_role);

  Course? get _selectedCourse {
    for (final course in _courses) {
      if (course.id == _selectedCourseId) return course;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadSenderContext();
  }

  Future<void> _loadSenderContext() async {
    try {
      final user = AuthService.instance.currentUser;
      if (user == null) {
        if (mounted) setState(() => _isLoadingProfile = false);
        return;
      }

      final profileDoc = await FirebaseFirestore.instance
          .collection('profiles')
          .doc(user.uid)
          .get();
      final data = profileDoc.data() ?? {};
      final role = ((data['role'] as String?) ?? 'student').toLowerCase();
      final admissionNumber = (data['admission_number'] as String?) ?? '';
      final prefix = Course.admissionPrefixFromSample(admissionNumber);
      final suffix = Course.classSuffixFromSample(admissionNumber);
      final courses = await CourseService.instance.listCourses();
      final course =
          CourseService.instance.matchCourse(admissionNumber, courses);

      if (!mounted) return;
      setState(() {
        _role = role;
        _classLabel = prefix.isNotEmpty && suffix.isNotEmpty
            ? '$prefix / $suffix'
            : '';
        _courseName = course?.name ?? '';
        _courses = List<Course>.from(courses)
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
        _audience = (role == 'class_rep' || role == 'assistant_class_rep')
            ? 'class'
            : 'all';
        _isLoadingProfile = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingProfile = false);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  String get _audienceHint {
    if (_isClassLeadership && _audience == 'course') {
      return _courseName.isEmpty
          ? 'This notification will be visible to everyone in your course'
          : 'This notification will be visible to all $_courseName students';
    }
    if (_isClassLeadership) {
      return _classLabel.isEmpty
          ? 'This notification will be visible to your class only'
          : 'This notification will be visible to class $_classLabel';
    }
    if (_isSystemAdmin && _audience == 'course') {
      final selected = _selectedCourse;
      return selected == null
          ? 'Choose a course to notify its members'
          : 'This notification will be visible to all ${selected.name} members';
    }
    return 'This notification will be visible to all users';
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

  Future<void> _pickImage() async {
    if (_isLoading) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
      dialogTitle: 'Attach an image',
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) return;

    const maxBytes = 8 * 1024 * 1024;
    if (bytes.length > maxBytes) {
      if (!mounted) return;
      _showSnack('Please choose an image smaller than 8 MB.', _danger);
      return;
    }

    setState(() {
      _imageBytes = bytes;
      _imageName = file.name;
      _imageMime = MediaService.mimeFromName(file.name, file.extension);
    });
  }

  Future<void> _createNotification() async {
    if (!_formKey.currentState!.validate()) return;

    if (_isSystemAdmin &&
        _audience == 'course' &&
        (_selectedCourseId == null || _selectedCourseId!.isEmpty)) {
      _showSnack('Please select a course', _danger);
      return;
    }

    setState(() => _isLoading = true);

    try {
      String? imageUrl;
      String? imagePublicId;
      final bytes = _imageBytes;
      if (bytes != null && bytes.isNotEmpty) {
        final uploaded = await MediaService.instance.uploadImage(
          bytes: bytes,
          fileName: _imageName ?? 'notification.jpg',
          mimeType: _imageMime ?? 'image/jpeg',
          folder: MediaService.folderNotifications,
        );
        imageUrl = uploaded.url;
        imagePublicId = uploaded.publicId;
      }

      await NotificationService.instance.create(
        title: _titleController.text,
        message: _messageController.text,
        type: _selectedType,
        audience: _audience,
        imageUrl: imageUrl,
        imagePublicId: imagePublicId,
        targetCourseId: _isSystemAdmin ? _selectedCourseId : null,
      );

      if (mounted) {
        _showSnack('Notification sent successfully', _success);
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Error creating notification: $e', _danger);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Keep content above [MainScreen]'s tab bar when this route is nested
  /// (Home → Notifications). From Profile the root route already covers it.
  double _bottomContentInset(BuildContext context) {
    final nested =
        Navigator.of(context) != Navigator.of(context, rootNavigator: true);
    if (nested) {
      return AdaptiveLayout.bottomClearance(context);
    }
    return MediaQuery.viewPaddingOf(context).bottom;
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

    return Scaffold(
      backgroundColor: background,
      body: _isLoadingProfile
          ? Center(
              child: CupertinoActivityIndicator(
                color: isDark ? Colors.white : _accent,
                radius: 14,
              ),
            )
          : CustomScrollView(
              physics: const BouncingScrollPhysics(),
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
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    0,
                    20,
                    24 + _bottomContentInset(context),
                  ),
                  sliver: SliverToBoxAdapter(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Create Notification',
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
                            'Post to your class, course, or everyone',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: muted,
                            ),
                          ),
                          const SizedBox(height: 20),
                          _hintBanner(
                            isDark: isDark,
                            titleColor: titleColor,
                            card: card,
                          ),
                          if (_isClassLeadership) ...[
                            const SizedBox(height: 28),
                            _sectionLabel('Send to', muted),
                            const SizedBox(height: 12),
                            _buildAudienceOption(
                              value: 'class',
                              title: _classLabel.isEmpty
                                  ? 'My class'
                                  : 'My class ($_classLabel)',
                              subtitle: 'Only students in your year/class',
                              icon: CupertinoIcons.person_2_fill,
                              titleColor: titleColor,
                              muted: muted,
                              card: card,
                              divider: divider,
                            ),
                            const SizedBox(height: 10),
                            _buildAudienceOption(
                              value: 'course',
                              title: _courseName.isEmpty
                                  ? 'Entire course'
                                  : 'Entire course ($_courseName)',
                              subtitle: 'All years in your course',
                              icon: CupertinoIcons.book_fill,
                              titleColor: titleColor,
                              muted: muted,
                              card: card,
                              divider: divider,
                            ),
                          ],
                          if (_isSystemAdmin) ...[
                            const SizedBox(height: 28),
                            _sectionLabel('Send to', muted),
                            const SizedBox(height: 12),
                            _buildAudienceOption(
                              value: 'all',
                              title: 'Everyone',
                              subtitle: 'All users on the platform',
                              icon: CupertinoIcons.globe,
                              titleColor: titleColor,
                              muted: muted,
                              card: card,
                              divider: divider,
                            ),
                            const SizedBox(height: 10),
                            _buildAudienceOption(
                              value: 'course',
                              title: 'Course members',
                              subtitle: _courses.isEmpty
                                  ? 'No courses available yet'
                                  : 'Members of a specific existing course',
                              icon: CupertinoIcons.book_fill,
                              titleColor: titleColor,
                              muted: muted,
                              card: card,
                              divider: divider,
                            ),
                            if (_audience == 'course') ...[
                              const SizedBox(height: 12),
                              if (_courses.isEmpty)
                                Text(
                                  'No courses available yet',
                                  style: TextStyle(fontSize: 13, color: muted),
                                )
                              else
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: _courses.map((course) {
                                    return _chip(
                                      label: course.name,
                                      selected: _selectedCourseId == course.id,
                                      onTap: () => setState(
                                        () => _selectedCourseId = course.id,
                                      ),
                                      titleColor: titleColor,
                                      muted: muted,
                                      card: card,
                                      divider: divider,
                                      icon: CupertinoIcons.book,
                                    );
                                  }).toList(),
                                ),
                            ],
                          ],
                          const SizedBox(height: 28),
                          _sectionLabel('Type', muted),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _notificationTypes.map((type) {
                              return _chip(
                                label: type.label,
                                selected: _selectedType == type.value,
                                onTap: () =>
                                    setState(() => _selectedType = type.value),
                                titleColor: titleColor,
                                muted: muted,
                                card: card,
                                divider: divider,
                                icon: type.icon,
                                selectedColor: type.color,
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 28),
                          _sectionLabel('Title (optional)', muted),
                          const SizedBox(height: 10),
                          _themedField(
                            controller: _titleController,
                            hint: 'Add a title, or leave blank',
                            titleColor: titleColor,
                            muted: muted,
                            card: card,
                            divider: divider,
                          ),
                          const SizedBox(height: 20),
                          _sectionLabel('Message', muted),
                          const SizedBox(height: 10),
                          _themedField(
                            controller: _messageController,
                            hint: 'What should people know?',
                            titleColor: titleColor,
                            muted: muted,
                            card: card,
                            divider: divider,
                            maxLines: 5,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Please enter a message';
                              }
                              if (value.trim().length < 10) {
                                return 'Message must be at least 10 characters';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 20),
                          _sectionLabel('Image (optional)', muted),
                          const SizedBox(height: 10),
                          if (_imageBytes != null) ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.memory(
                                _imageBytes!,
                                height: 180,
                                width: double.infinity,
                                fit: BoxFit.cover,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: _isLoading
                                  ? null
                                  : () {
                                      setState(() {
                                        _imageBytes = null;
                                        _imageName = null;
                                        _imageMime = null;
                                      });
                                    },
                              icon: const Icon(
                                CupertinoIcons.trash,
                                size: 16,
                                color: _danger,
                              ),
                              label: const Text(
                                'Remove image',
                                style: TextStyle(
                                  color: _danger,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ] else
                            OutlinedButton.icon(
                              onPressed: _isLoading ? null : _pickImage,
                              icon: const Icon(
                                CupertinoIcons.photo,
                                size: 18,
                              ),
                              label: const Text(
                                'Upload image',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(double.infinity, 52),
                                foregroundColor: titleColor,
                                side: BorderSide(color: divider),
                                backgroundColor: card,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          const SizedBox(height: 28),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed:
                                  _isLoading ? null : _createNotification,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _accent,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor:
                                    _accent.withOpacity(0.55),
                                elevation: 0,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                          Colors.white,
                                        ),
                                      ),
                                    )
                                  : const Text(
                                      'Send Notification',
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
    );
  }

  Widget _sectionLabel(String label, Color muted) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
        color: muted,
      ),
    );
  }

  Widget _hintBanner({
    required bool isDark,
    required Color titleColor,
    required Color card,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          _accent.withOpacity(isDark ? 0.16 : 0.08),
          card,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _accent.withOpacity(isDark ? 0.28 : 0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _accent.withOpacity(0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              CupertinoIcons.info_circle_fill,
              color: _accent,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _audienceHint,
              style: TextStyle(
                fontSize: 14,
                height: 1.35,
                fontWeight: FontWeight.w500,
                color: titleColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    required Color titleColor,
    required Color muted,
    required Color card,
    required Color divider,
    IconData? icon,
    Color selectedColor = _accent,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? selectedColor : card,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: selected ? selectedColor : divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 15,
                color: selected ? Colors.white : muted,
              ),
              const SizedBox(width: 7),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : titleColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudienceOption({
    required String value,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color titleColor,
    required Color muted,
    required Color card,
    required Color divider,
  }) {
    final isSelected = _audience == value;
    return Material(
      color: isSelected
          ? Color.alphaBlend(_accent.withOpacity(0.12), card)
          : card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected ? _accent : divider,
          width: isSelected ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() => _audience = value),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: (isSelected ? _accent : muted).withOpacity(0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: isSelected ? _accent : muted,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isSelected ? _accent : titleColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 13, color: muted),
                    ),
                  ],
                ),
              ),
              Icon(
                isSelected
                    ? CupertinoIcons.checkmark_circle_fill
                    : CupertinoIcons.circle,
                color: isSelected ? _accent : muted,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _themedField({
    required TextEditingController controller,
    required String hint,
    required Color titleColor,
    required Color muted,
    required Color card,
    required Color divider,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      validator: validator,
      style: TextStyle(color: titleColor, fontSize: 16),
      cursorColor: _accent,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: muted),
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
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
    );
  }
}
