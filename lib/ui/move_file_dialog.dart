import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MoveFileTarget {
  const MoveFileTarget({
    required this.id,
    required this.name,
    this.isMain = false,
  });

  final String id;
  final String name;
  final bool isMain;
}

Future<MoveFileTarget?> showMoveFileDialog({
  required BuildContext context,
  required String fileName,
  required List<MoveFileTarget> targets,
  bool isFolder = false,
}) {
  if (targets.isEmpty) return Future.value(null);
  HapticFeedback.lightImpact();
  return showGeneralDialog<MoveFileTarget>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: isFolder ? 'Move folder' : 'Move file',
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return Theme(
        data: Theme.of(context),
        child: MoveFileDialog(
          fileName: fileName,
          targets: targets,
          isFolder: isFolder,
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.06),
            end: Offset.zero,
          ).animate(curved),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
            child: child,
          ),
        ),
      );
    },
  );
}

class MoveFileDialog extends StatelessWidget {
  const MoveFileDialog({
    super.key,
    required this.fileName,
    required this.targets,
    this.isFolder = false,
  });

  final String fileName;
  final List<MoveFileTarget> targets;
  final bool isFolder;

  static const _accent = Color(0xFF6366F1);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheet = isDark ? const Color(0xFF151B28) : Colors.white;
    final titleColor =
        isDark ? const Color(0xFFF9FAFB) : const Color(0xFF111827);
    final muted = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
    final card = isDark ? const Color(0xFF1F2937) : const Color(0xFFF3F4F6);
    final main = targets.where((target) => target.isMain).toList();
    final folders = targets.where((target) => !target.isMain).toList();

    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
          child: Material(
            color: Colors.transparent,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420, maxHeight: 640),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: sheet,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: _accent.withValues(alpha: 0.18),
                      blurRadius: 36,
                      offset: const Offset(0, 16),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.22),
                      blurRadius: 28,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Header(fileName: fileName, isFolder: isFolder),
                      Flexible(
                        child: ListView(
                          shrinkWrap: true,
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                          children: [
                            Text(
                              'Choose a folder',
                              style: TextStyle(
                                color: muted,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 10),
                            for (final target in main) ...[
                              _FolderTile(
                                target: target,
                                titleColor: titleColor,
                                muted: muted,
                                background: card,
                                isFolder: isFolder,
                              ),
                              if (folders.isNotEmpty) const SizedBox(height: 8),
                            ],
                            if (folders.isNotEmpty) ...[
                              if (main.isNotEmpty) ...[
                                Text(
                                  'Folders here',
                                  style: TextStyle(
                                    color: muted,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],
                              for (final target in folders)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: _FolderTile(
                                    target: target,
                                    titleColor: titleColor,
                                    muted: muted,
                                    background: card,
                                    isFolder: isFolder,
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text(
                              'Cancel',
                              style: TextStyle(
                                color: muted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
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

class _Header extends StatelessWidget {
  const _Header({required this.fileName, required this.isFolder});

  final String fileName;
  final bool isFolder;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 12, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.drive_file_move_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isFolder ? 'Move folder' : 'Move file',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _FolderTile extends StatelessWidget {
  const _FolderTile({
    required this.target,
    required this.titleColor,
    required this.muted,
    required this.background,
    required this.isFolder,
  });

  final MoveFileTarget target;
  final Color titleColor;
  final Color muted;
  final Color background;
  final bool isFolder;

  @override
  Widget build(BuildContext context) {
    final accent = target.isMain ? const Color(0xFF0EA5E9) : const Color(0xFF6366F1);
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          Navigator.of(context).pop(target);
        },
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  target.isMain
                      ? Icons.outbox_rounded
                      : Icons.folder_rounded,
                  color: accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      target.isMain ? 'Main folder' : target.name,
                      style: TextStyle(
                        color: titleColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      target.isMain
                          ? (isFolder
                              ? 'Move back to the main folders'
                              : 'Move this file back to ${target.name}')
                          : 'Move into this folder',
                      style: TextStyle(
                        color: muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: muted),
            ],
          ),
        ),
      ),
    );
  }
}
