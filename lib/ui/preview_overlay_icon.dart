import 'package:flutter/material.dart';

/// Quiet frosted chip so action icons stay readable on file thumbnails.
class PreviewOverlayIcon extends StatelessWidget {
  const PreviewOverlayIcon({
    super.key,
    required this.icon,
    this.destructive = false,
    this.size = 18,
  });

  final IconData icon;
  final bool destructive;
  final double size;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill = isDark
        ? const Color(0xFF111827).withValues(alpha: 0.78)
        : Colors.white.withValues(alpha: 0.9);
    final iconColor = destructive
        ? const Color(0xFFEF4444)
        : isDark
            ? const Color(0xFFF9FAFB)
            : const Color(0xFF1F2937);
    final border = isDark
        ? Colors.white.withValues(alpha: 0.14)
        : const Color(0xFFE5E7EB);

    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.1),
            blurRadius: 5,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Icon(icon, color: iconColor, size: size),
    );
  }
}
