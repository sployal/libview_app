import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../services/client_service.dart';
import '../services/course_service.dart';
import '../screens/no_internet_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    this.needsProfileCompletion = false,
    this.initialTab = 0,
  });

  /// Signed in with Google (or another provider) but missing name / reg number.
  final bool needsProfileCompletion;

  /// 0 = log in, 1 = sign up. Used after onboarding.
  final int initialTab;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _loginFormKey = GlobalKey<FormState>();
  final _signUpFormKey = GlobalKey<FormState>();
  
  // Controllers
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _admissionNumberController = TextEditingController();
  
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  ClientWorkspace? _invitedClient;
  Timer? _inviteLookupTimer;

  @override
  void initState() {
    super.initState();
    final startTab =
        widget.needsProfileCompletion || widget.initialTab == 1 ? 1 : 0;
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: startTab,
    );
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _emailController.addListener(_scheduleInviteLookup);
    if (widget.needsProfileCompletion) {
      _prefillGoogleProfileFields();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _lookupInvitedClient();
        _blockIncompleteNewAccountIfRestricted();
      });
    }

    AuthService.instance.authStateChanges.listen((user) {
      if (user != null) {
        debugPrint('User signed in successfully');
      }
    });
  }

  void _prefillGoogleProfileFields() {
    final user = AuthService.instance.currentUser;
    _emailController.text = user?.email ?? '';
    final displayName = user?.displayName?.trim() ?? '';
    if (displayName.isNotEmpty) {
      _fullNameController.text = displayName;
    }
  }

  @override
  void dispose() {
    _inviteLookupTimer?.cancel();
    _emailController.removeListener(_scheduleInviteLookup);
    _tabController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _fullNameController.dispose();
    _admissionNumberController.dispose();
    super.dispose();
  }

  bool _isValidAdmissionNumber(String admissionNumber) {
    return Course.isValidAdmissionNumber(admissionNumber);
  }

  Future<bool> _ensureSignupAllowed({bool showPopup = true}) async {
    final settings =
        await AuthService.instance.fetchAccountCreationSettings();
    if (settings.allowNewAccounts) return true;
    if (showPopup && mounted) {
      await _showSignupRestrictedDialog(settings.restrictionMessage);
    }
    return false;
  }

  void _scheduleInviteLookup() {
    _inviteLookupTimer?.cancel();
    _inviteLookupTimer = Timer(const Duration(milliseconds: 280), () {
      _lookupInvitedClient();
    });
  }

  Future<void> _lookupInvitedClient() async {
    final client = await ClientService.instance.clientForInviteEmail(
      _emailController.text,
    );
    if (!mounted) return;
    if (client?.id == _invitedClient?.id) return;
    setState(() => _invitedClient = client);
  }

  Future<void> _blockIncompleteNewAccountIfRestricted() async {
    final user = AuthService.instance.currentUser;
    if (user == null) return;
    final hasProfile = await AuthService.instance.profileExists(user.uid);
    if (hasProfile) return;
    final allowed = await _ensureSignupAllowed(showPopup: false);
    if (allowed || !mounted) return;
    final invite = await ClientService.instance.clientForInviteEmail(user.email);
    if (invite != null) return;
    final settings = await AuthService.instance.fetchAccountCreationSettings();
    if (mounted) {
      await _showSignupRestrictedDialog(settings.restrictionMessage);
    }
    await AuthService.instance.signOut();
  }

  Future<void> _onAuthTabChanged(int? value) async {
    if (value == null || _isLoading) return;
    HapticFeedback.selectionClick();
    if (value == 1) {
      final allowed = await _ensureSignupAllowed();
      if (!allowed || !mounted) return;
    }
    _tabController.animateTo(value);
  }

  Future<void> _signUp() async {
    if (!await NoInternetScreen.ensureOnline(context)) return;
    if (!mounted) return;

    final invitedClient = _invitedClient ??
        await ClientService.instance.clientForInviteEmail(
          _emailController.text,
        );
    if (!mounted) return;
    if (invitedClient?.id != _invitedClient?.id) {
      setState(() => _invitedClient = invitedClient);
    }
    if (!_signUpFormKey.currentState!.validate()) return;
    if (!widget.needsProfileCompletion &&
        invitedClient == null &&
        !await _ensureSignupAllowed()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (invitedClient != null) {
        if (widget.needsProfileCompletion) {
          await AuthService.instance.completeStudentProfile(
            fullName: _fullNameController.text.trim(),
          );
          return;
        }
        await AuthService.instance.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          fullName: _fullNameController.text.trim(),
        );
        if (mounted) {
          _showSnackBar('Account created successfully!', success: true);
          _tabController.animateTo(0);
          _fullNameController.clear();
          _admissionNumberController.clear();
          _confirmPasswordController.clear();
          _emailController.clear();
          _passwordController.clear();
          setState(() => _invitedClient = null);
        }
        return;
      }

      // Normalize admission number (convert to uppercase for consistency)
      final normalizedAdmissionNumber = _admissionNumberController.text.trim().toUpperCase();

      final courses = await CourseService.instance.listCourses();
      final matchedCourse = CourseService.instance.matchCourse(
        normalizedAdmissionNumber,
        courses,
      );
      if (matchedCourse == null ||
          !Course.matchesAdmissionDigitLayout(
            normalizedAdmissionNumber,
            matchedCourse.sampleAdmissionNumber,
          )) {
        if (mounted) {
          setState(() => _isLoading = false);
          await _showCourseNotRegisteredDialog();
        }
        return;
      }
      if (matchedCourse.suspended) {
        if (mounted) {
          setState(() => _isLoading = false);
          await _showCourseSuspendedDialog(matchedCourse);
        }
        return;
      }

      // Check if admission number already exists
      final admissionNumberTaken = await AuthService.instance
          .isAdmissionNumberTaken(
            normalizedAdmissionNumber,
            excludeUid: widget.needsProfileCompletion
                ? AuthService.instance.currentUser?.uid
                : null,
          );

      if (admissionNumberTaken) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.white),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Admission number already exists',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFFEF4444),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              margin: const EdgeInsets.all(16),
            ),
          );
        }
        setState(() => _isLoading = false);
        return;
      }

      if (widget.needsProfileCompletion) {
        await AuthService.instance.completeStudentProfile(
          fullName: _fullNameController.text.trim(),
          admissionNumber: normalizedAdmissionNumber,
        );
        return;
      }

      // Sign up user with Firebase
      await AuthService.instance.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        fullName: _fullNameController.text.trim(),
        admissionNumber: normalizedAdmissionNumber,
      );

      if (mounted) {
        _showSnackBar('Account created successfully!', success: true);

        // Switch to login tab and clear form
        _tabController.animateTo(0);
        _fullNameController.clear();
        _admissionNumberController.clear();
        _confirmPasswordController.clear();
        _emailController.clear();
        _passwordController.clear();
      }
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        if (error.code == 'operation-not-allowed') {
          await _showSignupRestrictedDialog(
            error.message ?? AuthService.defaultSignupRestrictionMessage,
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      AuthService.instance.authErrorMessage(error),
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFFEF4444),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              margin: const EdgeInsets.all(16),
            ),
          );
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Unexpected error: $error',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _signIn() async {
    if (!_loginFormKey.currentState!.validate()) return;
    if (!await NoInternetScreen.ensureOnline(context)) return;
    if (!mounted) return;

    setState(() => _isLoading = true);

    try {
      await AuthService.instance.signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    AuthService.instance.authErrorMessage(error),
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Unexpected error: $error',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _forgotPassword() async {
    if (!await NoInternetScreen.ensureOnline(context)) return;
    if (!mounted) return;

    final result = await showDialog<_ResetPasswordResult>(
      context: context,
      builder: (dialogContext) => _ResetPasswordDialog(
        initialEmail: _emailController.text.trim(),
        onAuthError: (message) {
          if (mounted) _showSnackBar(message);
        },
      ),
    );

    if (result == null || !mounted) return;

    _emailController.text = result.email;
    _showSnackBar(
      'If an account exists for that email, a reset link is on its way.',
      success: true,
    );
  }

  Future<void> _signInWithGoogle() async {
    if (!await NoInternetScreen.ensureOnline(context)) return;
    if (!mounted) return;

    setState(() => _isLoading = true);

    try {
      await AuthService.instance.signInWithGoogle();
    } on FirebaseAuthException catch (error) {
      if (mounted) {
        if (error.code == 'operation-not-allowed') {
          await _showSignupRestrictedDialog(
            error.message ?? AuthService.defaultSignupRestrictionMessage,
          );
        } else {
          _showSnackBar(AuthService.instance.authErrorMessage(error));
        }
      }
    } catch (error) {
      final message = error.toString();
      if (message.contains('sign_in_canceled') ||
          message.contains('sign_in_cancelled')) {
        return;
      }
      if (mounted) {
        _showSnackBar('Unexpected error: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _cancelGoogleProfileSetup() async {
    setState(() => _isLoading = true);
    try {
      await AuthService.instance.signOut();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _showSignupRestrictedDialog(String message) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text(
            'Sign up unavailable',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
              color: isDark ? Colors.white : const Color(0xFF1C1C1E),
            ),
          ),
          content: Text(
            message,
            style: const TextStyle(
              fontSize: 15,
              color: Color(0xFF8E8E93),
              height: 1.35,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text(
                'OK',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: _accent,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showCourseSuspendedDialog(Course course) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final topic = course.suspensionTopic.isEmpty
        ? CourseService.defaultSuspensionTopic
        : course.suspensionTopic;
    final message = course.suspensionMessage.isEmpty
        ? CourseService.defaultSuspensionMessage
        : course.suspensionMessage;
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text(
            topic,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
              color: isDark ? Colors.white : const Color(0xFF1C1C1E),
            ),
          ),
          content: Text(
            message,
            style: const TextStyle(
              fontSize: 15,
              color: Color(0xFF8E8E93),
              height: 1.35,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text(
                'OK',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: _accent,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showCourseNotRegisteredDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text(
            'Course not registered',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
              color: isDark ? Colors.white : const Color(0xFF1C1C1E),
            ),
          ),
          content: const Text(
            'Your course is not registered. Contact your faculty rep or the system admin.',
            style: TextStyle(
              fontSize: 15,
              color: Color(0xFF8E8E93),
              height: 1.35,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text(
                'OK',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: _accent,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showSnackBar(String message, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              success ? Icons.check_circle : Icons.error_outline,
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor:
            success ? const Color(0xFF10B981) : const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  static const _accent = Color(0xFF6366F1);
  static const _accentDeep = Color(0xFF8B5CF6);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7);
    final titleColor = isDark ? Colors.white : const Color(0xFF1C1C1E);
    final subtitleColor = isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: background,
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                _accent.withValues(alpha: isDark ? 0.22 : 0.14),
                background,
                background,
              ],
              stops: const [0, 0.38, 1],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 8),
                  child: Column(
                    children: [
                      Hero(
                        tag: 'app_logo',
                        child: Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(22),
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [_accent, _accentDeep],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _accent.withValues(alpha: 0.35),
                                blurRadius: 24,
                                offset: const Offset(0, 12),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(22),
                            child: Image.asset(
                              'assets/app_icon.png',
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(
                                CupertinoIcons.book_fill,
                                size: 36,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Edupal',
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.8,
                          color: titleColor,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Your academic companion',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          color: subtitleColor,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      if (!widget.needsProfileCompletion)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                          child: SizedBox(
                            width: double.infinity,
                            child: CupertinoSlidingSegmentedControl<int>(
                              groupValue: _tabController.index,
                              backgroundColor: isDark
                                  ? const Color(0xFF1C1C1E)
                                  : const Color(0xFFE5E5EA),
                              thumbColor: isDark
                                  ? const Color(0xFF2C2C2E)
                                  : Colors.white,
                              children: {
                                0: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  child: Text(
                                    'Log In',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: -0.2,
                                      color: _tabController.index == 0
                                          ? titleColor
                                          : subtitleColor,
                                    ),
                                  ),
                                ),
                                1: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  child: Text(
                                    'Sign Up',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: -0.2,
                                      color: _tabController.index == 1
                                          ? titleColor
                                          : subtitleColor,
                                    ),
                                  ),
                                ),
                              },
                              onValueChanged: _onAuthTabChanged,
                            ),
                          ),
                        )
                      else
                        Align(
                          alignment: Alignment.centerLeft,
                          child: CupertinoButton(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                            onPressed:
                                _isLoading ? null : _cancelGoogleProfileSetup,
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(CupertinoIcons.chevron_back, size: 18),
                                SizedBox(width: 4),
                                Text('Use a different account'),
                              ],
                            ),
                          ),
                        ),
                      Expanded(
                        child: widget.needsProfileCompletion
                            ? _buildSignUpForm()
                            : TabBarView(
                                controller: _tabController,
                                physics: const NeverScrollableScrollPhysics(),
                                children: [
                                  _buildLoginForm(),
                                  _buildSignUpForm(),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
      child: Form(
        key: _loginFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSectionTitle('Welcome back', 'Sign in to continue your studies'),
            const SizedBox(height: 28),
            _buildTextField(
              controller: _emailController,
              label: 'Email',
              hint: 'your email',
              icon: CupertinoIcons.mail,
              keyboardType: TextInputType.emailAddress,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your email';
                }
                if (!value.contains('@')) {
                  return 'Please enter a valid email';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            _buildTextField(
              controller: _passwordController,
              label: 'Password',
              hint: 'Your password',
              icon: CupertinoIcons.lock,
              obscureText: _obscurePassword,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? CupertinoIcons.eye_slash
                      : CupertinoIcons.eye,
                  color: const Color(0xFF8E8E93),
                  size: 20,
                ),
                onPressed: () {
                  setState(() => _obscurePassword = !_obscurePassword);
                },
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your password';
                }
                return null;
              },
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _isLoading ? null : _forgotPassword,
                style: TextButton.styleFrom(
                  foregroundColor: _accent,
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Forgot password?',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            _buildPrimaryButton(
              label: 'Continue',
              onPressed: _isLoading ? null : _signIn,
            ),
            const SizedBox(height: 22),
            _buildOrDivider(),
            const SizedBox(height: 22),
            _buildGoogleButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildSignUpForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
      child: Form(
        key: _signUpFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSectionTitle(
              widget.needsProfileCompletion ? 'Finish setup' : 'Create account',
              _invitedClient != null
                  ? 'Continue as ${_invitedClient!.name}'
                  : widget.needsProfileCompletion
                      ? 'Add your student details to continue'
                      : 'Join and start your academic journey',
            ),
            const SizedBox(height: 28),

            // Full Name Field
            _buildTextField(
              controller: _fullNameController,
              label: 'Full Name',
              hint: 'First and last name',
              icon: CupertinoIcons.person,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your full name';
                }
                final trimmedValue = value.trim();
                
                // Check if name contains only letters and spaces
                if (!RegExp(r'^[a-zA-Z\s]+$').hasMatch(trimmedValue)) {
                  return 'Name should only contain letters and spaces';
                }
                
                final nameParts = trimmedValue.split(' ').where((part) => part.isNotEmpty).toList();
                if (nameParts.length < 2) {
                  return 'Please enter both first and last name';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Email Field
            _buildTextField(
              controller: _emailController,
              label: 'Email',
              hint: widget.needsProfileCompletion
                  ? 'Signed in with Google'
                  : 'your email',
              icon: CupertinoIcons.mail,
              keyboardType: TextInputType.emailAddress,
              enabled: !widget.needsProfileCompletion,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your email';
                }
                if (!value.contains('@')) {
                  return 'Please enter a valid email';
                }
                return null;
              },
            ),
            if (_invitedClient == null) ...[
              const SizedBox(height: 16),
              _buildTextField(
                controller: _admissionNumberController,
                label: 'Admission Number',
                hint: '',
                icon: CupertinoIcons.number,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter your admission number';
                  }
                  if (!_isValidAdmissionNumber(value)) {
                    return 'Enter your correct admission number';
                  }
                  return null;
                },
              ),
            ],
            if (!widget.needsProfileCompletion) ...[
              const SizedBox(height: 16),

              // Password Field
              _buildTextField(
                controller: _passwordController,
                label: 'Password',
                hint: 'At least 6 characters',
                icon: CupertinoIcons.lock,
                obscureText: _obscurePassword,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? CupertinoIcons.eye_slash
                        : CupertinoIcons.eye,
                    color: const Color(0xFF8E8E93),
                    size: 20,
                  ),
                  onPressed: () {
                    setState(() => _obscurePassword = !_obscurePassword);
                  },
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a password';
                  }
                  if (value.length < 6) {
                    return 'Password must be at least 6 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Confirm Password Field
              _buildTextField(
                controller: _confirmPasswordController,
                label: 'Confirm Password',
                hint: 'Re-enter password',
                icon: CupertinoIcons.lock,
                obscureText: _obscureConfirmPassword,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureConfirmPassword
                        ? CupertinoIcons.eye_slash
                        : CupertinoIcons.eye,
                    color: const Color(0xFF8E8E93),
                    size: 20,
                  ),
                  onPressed: () {
                    setState(
                      () => _obscureConfirmPassword = !_obscureConfirmPassword,
                    );
                  },
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please confirm your password';
                  }
                  if (value != _passwordController.text) {
                    return 'Passwords do not match';
                  }
                  return null;
                },
              ),
            ],
            const SizedBox(height: 22),
            _buildPrimaryButton(
              label: widget.needsProfileCompletion
                  ? 'Complete Sign Up'
                  : 'Create Account',
              onPressed: _isLoading ? null : _signUp,
            ),
            if (!widget.needsProfileCompletion) ...[
              const SizedBox(height: 22),
              _buildOrDivider(),
              const SizedBox(height: 22),
              _buildGoogleButton(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, String subtitle) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.7,
            height: 1.15,
            color: isDark ? Colors.white : const Color(0xFF1C1C1E),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w400,
            letterSpacing: -0.2,
            color: Color(0xFF8E8E93),
          ),
        ),
      ],
    );
  }

  Widget _buildPrimaryButton({
    required String label,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      height: 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(
            colors: [_accent, _accentDeep],
          ),
          boxShadow: [
            BoxShadow(
              color: _accent.withValues(alpha: 0.32),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: _isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Text(
                  label,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildOrDivider() {
    final color = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF3A3A3C)
        : const Color(0xFFD1D1D6);
    return Row(
      children: [
        Expanded(child: Divider(color: color, height: 1)),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'or',
            style: TextStyle(
              color: Color(0xFF8E8E93),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(child: Divider(color: color, height: 1)),
      ],
    );
  }

  Widget _buildGoogleButton() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        onPressed: _isLoading ? null : _signInWithGoogle,
        style: OutlinedButton.styleFrom(
          foregroundColor: isDark ? Colors.white : const Color(0xFF1C1C1E),
          backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          side: BorderSide(
            color: isDark ? const Color(0xFF3A3A3C) : const Color(0xFFD1D1D6),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ColoredGoogleIcon(size: 22),
            SizedBox(width: 12),
            Text(
              'Continue with Google',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    bool enabled = true,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1C1C1E);
    final border = isDark ? const Color(0xFF3A3A3C) : const Color(0xFFD1D1D6);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.1,
              color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
            ),
          ),
        ),
        TextFormField(
          controller: controller,
          enabled: enabled,
          readOnly: !enabled,
          obscureText: obscureText,
          keyboardType: keyboardType,
          validator: validator,
          cursorColor: _accent,
          style: TextStyle(
            color: textColor,
            fontSize: 17,
            fontWeight: FontWeight.w400,
            letterSpacing: -0.3,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
              color: Color(0xFF8E8E93),
              fontWeight: FontWeight.w400,
              fontSize: 17,
              letterSpacing: -0.3,
            ),
            prefixIcon: Icon(icon, color: _accent, size: 20),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: fill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: border),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: border.withValues(alpha: 0.6)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _accent, width: 1.6),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFFF3B30)),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFFF3B30), width: 1.6),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          ),
        ),
      ],
    );
  }
}

