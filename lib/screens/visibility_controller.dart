import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class VisibilityController {
  /// Check if current user is an admin
  static Future<bool> isAdmin() async {
    try {
      final role = await AuthService.instance.currentRole();
      return role == 'admin';
    } catch (e) {
      debugPrint('Error checking admin status: $e');
      return false;
    }
  }

  /// Check if current user has a specific role
  static Future<bool> hasRole(String role) async {
    try {
      final current = await AuthService.instance.currentRole();
      return current == role.toLowerCase().trim();
    } catch (e) {
      debugPrint('Error checking role: $e');
      return false;
    }
  }

  /// Check if current user has any of the specified roles
  static Future<bool> hasAnyRole(List<String> roles) async {
    try {
      final current = await AuthService.instance.currentRole();
      final normalized = roles.map((r) => r.toLowerCase().trim()).toList();
      return normalized.contains(current);
    } catch (e) {
      debugPrint('Error checking roles: $e');
      return false;
    }
  }

  /// Get current user's role
  static Future<String?> getCurrentUserRole() async {
    try {
      if (AuthService.instance.currentUser == null) return null;
      return AuthService.instance.currentRole();
    } catch (e) {
      debugPrint('Error getting user role: $e');
      return null;
    }
  }
}

/// Widget that conditionally shows content based on user role
class RoleBasedWidget extends StatefulWidget {
  final List<String> allowedRoles;
  final Widget child;
  final Widget? fallback;

  const RoleBasedWidget({
    super.key,
    required this.allowedRoles,
    required this.child,
    this.fallback,
  });

  @override
  State<RoleBasedWidget> createState() => _RoleBasedWidgetState();
}

class _RoleBasedWidgetState extends State<RoleBasedWidget> {
  bool _isVisible = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkVisibility();
  }

  Future<void> _checkVisibility() async {
    final hasAccess =
        await VisibilityController.hasAnyRole(widget.allowedRoles);
    if (mounted) {
      setState(() {
        _isVisible = hasAccess;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox.shrink();
    }

    if (_isVisible) {
      return widget.child;
    }

    return widget.fallback ?? const SizedBox.shrink();
  }
}
