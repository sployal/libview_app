import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum FileSortMode {
  nameAz,
  nameZa,
  dateRecent,
  dateOldest,
  sizeLargest,
  sizeSmallest,
  typeAz,
  typeZa,
}

extension FileSortModeX on FileSortMode {
  String get storageValue => name;

  String get label {
    switch (this) {
      case FileSortMode.nameAz:
        return 'Name · A to Z';
      case FileSortMode.nameZa:
        return 'Name · Z to A';
      case FileSortMode.dateRecent:
        return 'Date · Recent';
      case FileSortMode.dateOldest:
        return 'Date · Oldest';
      case FileSortMode.sizeLargest:
        return 'Size · Largest';
      case FileSortMode.sizeSmallest:
        return 'Size · Smallest';
      case FileSortMode.typeAz:
        return 'Type · A to Z';
      case FileSortMode.typeZa:
        return 'Type · Z to A';
    }
  }

  static FileSortMode fromStorage(String? value, {FileSortMode fallback = FileSortMode.nameAz}) {
    return FileSortMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => fallback,
    );
  }
}

class FileSort {
  static int parseSizeBytes(String? raw) {
    if (raw == null) return 0;
    final compact = raw.trim().toUpperCase().replaceAll(' ', '');
    if (compact.isEmpty || compact == 'UNKNOWN') return 0;
    final match = RegExp(r'^([\d.]+)(B|KB|MB|GB)?$').firstMatch(compact);
    if (match == null) return int.tryParse(compact) ?? 0;
    final amount = double.tryParse(match.group(1)!) ?? 0;
    switch (match.group(2)) {
      case 'KB':
        return (amount * 1024).round();
      case 'MB':
        return (amount * 1024 * 1024).round();
      case 'GB':
        return (amount * 1024 * 1024 * 1024).round();
      default:
        return amount.round();
    }
  }

  static DateTime? parseDate(String? raw) {
    if (raw == null) return null;
    final value = raw.trim();
    if (value.isEmpty || value.toLowerCase() == 'unknown') return null;
    final lower = value.toLowerCase();
    final now = DateTime.now();
    if (lower == 'just now' || lower == 'today') {
      return DateTime(now.year, now.month, now.day);
    }
    if (lower == 'yesterday') {
      return DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1));
    }
    final daysAgo = RegExp(r'^(\d+)\s+days?\s+ago$').firstMatch(lower);
    if (daysAgo != null) {
      final days = int.tryParse(daysAgo.group(1)!) ?? 0;
      return now.subtract(Duration(days: days));
    }
    final slash = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(value);
    if (slash != null) {
      return DateTime(
        int.parse(slash.group(3)!),
        int.parse(slash.group(2)!),
        int.parse(slash.group(1)!),
      );
    }
    return DateTime.tryParse(value);
  }

  static List<T> apply<T>(
    Iterable<T> items, {
    required FileSortMode mode,
    required String Function(T item) nameOf,
    String Function(T item)? typeOf,
    int Function(T item)? sizeOf,
    DateTime? Function(T item)? dateOf,
  }) {
    final list = [...items];
    int cmpName(T a, T b) =>
        nameOf(a).toLowerCase().compareTo(nameOf(b).toLowerCase());
    int cmpType(T a, T b) {
      final type = (typeOf?.call(a) ?? '').toLowerCase().compareTo(
            (typeOf?.call(b) ?? '').toLowerCase(),
          );
      return type != 0 ? type : cmpName(a, b);
    }

    int cmpSize(T a, T b) {
      final size = (sizeOf?.call(a) ?? 0).compareTo(sizeOf?.call(b) ?? 0);
      return size != 0 ? size : cmpName(a, b);
    }

    int cmpDate(T a, T b) {
      final da = dateOf?.call(a) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final db = dateOf?.call(b) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final date = da.compareTo(db);
      return date != 0 ? date : cmpName(a, b);
    }

    switch (mode) {
      case FileSortMode.nameAz:
        list.sort(cmpName);
      case FileSortMode.nameZa:
        list.sort((a, b) => cmpName(b, a));
      case FileSortMode.dateRecent:
        list.sort((a, b) => cmpDate(b, a));
      case FileSortMode.dateOldest:
        list.sort(cmpDate);
      case FileSortMode.sizeLargest:
        list.sort((a, b) => cmpSize(b, a));
      case FileSortMode.sizeSmallest:
        list.sort(cmpSize);
      case FileSortMode.typeAz:
        list.sort(cmpType);
      case FileSortMode.typeZa:
        list.sort((a, b) => cmpType(b, a));
    }
    return list;
  }
}

