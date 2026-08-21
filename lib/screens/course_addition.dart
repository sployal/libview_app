import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/course_service.dart';
import '../services/upload_service.dart';

class CourseAdditionScreen extends StatefulWidget {
  const CourseAdditionScreen({super.key, this.course});

  final Course? course;

  @override
  State<CourseAdditionScreen> createState() => _CourseAdditionScreenState();
}

class _CourseAdditionScreenState extends State<CourseAdditionScreen> {
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
          backgroundColor: const Color(0xFF10B981),
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
          backgroundColor: const Color(0xFFEF4444),
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
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefix = Course.admissionPrefixFromSample(_admissionController.text);
    final years = int.tryParse(_yearsController.text.trim()) ?? 0;
    final folderPreview = years > 0
        ? 'year 1 sem 1  →  year $years sem 2'
        : 'year 1 sem 1, year 1 sem 2, ...';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          _isEditing ? 'Edit Course' : 'Add Course',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
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
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.folder_copy_rounded, color: Colors.white),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _isEditing
                              ? 'Changing the course name also renames the main Drive folder under Edupal. Year and semester folders stay in place.'
                              : 'A course folder is created under Edupal, with year / semester subfolders. Those Drive IDs are stored in Firebase so students see the right materials.',
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
                const SizedBox(height: 32),
                _buildTextField(
                  controller: _nameController,
                  label: 'Course name',
                  hint: 'e.g. Engineering',
                  icon: Icons.school_rounded,
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
                const SizedBox(height: 24),
                _buildTextField(
                  controller: _yearsController,
                  label: 'Number of years',
                  hint: 'e.g. 5',
                  icon: Icons.calendar_month_rounded,
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
                const SizedBox(height: 24),
                _buildTextField(
                  controller: _admissionController,
                  label: 'Sample admission number',
                  hint: 'e.g. EB24/46271/20',
                  icon: Icons.badge_rounded,
                  onChanged: (_) => setState(() {}),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Enter a sample admission number';
                    }
                    if (Course.admissionPrefixFromSample(value).isEmpty) {
                      return 'Use a code before the first /, e.g. EB24/56121/21';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  prefix.isEmpty
                      ? 'The code before the first / (for example EB24 in EB24/56121/21) decides the course. The numbers after the last / (for example 21) group class members.'
                      : 'Users whose admission number starts with "$prefix/" will be linked to this course. The last segment after / groups them into the same class.',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Drive folders',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Edupal / ${_nameController.text.trim().isEmpty ? 'Course name' : _nameController.text.trim()}',
                        style: const TextStyle(color: Color(0xFFCBD5E1)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        folderPreview,
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
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
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _status!,
                          style: const TextStyle(color: Color(0xFF4B5563)),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isSubmitting ? null : _submit,
                    icon: Icon(
                      _isEditing ? Icons.save_rounded : Icons.add_rounded,
                    ),
                    label: Text(
                      _isSubmitting
                          ? (_isEditing ? 'Saving...' : 'Creating...')
                          : (_isEditing ? 'Save changes' : 'Create course'),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFF94A3B8),
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
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    TextCapitalization textCapitalization = TextCapitalization.none,
    ValueChanged<String>? onChanged,
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
        TextFormField(
          controller: controller,
          validator: validator,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          textCapitalization: textCapitalization,
          onChanged: onChanged,
          enabled: !_isSubmitting,
          style: const TextStyle(
            color: Color(0xFF1F2937),
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey[400]),
            prefixIcon: Icon(icon, color: const Color(0xFF6366F1)),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Color(0xFF6366F1), width: 2),
            ),
          ),
        ),
      ],
    );
  }
}
