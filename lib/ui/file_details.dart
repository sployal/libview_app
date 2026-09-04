import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/download_service.dart';
import '../services/google_drive_service.dart';
import 'file_sort.dart';

class FileDetailField {
  const FileDetailField({
    required this.label,
    required this.value,
    this.copyable = false,
  });

  final String label;
  final String value;
  final bool copyable;
}

class FileDetailsInfo {
  const FileDetailsInfo({
    required this.name,
    required this.type,
    required this.sizeLabel,
    required this.dateLabel,
    this.modifiedAt,
    this.createdAt,
    this.thumbnailUrl,
    this.accentColor,
    this.isFolder = false,
    this.fields = const [],
  });

  final String name;
  final String type;
  final String sizeLabel;
  final String dateLabel;
  final DateTime? modifiedAt;
  final DateTime? createdAt;
  final String? thumbnailUrl;
  final Color? accentColor;
  final bool isFolder;
  final List<FileDetailField> fields;

  factory FileDetailsInfo.fromStudyMaterial(
    StudyMaterial file, {
    String? folderName,
  }) {
    final modified = file.modifiedAt ?? FileSort.parseDate(file.date);
    final extension = _extensionOf(file.name);
    return FileDetailsInfo(
      name: file.name,
      type: file.type,
      sizeLabel: _sizeLabel(file.size, file.sizeBytes),
      dateLabel: file.date,
      modifiedAt: modified,
      createdAt: file.createdAt,
      thumbnailUrl: file.thumbnailUrl,
      fields: [
        FileDetailField(label: 'Kind', value: _kindLabel(file.type, extension)),
        if (folderName != null && folderName.trim().isNotEmpty)
          FileDetailField(label: 'Folder', value: folderName.trim()),
        if (extension != null)
          FileDetailField(label: 'Extension', value: '.$extension'),
      ],
    );
  }

  factory FileDetailsInfo.fromSubject(Subject folder) {
    final files = folder.fileCount;
    return FileDetailsInfo(
      name: folder.name,
      type: 'Folder',
      sizeLabel: files == 1 ? '1 file' : '$files files',
      dateLabel: '',
      modifiedAt: folder.modifiedAt,
      createdAt: folder.createdAt,
      isFolder: true,
      accentColor: folder.color,
      fields: [
        const FileDetailField(label: 'Kind', value: 'Folder'),
        if (folder.code.trim().isNotEmpty)
          FileDetailField(label: 'Code', value: folder.code),
      ],
    );
  }

  factory FileDetailsInfo.fromDownload(DownloadItem file) {
    final modified = DateTime.tryParse(file.date) ?? FileSort.parseDate(file.date);
    final extension = _extensionOf(file.name);
    final location = (file.contentUri != null && file.contentUri!.isNotEmpty)
        ? file.contentUri!
        : file.filePath;
    return FileDetailsInfo(
      name: file.name,
      type: file.type,
      sizeLabel: DownloadService.formatFileSize(file.size),
      dateLabel: file.date,
      modifiedAt: modified,
      fields: [
        FileDetailField(label: 'Kind', value: _kindLabel(file.type, extension)),
        if (file.subject.trim().isNotEmpty)
          FileDetailField(label: 'Folder', value: file.subject),
        if (extension != null)
          FileDetailField(label: 'Extension', value: '.$extension'),
        if (location.isNotEmpty)
          FileDetailField(
            label: 'Location',
            value: location,
            copyable: true,
          ),
      ],
    );
  }
}

