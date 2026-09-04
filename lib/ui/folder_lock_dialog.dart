import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum FolderLockDialogMode { lock, unlock, enter }

Future<String?> showFolderLockDialog({
  required BuildContext context,
  required FolderLockDialogMode mode,
  required String folderName,
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
        child: FolderLockDialog(mode: mode, folderName: folderName),
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

class FolderLockDialog extends StatefulWidget {
  const FolderLockDialog({
    super.key,
    required this.mode,
    required this.folderName,
  });

  final FolderLockDialogMode mode;
  final String folderName;

  @override
  State<FolderLockDialog> createState() => _FolderLockDialogState();
}

class _FolderLockDialogState extends State<FolderLockDialog>
    with SingleTickerProviderStateMixin {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _error;
  late final AnimationController _pulse;

  static const _lockAccent = Color(0xFF6366F1);
  static const _unlockAccent = Color(0xFF10B981);
  static const _enterAccent = Color(0xFFF59E0B);

  Color get _accent {
    switch (widget.mode) {
      case FolderLockDialogMode.lock:
        return _lockAccent;
      case FolderLockDialogMode.unlock:
        return _unlockAccent;
      case FolderLockDialogMode.enter:
        return _enterAccent;
    }
  }

  Color get _accentDeep {
    switch (widget.mode) {
      case FolderLockDialogMode.lock:
        return const Color(0xFF4338CA);
      case FolderLockDialogMode.unlock:
        return const Color(0xFF047857);
      case FolderLockDialogMode.enter:
        return const Color(0xFFD97706);
    }
  }

  IconData get _icon {
    switch (widget.mode) {
      case FolderLockDialogMode.lock:
        return Icons.lock_rounded;
      case FolderLockDialogMode.unlock:
        return Icons.lock_open_rounded;
      case FolderLockDialogMode.enter:
        return Icons.lock_person_rounded;
    }
  }

  String get _title {
    switch (widget.mode) {
      case FolderLockDialogMode.lock:
        return 'Lock this folder';
      case FolderLockDialogMode.unlock:
        return 'Unlock folder';
      case FolderLockDialogMode.enter:
        return 'Folder is locked';
    }
  }

  String get _subtitle {
    switch (widget.mode) {
      case FolderLockDialogMode.lock:
        return 'Set a password to keep “${widget.folderName}” private. Anyone opening it will need this password.';
      case FolderLockDialogMode.unlock:
        return 'Enter the password to remove the lock from “${widget.folderName}”.';
      case FolderLockDialogMode.enter:
        return 'Enter the password to open “${widget.folderName}”.';
    }
  }

  String get _confirmLabel {
    switch (widget.mode) {
      case FolderLockDialogMode.lock:
        return 'Lock folder';
      case FolderLockDialogMode.unlock:
        return 'Remove lock';
      case FolderLockDialogMode.enter:
        return 'Open folder';
    }
  }

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    _password.dispose();
    _confirm.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _submit() {
    final password = _password.text;
    if (password.length < 4) {
      setState(() => _error = 'Use at least 4 characters');
      return;
    }
    if (password.length > 64) {
      setState(() => _error = 'Password is too long');
      return;
    }
    if (widget.mode == FolderLockDialogMode.lock &&
        password != _confirm.text) {
      setState(() => _error = 'Passwords do not match');
      return;
    }
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(password);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = isDark ? const Color(0xFF151B2B) : Colors.white;
    final title = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
    final muted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final field = isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9);

    return Center(
      child: Material(
        color: Colors.transparent,
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
                                      color: _accent.withValues(alpha: 0.45),
                                      blurRadius: glow,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                                child: child,
                              );
                            },
                            child: Icon(_icon, color: Colors.white, size: 34),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _title,
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
                          _PasswordField(
                            controller: _password,
                            focusNode: _passwordFocus,
                            fill: field,
                            accent: _accent,
                            obscure: _obscurePassword,
                            hint: widget.mode == FolderLockDialogMode.lock
                                ? 'Create password'
                                : 'Enter password',
                            onToggle: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                            onChanged: (_) {
                              if (_error != null) {
                                setState(() => _error = null);
                              }
                            },
                            onSubmitted: (_) {
                              if (widget.mode == FolderLockDialogMode.lock) {
                                FocusScope.of(context).nextFocus();
                              } else {
                                _submit();
                              }
                            },
                          ),
                          if (widget.mode == FolderLockDialogMode.lock) ...[
                            const SizedBox(height: 12),
                            _PasswordField(
                              controller: _confirm,
                              fill: field,
                              accent: _accent,
                              obscure: _obscureConfirm,
                              hint: 'Confirm password',
                              onToggle: () {
                                setState(() {
                                  _obscureConfirm = !_obscureConfirm;
                                });
                              },
                              onChanged: (_) {
                                if (_error != null) {
                                  setState(() => _error = null);
                                }
                              },
                              onSubmitted: (_) => _submit(),
                            ),
                          ],
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
                                  onPressed: () => Navigator.of(context).pop(),
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
                                        color: _accent.withValues(alpha: 0.35),
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
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                    child: Text(
                                      _confirmLabel,
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

class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.controller,
    required this.fill,
    required this.accent,
    required this.obscure,
    required this.hint,
    required this.onToggle,
    required this.onChanged,
    required this.onSubmitted,
    this.focusNode,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final Color fill;
  final Color accent;
  final bool obscure;
  final String hint;
  final VoidCallback onToggle;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscure,
      autofocus: focusNode != null,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      textInputAction:
          focusNode != null ? TextInputAction.next : TextInputAction.done,
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: fill,
        prefixIcon: Icon(Icons.key_rounded, color: accent),
        suffixIcon: IconButton(
          onPressed: onToggle,
          icon: Icon(
            obscure
                ? Icons.visibility_rounded
                : Icons.visibility_off_rounded,
            color: accent.withValues(alpha: 0.8),
          ),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: accent, width: 1.6),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }
}
