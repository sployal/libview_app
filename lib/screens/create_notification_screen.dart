import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/course_service.dart';
import '../services/media_service.dart';
import '../services/notification_service.dart';

class CreateNotificationScreen extends StatefulWidget {
  const CreateNotificationScreen({super.key});

  @override
  State<CreateNotificationScreen> createState() =>
      _CreateNotificationScreenState();
}

class _CreateNotificationScreenState extends State<CreateNotificationScreen> {
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

  final List<Map<String, dynamic>> _notificationTypes = [
    {
      'value': 'general',
      'label': 'General',
      'icon': Icons.notifications_rounded,
      'color': Color(0xFF6B7280),
    },
    {
      'value': 'assignment',
      'label': 'Assignment',
      'icon': Icons.assignment_rounded,
      'color': Color(0xFF3B82F6),
    },
    {
      'value': 'exam',
      'label': 'Exam',
      'icon': Icons.quiz_rounded,
      'color': Color(0xFFEF4444),
    },
    {
      'value': 'event',
      'label': 'Event',
      'icon': Icons.event_rounded,
      'color': Color(0xFF8B5CF6),
    },
    {
      'value': 'announcement',
      'label': 'Announcement',
      'icon': Icons.campaign_rounded,
      'color': Color(0xFFF59E0B),
    },
  ];

  bool get _isClassLeadership =>
      _role == 'class_rep' || _role == 'assistant_class_rep';

  bool get _isSuperAdmin => _role == 'super_admin';

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
      final registrationNumber =
          (data['registration_number'] as String?) ?? '';
      final prefix = Course.admissionPrefixFromSample(registrationNumber);
      final suffix = Course.classSuffixFromSample(registrationNumber);
      final courses = await CourseService.instance.listCourses();
      final course =
          CourseService.instance.matchCourse(registrationNumber, courses);

