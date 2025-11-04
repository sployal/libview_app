// TODO Implement this library.
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class VisibilityController {
  static final _supabase = Supabase.instance.client;

  /// Check if current user is an admin
  static Future<bool> isAdmin() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return false;

      final profile = await _supabase
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .single();

      return profile['role'] == 'admin';
    } catch (e) {
      debugPrint('Error checking admin status: $e');
      return false;
    }
  }

  /// Check if current user has a specific role
  static Future<bool> hasRole(String role) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return false;

      final profile = await _supabase
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .single();

      return profile['role'] == role;
    } catch (e) {
      debugPrint('Error checking role: $e');
      return false;
    }
  }

  /// Check if current user has any of the specified roles
  static Future<bool> hasAnyRole(List<String> roles) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return false;

      final profile = await _supabase
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .single();

      return roles.contains(profile['role']);
    } catch (e) {
      debugPrint('Error checking roles: $e');
      return false;
    }
  }

  /// Get current user's role
  static Future<String?> getCurrentUserRole() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return null;

      final profile = await _supabase
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .single();

      return profile['role'] as String?;
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
    final hasAccess = await VisibilityController.hasAnyRole(widget.allowedRoles);
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