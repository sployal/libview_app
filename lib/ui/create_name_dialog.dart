import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/google_drive_service.dart';

enum CreateNameKind { folder, playlist, file }

Future<String?> showCreateNameDialog({
  required BuildContext context,
  required CreateNameKind kind,
  required String title,
  required String confirmLabel,
  String initial = '',
  String fieldLabel = '',
  String fieldHint = '',
  String? subtitle,
  String? helperText,
  List<String> takenNames = const [],
  String takenError = 'That name is already in use',
  bool clashAsFile = false,
  String? extensionFrom,
  TextCapitalization textCapitalization = TextCapitalization.sentences,
}) {
  return showGeneralDialog<String>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.black.withValues(alpha: 0.62),
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return Theme(
        data: Theme.of(context),
        child: _CreateNameDialog(
          kind: kind,
          title: title,
          confirmLabel: confirmLabel,
          initial: initial,
          fieldLabel: fieldLabel,
          fieldHint: fieldHint,
          subtitle: subtitle,
          helperText: helperText,
          takenNames: takenNames,
          takenError: takenError,
          clashAsFile: clashAsFile,
          extensionFrom: extensionFrom,
          textCapitalization: textCapitalization,
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _CreateNameDialog extends StatefulWidget {
  const _CreateNameDialog({
    required this.kind,
    required this.title,
    required this.confirmLabel,
    required this.initial,
    required this.fieldLabel,
    required this.fieldHint,
    required this.subtitle,
    required this.helperText,
    required this.takenNames,
    required this.takenError,
    required this.clashAsFile,
    required this.extensionFrom,
    required this.textCapitalization,
  });

  final CreateNameKind kind;
  final String title;
  final String confirmLabel;
  final String initial;
  final String fieldLabel;
  final String fieldHint;
  final String? subtitle;
  final String? helperText;
  final List<String> takenNames;
  final String takenError;
  final bool clashAsFile;
  final String? extensionFrom;
  final TextCapitalization textCapitalization;

  @override
  State<_CreateNameDialog> createState() => _CreateNameDialogState();
}

class _CreateNameDialogState extends State<_CreateNameDialog>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _controller;
  late final AnimationController _pulse;
  String? _error;

  static const _folderAccent = Color(0xFF0EA5E9);
  static const _folderDeep = Color(0xFF2563EB);
  static const _playlistAccent = Color(0xFFEC4899);
  static const _playlistDeep = Color(0xFF8B5CF6);
  static const _fileAccent = Color(0xFF6366F1);
  static const _fileDeep = Color(0xFF4338CA);

  Color get _accent {
    switch (widget.kind) {
      case CreateNameKind.folder:
        return _folderAccent;
      case CreateNameKind.playlist:
        return _playlistAccent;
      case CreateNameKind.file:
        return _fileAccent;
    }
  }

  Color get _accentDeep {
    switch (widget.kind) {
      case CreateNameKind.folder:
        return _folderDeep;
      case CreateNameKind.playlist:
        return _playlistDeep;
      case CreateNameKind.file:
        return _fileDeep;
    }
  }

  IconData get _icon {
    switch (widget.kind) {
      case CreateNameKind.folder:
        return Icons.create_new_folder_rounded;
      case CreateNameKind.playlist:
        return Icons.library_music_rounded;
      case CreateNameKind.file:
        return Icons.drive_file_rename_outline_rounded;
    }
  }

  IconData get _fieldIcon {
    switch (widget.kind) {
      case CreateNameKind.folder:
        return Icons.folder_rounded;
      case CreateNameKind.playlist:
        return Icons.queue_music_rounded;
      case CreateNameKind.file:
        return Icons.description_rounded;
    }
  }

  String get _subtitle {
    if (widget.subtitle != null) return widget.subtitle!;
    switch (widget.kind) {
      case CreateNameKind.folder:
        return widget.title.toLowerCase().contains('rename')
            ? 'Pick a new name that’s easy to find later.'
            : 'Give this folder a short, clear name.';
      case CreateNameKind.playlist:
        return widget.title.toLowerCase().contains('rename')
            ? 'Update the name of this mix.'
            : 'Name your mix. You can add tracks next.';
      case CreateNameKind.file:
        return 'Keep the same type — only the name changes.';
    }
  }

  String get _hint {
    if (widget.fieldHint.isNotEmpty) return widget.fieldHint;
    if (widget.fieldLabel.isNotEmpty) return widget.fieldLabel;
    switch (widget.kind) {
      case CreateNameKind.folder:
        return 'Folder name';
      case CreateNameKind.playlist:
        return 'Evening mix';
      case CreateNameKind.file:
        return 'File name';
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    _controller.dispose();
    super.dispose();
  }

  bool _isTaken(String typed) {
    if (widget.takenNames.isEmpty) return false;
    final name = widget.extensionFrom == null
        ? typed.trim()
        : GoogleDriveService.fileNameWithExtension(typed, widget.extensionFrom!);
    final clash = widget.clashAsFile
        ? GoogleDriveService.fileNamesClash
        : GoogleDriveService.folderNamesClash;
    return widget.takenNames.any((taken) => clash(taken, name));
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a name to continue');
      return;
    }
    if (_isTaken(name)) {
      setState(() => _error = widget.takenError);
      return;
    }
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(name);
  }

  List<Color> _coverColors(String seed) {
    const gradients = [
      [Color(0xFFEC4899), Color(0xFF8B5CF6)],
      [Color(0xFFF43F5E), Color(0xFFFB7185)],
      [Color(0xFF6366F1), Color(0xFFEC4899)],
      [Color(0xFF0EA5E9), Color(0xFFA855F7)],
      [Color(0xFF14B8A6), Color(0xFF6366F1)],
      [Color(0xFFF59E0B), Color(0xFFEC4899)],
    ];
    var hash = 0;
    for (final code in seed.codeUnits) {
      hash = (hash + code) & 0x7fffffff;
    }
    return gradients[hash % gradients.length];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = isDark ? const Color(0xFF151B2B) : Colors.white;
    final title = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
    final muted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final field = isDark ? const Color(0xFF0F172A) : const Color(0xFFDCE3EE);

    return Center(
      child: Material(
        type: MaterialType.transparency,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              22,
              22,
              22,
              22 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: card,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: _accent.withValues(alpha: 0.28),
                    blurRadius: 40,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        height: 6,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [_accent, _accentDeep],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedBuilder(
                              animation: _pulse,
                              builder: (context, child) {
                                final glow = 10 + (_pulse.value * 10);
                                return ValueListenableBuilder<TextEditingValue>(
                                  valueListenable: _controller,
                                  builder: (context, value, _) {
                                    if (widget.kind == CreateNameKind.playlist) {
                                      final colors = _coverColors(
                                        value.text.trim().isEmpty
                                            ? 'playlist'
                                            : value.text.trim(),
                                      );
                                      final letter = value.text.trim().isEmpty
                                          ? '♪'
                                          : value.text.trim()[0].toUpperCase();
                                      return Container(
                                        width: 84,
                                        height: 84,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(24),
                                          gradient: LinearGradient(
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                            colors: colors,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: colors.first.withValues(
                                                alpha: 0.42,
                                              ),
                                              blurRadius: glow,
                                              spreadRadius: 1,
                                            ),
                                          ],
                                        ),
                                        alignment: Alignment.center,
                                        child: Text(
                                          letter,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 34,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: -1,
                                          ),
                                        ),
                                      );
                                    }
                                    return Container(
                                      width: 78,
                                      height: 78,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [_accent, _accentDeep],
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: _accent.withValues(
                                              alpha: 0.45,
                                            ),
                                            blurRadius: glow,
                                            spreadRadius: 1,
                                          ),
                                        ],
                                      ),
                                      child: child,
                                    );
                                  },
                                );
                              },
                              child: Icon(_icon, color: Colors.white, size: 34),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              widget.title,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: title,
                                letterSpacing: -0.4,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _subtitle,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.4,
                                color: muted,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 20),
                            TextField(
                              controller: _controller,
                              autofocus: true,
                              textCapitalization: widget.textCapitalization,
                              textInputAction: TextInputAction.done,
                              onChanged: (_) {
                                if (_error != null) {
                                  setState(() => _error = null);
                                }
                              },
                              onSubmitted: (_) => _submit(),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                              decoration: InputDecoration(
                                hintText: _hint,
                                helperText: widget.helperText,
                                helperMaxLines: 2,
                                filled: true,
                                fillColor: field,
                                prefixIcon: Icon(_fieldIcon, color: _accent),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide(
                                    color: _accent,
                                    width: 1.6,
                                  ),
                                ),
                                errorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFEF4444),
                                    width: 1.4,
                                  ),
                                ),
                                focusedErrorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFEF4444),
                                    width: 1.6,
                                  ),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                              ),
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 10),
                              Text(
                                _error!,
                                style: const TextStyle(
                                  color: Color(0xFFEF4444),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                            const SizedBox(height: 22),
                            Row(
                              children: [
                                Expanded(
                                  child: TextButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(),
                                    style: TextButton.styleFrom(
                                      foregroundColor: muted,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                    child: const Text(
                                      'Cancel',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  flex: 2,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(16),
                                      gradient: LinearGradient(
                                        colors: [_accent, _accentDeep],
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: _accent.withValues(
                                            alpha: 0.35,
                                          ),
                                          blurRadius: 16,
                                          offset: const Offset(0, 8),
                                        ),
                                      ],
                                    ),
                                    child: TextButton(
                                      onPressed: _submit,
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        widget.confirmLabel,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
