import 'package:flutter/material.dart';

class AdaptiveLayout {
  AdaptiveLayout._();

  static bool isTablet(BuildContext context) =>
      MediaQuery.sizeOf(context).shortestSide >= 600;

  static EdgeInsets pagePadding(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final tablet = isTablet(context);
    final double side;
    if (width >= 1100) {
      side = ((width - 880) / 2).clamp(32.0, 160.0);
    } else if (tablet) {
      side = 28;
    } else {
      side = 16;
    }
    return EdgeInsets.symmetric(horizontal: side);
  }

  static double bottomClearance(BuildContext context) {
    return MediaQuery.viewPaddingOf(context).bottom +
        kBottomNavigationBarHeight +
        20;
  }

  static int gridCount(double width) {
    if (width >= 1100) return 4;
    if (width >= 720) return 3;
    return 2;
  }

  static int listColumns(double width) {
    return width >= 720 ? 2 : 1;
  }
}

SliverAppBar compactSliverAppBar({
  required Widget title,
  Color? backgroundColor,
  Color? foregroundColor,
  Widget? leading,
  List<Widget>? actions,
  bool automaticallyImplyLeading = false,
}) {
  return SliverAppBar(
    pinned: true,
    floating: true,
    snap: true,
    toolbarHeight: 52,
    titleSpacing: leading == null ? 16 : 4,
    automaticallyImplyLeading: automaticallyImplyLeading,
    centerTitle: false,
    backgroundColor: backgroundColor,
    foregroundColor: foregroundColor,
    surfaceTintColor: Colors.transparent,
    leading: leading,
    title: title,
    actions: actions,
  );
}