class _ResetPasswordResult {
  const _ResetPasswordResult(this.email);
  final String email;
}

class _ResetPasswordDialog extends StatefulWidget {
  const _ResetPasswordDialog({
    required this.initialEmail,
    required this.onAuthError,
  });

  final String initialEmail;
  final ValueChanged<String> onAuthError;

  @override
  State<_ResetPasswordDialog> createState() => _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends State<_ResetPasswordDialog> {
  late final TextEditingController _emailController;
  final _formKey = GlobalKey<FormState>();
  var _sending = false;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendLink() async {
    if (!_formKey.currentState!.validate() || _sending) return;

    setState(() => _sending = true);
    try {
      await AuthService.instance.sendPasswordResetEmail(
        _emailController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(
        _ResetPasswordResult(_emailController.text.trim()),
      );
    } on FirebaseAuthException catch (error) {
      if (error.code == 'user-not-found') {
        if (!mounted) return;
        Navigator.of(context).pop(
          _ResetPasswordResult(_emailController.text.trim()),
        );
        return;
      }
      if (!mounted) return;
      setState(() => _sending = false);
      widget.onAuthError(AuthService.instance.authErrorMessage(error));
    } catch (error) {
      if (!mounted) return;
      setState(() => _sending = false);
      widget.onAuthError('Unexpected error: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AlertDialog(
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(
        'Reset password',
        style: TextStyle(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
          color: isDark ? Colors.white : const Color(0xFF1C1C1E),
        ),
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the email for your account and we will send you a reset link. Check reset link in spam emails section if you don\'t see it in your inbox.',
              style: TextStyle(
                fontSize: 15,
                color: Color(0xFF8E8E93),
                height: 1.35,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _emailController,
              enabled: !_sending,
              keyboardType: TextInputType.emailAddress,
              autofocus: widget.initialEmail.isEmpty,
              cursorColor: _AuthScreenState._accent,
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF1C1C1E),
                fontSize: 17,
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter your email';
                }
                if (!value.contains('@')) {
                  return 'Please enter a valid email';
                }
                return null;
              },
              decoration: InputDecoration(
                hintText: 'your last used email',
                filled: true,
                fillColor: isDark
                    ? const Color(0xFF2C2C2E)
                    : const Color(0xFFF2F2F7),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
          child: const Text(
            'Cancel',
            style: TextStyle(color: Color(0xFF8E8E93)),
          ),
        ),
        TextButton(
          onPressed: _sending ? null : _sendLink,
          child: _sending
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _AuthScreenState._accent,
                    ),
                  ),
                )
              : const Text(
                  'Send link',
                  style: TextStyle(
                    color: _AuthScreenState._accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ],
    );
  }
}

class ColoredGoogleIcon extends StatelessWidget {
  const ColoredGoogleIcon({super.key, this.size = 22});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  static const _blue = Color(0xFF4285F4);
  static const _green = Color(0xFF34A853);
  static const _yellow = Color(0xFFFBBC05);
  static const _red = Color(0xFFEA4335);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.18;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - stroke / 2;
    final arcRect = Rect.fromCircle(center: center, radius: radius);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    paint.color = _red;
    canvas.drawArc(arcRect, -math.pi * 0.22, -math.pi * 0.72, false, paint);

    paint.color = _yellow;
    canvas.drawArc(arcRect, math.pi * 0.95, math.pi * 0.55, false, paint);

    paint.color = _green;
    canvas.drawArc(arcRect, math.pi * 0.38, math.pi * 0.58, false, paint);

    paint.color = _blue;
    canvas.drawArc(arcRect, -math.pi * 0.18, math.pi * 0.52, false, paint);

    final bar = Paint()
      ..color = _blue
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          center.dx - stroke * 0.08,
          center.dy - stroke / 2,
          radius + stroke * 0.08,
          stroke,
        ),
        Radius.circular(stroke / 5),
      ),
      bar,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