Future<FileSortMode?> showFileSortSheet({
  required BuildContext context,
  required FileSortMode selected,
}) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<FileSortMode>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (context) => FileSortSheet(selected: selected),
  );
}

class FileSortSheet extends StatelessWidget {
  const FileSortSheet({super.key, required this.selected});

  final FileSortMode selected;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheet = isDark ? const Color(0xFF151B28) : Colors.white;
    final titleColor = isDark ? const Color(0xFFF9FAFB) : const Color(0xFF111827);
    final muted = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
    final card = isDark ? const Color(0xFF1F2937) : const Color(0xFFF3F4F6);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: sheet,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 28,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: muted.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.sort_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Sort files',
                            style: TextStyle(
                              color: titleColor,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Choose how this folder is ordered',
                            style: TextStyle(
                              color: muted,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _SortGroup(
                  icon: Icons.sort_by_alpha_rounded,
                  iconColor: const Color(0xFF6366F1),
                  title: 'Name',
                  card: card,
                  titleColor: titleColor,
                  muted: muted,
                  options: const [
                    (FileSortMode.nameAz, 'A to Z'),
                    (FileSortMode.nameZa, 'Z to A'),
                  ],
                  selected: selected,
                ),
                const SizedBox(height: 10),
                _SortGroup(
                  icon: Icons.schedule_rounded,
                  iconColor: const Color(0xFF0EA5E9),
                  title: 'Date modified',
                  card: card,
                  titleColor: titleColor,
                  muted: muted,
                  options: const [
                    (FileSortMode.dateRecent, 'Recent first'),
                    (FileSortMode.dateOldest, 'Oldest first'),
                  ],
                  selected: selected,
                ),
                const SizedBox(height: 10),
                _SortGroup(
                  icon: Icons.sd_storage_rounded,
                  iconColor: const Color(0xFF10B981),
                  title: 'File size',
                  card: card,
                  titleColor: titleColor,
                  muted: muted,
                  options: const [
                    (FileSortMode.sizeLargest, 'Largest'),
                    (FileSortMode.sizeSmallest, 'Smallest'),
                  ],
                  selected: selected,
                ),
                const SizedBox(height: 10),
                _SortGroup(
                  icon: Icons.category_rounded,
                  iconColor: const Color(0xFFF59E0B),
                  title: 'Type',
                  card: card,
                  titleColor: titleColor,
                  muted: muted,
                  options: const [
                    (FileSortMode.typeAz, 'A to Z'),
                    (FileSortMode.typeZa, 'Z to A'),
                  ],
                  selected: selected,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SortGroup extends StatelessWidget {
  const _SortGroup({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.card,
    required this.titleColor,
    required this.muted,
    required this.options,
    required this.selected,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final Color card;
  final Color titleColor;
  final Color muted;
  final List<(FileSortMode, String)> options;
  final FileSortMode selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: TextStyle(
                  color: titleColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < options.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: _SortChip(
                    label: options[i].$2,
                    selected: selected == options[i].$1,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      Navigator.pop(context, options[i].$1);
                    },
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  const _SortChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFF6366F1) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? const Color(0xFF6366F1)
                  : const Color(0xFF6366F1).withValues(alpha: 0.22),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (selected) ...[
                const Icon(Icons.check_rounded, color: Colors.white, size: 16),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : const Color(0xFF6366F1),
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