Future<void> showFileDetailsDialog({
  required BuildContext context,
  required FileDetailsInfo info,
}) {
  HapticFeedback.lightImpact();
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'File details',
    barrierColor: Colors.black.withValues(alpha: 0.52),
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (context, animation, secondaryAnimation) {
      return FileDetailsDialog(info: info);
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
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

class FileDetailsDialog extends StatelessWidget {
  const FileDetailsDialog({super.key, required this.info});

  final FileDetailsInfo info;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = info.accentColor ?? fileTypeColor(info.type);
    final sheet = isDark ? const Color(0xFF151B28) : Colors.white;
    final titleColor =
        isDark ? const Color(0xFFF9FAFB) : const Color(0xFF111827);
    final muted = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
    final card = isDark ? const Color(0xFF1F2937) : const Color(0xFFF3F4F6);
    final dateText = _prettyDate(info.modifiedAt) ?? _readableDate(info.dateLabel);
    final relative = _relativeDate(info.modifiedAt);
    final uploadedText = _prettyDate(info.createdAt);
    final uploadedRelative = _relativeDate(info.createdAt);
    final hasUploaded = uploadedRelative != null || uploadedText != null;

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
                      color: accent.withValues(alpha: 0.18),
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
                      _Header(
                        type: info.type,
                        accent: accent,
                        thumbnailUrl: info.thumbnailUrl,
                        isFolder: info.isFolder,
                      ),
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                info.name,
                                style: TextStyle(
                                  color: titleColor,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  height: 1.25,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _Chip(
                                    label: info.type.toUpperCase(),
                                    color: accent,
                                  ),
                                  _Chip(
                                    label: info.sizeLabel,
                                    color: muted,
                                    outlined: true,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: _StatCard(
                                      icon: info.isFolder
                                          ? Icons.folder_rounded
                                          : Icons.sd_storage_rounded,
                                      label: info.isFolder ? 'Files' : 'Size',
                                      value: info.sizeLabel,
                                      color: accent,
                                      background: card,
                                      titleColor: titleColor,
                                      muted: muted,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _StatCard(
                                      icon: hasUploaded
                                          ? Icons.cloud_upload_rounded
                                          : Icons.schedule_rounded,
                                      label: hasUploaded ? 'Uploaded' : 'Updated',
                                      value: uploadedRelative ??
                                          uploadedText ??
                                          relative ??
                                          dateText,
                                      color: accent,
                                      background: card,
                                      titleColor: titleColor,
                                      muted: muted,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Details',
                                style: TextStyle(
                                  color: titleColor,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              const SizedBox(height: 8),
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: card,
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Column(
                                  children: [
                                    _DetailRow(
                                      label: 'Name',
                                      value: info.name,
                                      muted: muted,
                                      titleColor: titleColor,
                                      copyable: true,
                                    ),
                                    if (uploadedText != null)
                                      _DetailRow(
                                        label: 'Uploaded',
                                        value: uploadedText,
                                        muted: muted,
                                        titleColor: titleColor,
                                      ),
                                    _DetailRow(
                                      label: 'Modified',
                                      value: dateText,
                                      muted: muted,
                                      titleColor: titleColor,
                                    ),
                                    for (final field in info.fields)
                                      if (field.value.trim().isNotEmpty)
                                        _DetailRow(
                                          label: field.label,
                                          value: field.value,
                                          muted: muted,
                                          titleColor: titleColor,
                                          copyable: field.copyable,
                                        ),
                                  ],
                                ),
                              ),
                            ],
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
  const _Header({
    required this.type,
    required this.accent,
    this.thumbnailUrl,
    this.isFolder = false,
  });

  final String type;
  final Color accent;
  final String? thumbnailUrl;
  final bool isFolder;

  @override
  Widget build(BuildContext context) {
    final preview = thumbnailUrl?.trim();
    return SizedBox(
      height: 132,
      width: double.infinity,
      child: Stack(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  accent,
                  Color.lerp(accent, const Color(0xFF111827), 0.28)!,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const SizedBox.expand(),
          ),
          if (preview != null && preview.isNotEmpty) ...[
            Positioned.fill(
              child: Opacity(
                opacity: 0.28,
                child: Image.network(
                  preview.replaceFirst(RegExp(r'=s\d+'), '=s400'),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withValues(alpha: 0.15),
                      Colors.black.withValues(alpha: 0.35),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
          ],
          Positioned(
            right: -18,
            top: -22,
            child: Icon(
              fileTypeIcon(type),
              size: 140,
              color: Colors.white.withValues(alpha: 0.12),
            ),
          ),
          Positioned(
            left: 20,
            bottom: 20,
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.28),
                    ),
                  ),
                  child: Icon(
                    fileTypeIcon(type),
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isFolder ? 'Folder information' : 'File information',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isFolder
                          ? 'Name, files, and more'
                          : 'Name, size, type, and more',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            top: 10,
            right: 10,
            child: IconButton(
              tooltip: 'Close',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.color,
    this.outlined = false,
  });

  final String label;
  final Color color;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: outlined ? Colors.transparent : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: outlined ? color.withValues(alpha: 0.35) : color.withValues(alpha: 0.2),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.background,
    required this.titleColor,
    required this.muted,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final Color background;
  final Color titleColor;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 10),
          Text(
            label,
            style: TextStyle(
              color: muted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: titleColor,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    required this.muted,
    required this.titleColor,
    this.copyable = false,
  });

  final String label;
  final String value;
  final Color muted;
  final Color titleColor;
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 86,
            child: Text(
              label,
              style: TextStyle(
                color: muted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: titleColor,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
          if (copyable)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: value));
                  if (!context.mounted) return;
                  HapticFeedback.selectionClick();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Copied $label'),
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
                child: Icon(Icons.copy_rounded, size: 16, color: muted),
              ),
            ),
        ],
      ),
    );
  }
}

IconData fileTypeIcon(String type) {
  switch (type.toUpperCase()) {
    case 'FOLDER':
      return Icons.folder_rounded;
    case 'PDF':
      return Icons.picture_as_pdf_rounded;
    case 'DOC':
      return Icons.description_rounded;
    case 'PPT':
      return Icons.slideshow_rounded;
    case 'XLS':
      return Icons.table_chart_rounded;
    case 'IMG':
      return Icons.image_rounded;
    default:
      return Icons.insert_drive_file_rounded;
  }
}

Color fileTypeColor(String type) {
  switch (type.toUpperCase()) {
    case 'FOLDER':
      return const Color(0xFF6366F1);
    case 'PDF':
      return const Color(0xFFEF4444);
    case 'DOC':
      return const Color(0xFF3B82F6);
    case 'PPT':
      return const Color(0xFFF59E0B);
    case 'XLS':
      return const Color(0xFF10B981);
    case 'IMG':
      return const Color(0xFF8B5CF6);
    default:
      return const Color(0xFF6366F1);
  }
}

String _sizeLabel(String size, int? sizeBytes) {
  if (size.trim().isNotEmpty && size.toLowerCase() != 'unknown') {
    return size;
  }
  if (sizeBytes != null && sizeBytes > 0) {
    return DownloadService.formatFileSize(sizeBytes);
  }
  return 'Unknown';
}

String? _extensionOf(String name) {
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return null;
  return name.substring(dot + 1).toUpperCase();
}

String _kindLabel(String type, String? extension) {
  switch (type.toUpperCase()) {
    case 'FOLDER':
      return 'Folder';
    case 'PDF':
      return 'PDF document';
    case 'DOC':
      return 'Word document';
    case 'PPT':
      return 'Presentation';
    case 'XLS':
      return 'Spreadsheet';
    case 'IMG':
      return 'Image';
    default:
      return extension == null ? 'File' : '$extension file';
  }
}

String _readableDate(String raw) {
  final value = raw.trim();
  if (value.isEmpty || value.toLowerCase() == 'unknown') return 'Unknown';
  return value;
}

String? _prettyDate(DateTime? date) {
  if (date == null) return null;
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  // Drive/API timestamps are UTC. Format in the device timezone, like the web UI.
  final local = date.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final suffix = local.hour >= 12 ? 'PM' : 'AM';
  return '${months[local.month - 1]} ${local.day}, ${local.year} · $hour:$minute $suffix';
}

String? _relativeDate(DateTime? date) {
  if (date == null) return null;
  final difference = DateTime.now().difference(date.toLocal());
  if (difference.inSeconds < 45) return 'Just now';
  if (difference.inMinutes < 60) return '${difference.inMinutes} min ago';
  if (difference.inHours < 24) {
    return '${difference.inHours} hour${difference.inHours == 1 ? '' : 's'} ago';
  }
  if (difference.inDays == 1) return 'Yesterday';
  if (difference.inDays < 7) return '${difference.inDays} days ago';
  return null;
}
