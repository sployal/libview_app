import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/course_service.dart';
import '../services/upload_service.dart';
import '../ui/adaptive_layout.dart';

class CourseAdditionScreen extends StatefulWidget {
  const CourseAdditionScreen({super.key, this.course});

  final Course? course;

  @override
  State<CourseAdditionScreen> createState() => _CourseAdditionScreenState();
}

class _CourseAdditionScreenState extends State<CourseAdditionScreen> {
  static const _accent = Color(0xFF6366F1);
  static const _danger = Color(0xFFEF4444);
  static const _success = Color(0xFF10B981);

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _yearsController = TextEditingController();
  final _admissionController = TextEditingController();

  bool _isSubmitting = false;
  String? _status;

  bool get _isEditing => widget.course != null;

  @override
  void initState() {
    super.initState();
    final course = widget.course;
    if (course != null) {
      _nameController.text = course.name;
      _yearsController.text = course.years.toString();
      _admissionController.text = course.sampleAdmissionNumber;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _yearsController.dispose();
    _admissionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _isSubmitting) return;

    final years = int.parse(_yearsController.text.trim());
    setState(() {
      _isSubmitting = true;
      _status = _isEditing
          ? 'Updating "${_nameController.text.trim()}" and renaming the Drive course folder...'
          : 'Creating "${_nameController.text.trim()}" and $years year folders on Drive...';
    });

    try {
      if (_isEditing) {
        await CourseService.instance.updateCourse(
          course: widget.course!,
          name: _nameController.text,
          years: years,
          sampleAdmissionNumber: _admissionController.text,
        );
      } else {
        await CourseService.instance.createCourse(
          name: _nameController.text,
          years: years,
          sampleAdmissionNumber: _admissionController.text,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _isEditing
                      ? 'Course updated and Drive folder renamed'
                      : 'Course created and folders saved',
                ),
              ),
            ],
          ),
          backgroundColor: _success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context, true);
    } on UploadException catch (error) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _status = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          backgroundColor: _danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _status = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
          _isEditing
              ? 'Could not update course: $error'
              : 'Could not create course: $error',
        ),
          backgroundColor: _danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
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
    final divider = isDark ? const Color(0xFF374151) : const Color(0xFFE5E7EB);
    final pagePad = AdaptiveLayout.pagePadding(context);
    final tablet = AdaptiveLayout.isTablet(context);

    final prefix = Course.admissionPrefixFromSample(_admissionController.text);
    final years = int.tryParse(_yearsController.text.trim()) ?? 0;
    final folderPreview = years > 0
        ? 'year 1 sem 1  →  year $years sem 2'
        : 'year 1 sem 1, year 1 sem 2, ...';

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
          _isEditing ? 'Edit Course' : 'Add Course',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: tablet ? 22 : 20,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: pagePad.copyWith(
            top: 8,
            bottom: 40 + MediaQuery.viewPaddingOf(context).bottom,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: divider),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _accent.withOpacity(isDark ? 0.22 : 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          CupertinoIcons.folder_fill,
                          color: _accent,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _isEditing
                              ? 'Changing the course name also renames the main Drive folder under Edupal. Year and semester folders stay in place.'
                              : 'A course folder is created under Edupal, with year / semester subfolders. Those Drive IDs are stored in Firebase so students see the right materials.',
                          style: TextStyle(
                            color: secondaryText,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                _sectionLabel('Course details', secondaryText),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _nameController,
                  label: 'Course name',
                  hint: 'e.g. Engineering',
                  icon: CupertinoIcons.book_fill,
                  primaryText: primaryText,
                  secondaryText: secondaryText,
                  card: card,
                  divider: divider,
                  onChanged: (_) => setState(() {}),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Enter a course name';
                    }
                    if (value.trim().length < 2) {
                      return 'Course name is too short';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _yearsController,
                  label: 'Number of years',
                  hint: 'e.g. 5',
                  icon: CupertinoIcons.calendar,
                  primaryText: primaryText,
                  secondaryText: secondaryText,
                  card: card,
                  divider: divider,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => setState(() {}),
                  validator: (value) {
                    final yearsValue = int.tryParse(value?.trim() ?? '');
                    if (yearsValue == null) {
                      return 'Enter the number of years';
                    }
                    if (yearsValue < 1 || yearsValue > 10) {
                      return 'Use a value between 1 and 10';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _admissionController,
                  label: 'Sample admission number',
                  hint: 'e.g. C2/11745/24',
                  icon: CupertinoIcons.creditcard_fill,
                  primaryText: primaryText,
                  secondaryText: secondaryText,
                  card: card,
                  divider: divider,
                  onChanged: (_) => setState(() {}),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Enter a sample admission number';
                    }
                    if (!Course.isValidAdmissionNumber(value)) {
                      return 'Use prefix/number/year, e.g. C2/11745/24';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                Text(
                  prefix.isEmpty
                      ? 'The part before the first / is the course code (C2, EB24, BBIT — any letters or numbers). Matching ignores case. The part after the last / groups classmates.'
                      : 'Users whose admission number starts with "$prefix/" will be linked to this course. Matching ignores case. The last segment after / groups them into the same class.',
                  style: TextStyle(
                    fontSize: 13,
                    color: secondaryText,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                _sectionLabel('Drive folders', secondaryText),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: divider),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            CupertinoIcons.folder,
                            color: _accent,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Preview',
                            style: TextStyle(
                              color: primaryText,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Edupal / ${_nameController.text.trim().isEmpty ? 'Course name' : _nameController.text.trim()}',
                        style: TextStyle(
                          color: primaryText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        folderPreview,
                        style: TextStyle(
                          color: secondaryText,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_status != null) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(_accent),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _status!,
                          style: TextStyle(color: secondaryText),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: _isSubmitting ? null : _submit,
                    icon: Icon(
                      _isEditing
                          ? CupertinoIcons.checkmark_alt
                          : CupertinoIcons.add,
                    ),
                    label: Text(
                      _isSubmitting
                          ? (_isEditing ? 'Saving...' : 'Creating...')
                          : (_isEditing ? 'Save changes' : 'Create course'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: _accent.withOpacity(0.45),
                      disabledForegroundColor: Colors.white.withOpacity(0.85),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required Color primaryText,
    required Color secondaryText,
    required Color card,
    required Color divider,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    TextCapitalization textCapitalization = TextCapitalization.none,
    ValueChanged<String>? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      textCapitalization: textCapitalization,
      onChanged: onChanged,
      enabled: !_isSubmitting,
      style: TextStyle(
        color: primaryText,
        fontSize: 16,
        fontWeight: FontWeight.w500,
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
}