      if (!mounted) return;
      setState(() {
        _role = role;
        _classLabel = prefix.isNotEmpty && suffix.isNotEmpty
            ? '$prefix / $suffix'
            : '';
        _courseName = course?.name ?? '';
        _courses = List<Course>.from(courses)
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
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
    if (_isSuperAdmin && _audience == 'course') {
      final selected = _selectedCourse;
      return selected == null
          ? 'Choose a course to notify its members'
          : 'This notification will be visible to all ${selected.name} members';
    }
    return 'This notification will be visible to all users';
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please choose an image smaller than 8 MB.'),
          backgroundColor: Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
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

    if (_isSuperAdmin &&
        _audience == 'course' &&
        (_selectedCourseId == null || _selectedCourseId!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please select a course'),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
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
        targetCourseId: _isSuperAdmin ? _selectedCourseId : null,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Notification sent successfully!',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Error creating notification: $e',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF1F2937)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Create Notification',
          style: TextStyle(
            color: Color(0xFF1F2937),
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: _isLoadingProfile
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.info_outline_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              _audienceHint,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_isClassLeadership) ...[
                      const SizedBox(height: 32),
                      const Text(
                        'Send to',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildAudienceOption(
                        value: 'class',
                        title: _classLabel.isEmpty
                            ? 'My class'
                            : 'My class ($_classLabel)',
                        subtitle: 'Only students in your year/class',
                        icon: Icons.groups_rounded,
                      ),
                      const SizedBox(height: 8),
                      _buildAudienceOption(
                        value: 'course',
                        title: _courseName.isEmpty
                            ? 'Entire course'
                            : 'Entire course ($_courseName)',
                        subtitle: 'All years in your course',
                        icon: Icons.school_rounded,
                      ),
                    ],
                    if (_isSuperAdmin) ...[
                      const SizedBox(height: 32),
                      const Text(
                        'Send to',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildAudienceOption(
                        value: 'all',
                        title: 'Everyone',
                        subtitle: 'All users on the platform',
                        icon: Icons.public_rounded,
                      ),
                      const SizedBox(height: 8),
                      _buildAudienceOption(
                        value: 'course',
                        title: 'Course members',
                        subtitle: _courses.isEmpty
                            ? 'No courses available yet'
                            : 'Members of a specific existing course',
                        icon: Icons.school_rounded,
                      ),
                      if (_audience == 'course') ...[
                        const SizedBox(height: 12),
                        if (_courses.isEmpty)
                          const Text(
                            'No courses available yet',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF6B7280),
                            ),
                          )
                        else
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _courses.map((course) {
                              final isSelected = _selectedCourseId == course.id;
                              return GestureDetector(
                                onTap: () {
                                  setState(() => _selectedCourseId = course.id);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? const Color(0xFF6366F1).withOpacity(0.1)
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isSelected
                                          ? const Color(0xFF6366F1)
                                          : const Color(0xFFE5E7EB),
                                      width: isSelected ? 2 : 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.school_rounded,
                                        size: 18,
                                        color: isSelected
                                            ? const Color(0xFF6366F1)
                                            : const Color(0xFF6B7280),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        course.name,
                                        style: TextStyle(
                                          color: isSelected
                                              ? const Color(0xFF6366F1)
                                              : const Color(0xFF1F2937),
                                          fontWeight: isSelected
                                              ? FontWeight.bold
                                              : FontWeight.w500,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                      ],
                    ],
                    const SizedBox(height: 32),
                    const Text(
                      'Notification Type',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _notificationTypes.map((type) {
                        final isSelected = _selectedType == type['value'];
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedType = type['value'] as String;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? (type['color'] as Color).withOpacity(0.1)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? type['color'] as Color
                                    : const Color(0xFFE5E7EB),
                                width: isSelected ? 2 : 1,
                              ),
                              boxShadow: [
                                if (isSelected)
                                  BoxShadow(
                                    color: (type['color'] as Color)
                                        .withOpacity(0.2),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  type['icon'] as IconData,
                                  color: isSelected
                                      ? type['color'] as Color
                                      : const Color(0xFF6B7280),
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  type['label'] as String,
                                  style: TextStyle(
                                    color: isSelected
                                        ? type['color'] as Color
                                        : const Color(0xFF6B7280),
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.w500,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(                      ),
                    ),
                    const SizedBox(height: 32),
                    _buildTextField(
                      controller: _titleController,
                      label: 'Title (optional)',
                      hint: 'Enter a title, or leave blank',
                      icon: Icons.title_rounded,
                      maxLines: 1,
                    ),
                    const SizedBox(height: 24),
                    _buildTextField(
                      controller: _messageController,
                      label: 'Message',
                      hint: 'Enter notification message',
                      icon: Icons.message_rounded,
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
                    const SizedBox(height: 24),
                    const Text(
                      'Image (optional)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(height: 12),
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
                        icon: const Icon(Icons.close_rounded, color: Color(0xFFEF4444)),
                        label: const Text(
                          'Remove image',
                          style: TextStyle(color: Color(0xFFEF4444)),
                        ),
                      ),
                    ] else
                      OutlinedButton.icon(
                        onPressed: _isLoading ? null : _pickImage,
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        label: const Text('Upload image'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 52),
                          foregroundColor: const Color(0xFF6366F1),
                          side: const BorderSide(color: Color(0xFF6366F1)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFF6366F1),
                              Color(0xFF8B5CF6),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF6366F1).withOpacity(0.4),
                              blurRadius: 15,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _createNotification,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 0,
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.send_rounded, size: 20),
                                    SizedBox(width: 8),
                                    Text(
                                      'Send Notification',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
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
            ),
    );
  }

  Widget _buildAudienceOption({
    required String value,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final isSelected = _audience == value;
    return GestureDetector(
      onTap: () => setState(() => _audience = value),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF6366F1).withOpacity(0.08)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF6366F1)
                : const Color(0xFFE5E7EB),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected
                  ? const Color(0xFF6366F1)
                  : const Color(0xFF6B7280),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isSelected
                          ? const Color(0xFF6366F1)
                          : const Color(0xFF1F2937),
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              isSelected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              color: isSelected
                  ? const Color(0xFF6366F1)
                  : const Color(0xFF9CA3AF),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1F2937),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: TextFormField(
            controller: controller,
            maxLines: maxLines,
            validator: validator,
            style: const TextStyle(
              color: Color(0xFF1F2937),
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                color: Colors.grey[400],
                fontWeight: FontWeight.w400,
              ),
              prefixIcon: Container(
                margin: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: const Color(0xFF6366F1), size: 20),
              ),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB), width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFF6366F1), width: 2),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFFEF4444), width: 2),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
