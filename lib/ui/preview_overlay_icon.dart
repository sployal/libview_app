import 'package:flutter/material.dart';

/// Circular scrim so action icons stay readable on any file thumbnail.
class PreviewOverlayIcon extends StatelessWidget {
  const PreviewOverlayIcon({
    super.key,
    required this.icon,
    this.color = Colors.white,
    this.size = 18,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Icon(icon, color: color, size: size),
    );
  }
}
