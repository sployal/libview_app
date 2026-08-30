import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../services/support_service.dart';
import '../ui/adaptive_layout.dart';
import 'no_internet_screen.dart';

class HelpAndSupportScreen extends StatefulWidget {
  const HelpAndSupportScreen({super.key});

  @override
  State<HelpAndSupportScreen> createState() => _HelpAndSupportScreenState();
}

class _HelpAndSupportScreenState extends State<HelpAndSupportScreen> {
  static const _accent = Color(0xFF6366F1);
  static const _danger = Color(0xFFEF4444);
  static const _success = Color(0xFF10B981);

  final _formKey = GlobalKey<FormState>();
  final _headingController = TextEditingController();
  final _descriptionController = TextEditingController();

  Uint8List? _screenshotBytes;
  String? _screenshotName;
  String? _screenshotMime;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _headingController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickScreenshot() async {
    if (_isSubmitting) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
      dialogTitle: 'Attach a screenshot',
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
      _screenshotBytes = bytes;
      _screenshotName = file.name;
      _screenshotMime = _mimeFromName(file.name, file.extension);
    });
  }

  String _mimeFromName(String name, String? extension) {
    final ext = (extension ?? name.split('.').last).toLowerCase();
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _isSubmitting) return;
    if (!await NoInternetScreen.ensureOnline(context)) return;
    if (!mounted) return;

    setState(() => _isSubmitting = true);

    try {
      String? screenshotUrl;
      String? screenshotPublicId;
      final bytes = _screenshotBytes;
      if (bytes != null && bytes.isNotEmpty) {
        final uploaded = await SupportService.instance.uploadScreenshot(
          bytes: bytes,
          fileName: _screenshotName ?? 'screenshot.jpg',
          mimeType: _screenshotMime ?? 'image/jpeg',
        );
        screenshotUrl = uploaded['url'];
        screenshotPublicId = uploaded['publicId'];
        if (screenshotUrl == null || screenshotUrl.isEmpty) {
          throw Exception('Screenshot upload did not return a URL');
        }
      }

      await SupportService.instance.submitMessage(
        heading: _headingController.text,
        description: _descriptionController.text,
        screenshotUrl: screenshotUrl,
        screenshotPublicId: screenshotPublicId,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your message was sent. We will look into it.'),
          backgroundColor: _success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not send message: $e'),
          backgroundColor: _danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
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

    return Scaffold(
      backgroundColor: background,
      body: CustomScrollView(
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
              'Help & Support',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: tablet ? 22 : 20,
              ),
            ),
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
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Color.alphaBlend(
                          _accent.withOpacity(isDark ? 0.16 : 0.08),
                          card,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _accent.withOpacity(isDark ? 0.28 : 0.18),
                        ),
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
                              'Describe the issue you are facing. A screenshot is optional and helps us understand the problem faster.',
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.35,
                                fontWeight: FontWeight.w500,
                                color: primaryText,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    _sectionLabel('Heading', secondaryText),
                    const SizedBox(height: 10),
                    _themedField(
                      controller: _headingController,
                      hint: 'Short title for the issue',
                      primaryText: primaryText,
                      secondaryText: secondaryText,
                      card: card,
                      divider: divider,
                      enabled: !_isSubmitting,
                      textCapitalization: TextCapitalization.sentences,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please add a heading';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    _sectionLabel('Description', secondaryText),
                    const SizedBox(height: 10),
                    _themedField(
                      controller: _descriptionController,
                      hint: 'Describe what happened and what you expected',
                      primaryText: primaryText,
                      secondaryText: secondaryText,
                      card: card,
                      divider: divider,
                      enabled: !_isSubmitting,
                      minLines: 6,
                      maxLines: 12,
                      textCapitalization: TextCapitalization.sentences,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please describe the issue';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    _sectionLabel('Screenshot (optional)', secondaryText),
                    const SizedBox(height: 10),
                    if (_screenshotBytes != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.memory(
                          _screenshotBytes!,
                          height: 180,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: _isSubmitting
                            ? null
                            : () {
                                setState(() {
                                  _screenshotBytes = null;
                                  _screenshotName = null;
                                  _screenshotMime = null;
                                });
                              },
                        icon: const Icon(
                          CupertinoIcons.trash,
                          size: 16,
                          color: _danger,
                        ),
                        label: const Text(
                          'Remove screenshot',
                          style: TextStyle(
                            color: _danger,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ] else
                      OutlinedButton.icon(
                        onPressed: _isSubmitting ? null : _pickScreenshot,
                        icon: const Icon(CupertinoIcons.photo, size: 18),
                        label: const Text(
                          'Add screenshot',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 52),
                          foregroundColor: primaryText,
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
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accent,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: _accent.withOpacity(0.45),
                          disabledForegroundColor:
                              Colors.white.withOpacity(0.85),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : const Text(
                                'Send message',
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

  Widget _themedField({
    required TextEditingController controller,
    required String hint,
    required Color primaryText,
    required Color secondaryText,
    required Color card,
    required Color divider,
    required bool enabled,
    String? Function(String?)? validator,
    int minLines = 1,
    int maxLines = 1,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      validator: validator,
      minLines: minLines,
      maxLines: maxLines,
      textCapitalization: textCapitalization,
      style: TextStyle(color: primaryText, fontSize: 16),
      cursorColor: _accent,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: secondaryText),
        filled: true,
        fillColor: card,
        contentPadding: const EdgeInsets.all(16),
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
      ),
    );
  }
}
