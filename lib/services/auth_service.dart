import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'client_service.dart';

class AccountCreationSettings {
  const AccountCreationSettings({
    required this.allowNewAccounts,
    required this.restrictionMessage,
  });

  final bool allowNewAccounts;
  final String restrictionMessage;
}

class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  static const defaultSignupRestrictionMessage =
      'New account creation is currently closed. Please contact the system administrator.';

  static const defaultSuspensionMessage =
      'Your account has been suspended. Please contact the system administrator.';

  static const clientRole = 'client';

  static bool isClientRole(String? role) =>
      (role ?? '').toLowerCase().trim() == clientRole;

  /// Web OAuth client ID from google-services.json (needed so Android returns an idToken).
  static const String _googleServerClientId =
      '494545154949-blol1a78c2j59m4keve80opihqn67m5b.apps.googleusercontent.com';

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: const ['email', 'profile'],
    serverClientId: _googleServerClientId,
  );

  User? get currentUser => _auth.currentUser;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Photo from the Google provider, if this account signed in with Google.
  static String? googlePhotoUrlFor(User? user) {
    if (user == null) return null;
    for (final info in user.providerData) {
      if (info.providerId != 'google.com') continue;
      final url = info.photoURL?.trim();
      if (url != null && url.isNotEmpty) return url;
    }
    return user.photoURL?.trim().isNotEmpty == true ? user.photoURL!.trim() : null;
  }

  /// Custom uploaded avatar wins; otherwise the stored or live Google photo.
  static String? displayAvatarUrl({
    String? avatarUrl,
    String? googlePhotoUrl,
    User? user,
  }) {
    final custom = avatarUrl?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    final stored = googlePhotoUrl?.trim();
    if (stored != null && stored.isNotEmpty) return stored;
    return googlePhotoUrlFor(user);
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> profileDocStream(String uid) {
    return _firestore.collection('profiles').doc(uid).snapshots();
  }

  bool isProfileDataComplete(Map<String, dynamic>? data) {
    if (data == null) return false;
    final name = (data['full_name'] as String?)?.trim() ?? '';
    if (name.isEmpty) return false;
    if (isClientRole(data['role'] as String?)) return true;
    final registration = (data['registration_number'] as String?)?.trim() ?? '';
    return registration.isNotEmpty;
  }

  static bool isAccountSuspended(Map<String, dynamic>? data) {
    return data?['suspended'] == true;
  }

  static String suspensionMessageFor(Map<String, dynamic>? data) {
    final message = (data?['suspension_message'] as String?)?.trim() ?? '';
    return message.isEmpty ? defaultSuspensionMessage : message;
  }

  Future<void> suspendAccount({
    required String userId,
    required String message,
  }) async {
    final trimmed = message.trim();
    await _firestore.collection('profiles').doc(userId).update({
      'suspended': true,
      'suspension_message':
          trimmed.isEmpty ? defaultSuspensionMessage : trimmed,
      'suspended_at': FieldValue.serverTimestamp(),
      'suspended_by': currentUser?.email,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> unsuspendAccount(String userId) async {
    await _firestore.collection('profiles').doc(userId).update({
      'suspended': false,
      'suspension_message': FieldValue.delete(),
      'suspended_at': FieldValue.delete(),
      'suspended_by': FieldValue.delete(),
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  /// Deletes a profile and, when the backend is available, the Auth account.
  Future<void> deleteAccount(String userId, {String? email}) async {
    if (userId.isEmpty) {
      throw Exception('Missing user id');
    }
    if (userId == currentUser?.uid) {
      throw Exception('You cannot delete your own account.');
    }

    var accountEmail = email?.trim().toLowerCase() ?? '';
    if (accountEmail.isEmpty) {
      final snap = await _firestore.collection('profiles').doc(userId).get();
      accountEmail =
          (snap.data()?['email'] as String?)?.trim().toLowerCase() ?? '';
    }
    if (accountEmail == 'muigaid91@gmail.com') {
      throw Exception('This account cannot be deleted.');
    }

    final token = await currentUser?.getIdToken();
    if (token != null && token.isNotEmpty) {
      try {
        final dio = Dio(
          BaseOptions(
            baseUrl: 'https://edupal-backend.onrender.com',
            connectTimeout: const Duration(seconds: 30),
            receiveTimeout: const Duration(seconds: 30),
          ),
        );
        await dio.delete(
          '/users/${Uri.encodeComponent(userId)}',
          options: Options(headers: {'Authorization': 'Bearer $token'}),
        );
        return;
      } on DioException catch (e) {
        final status = e.response?.statusCode ?? 0;
        if (status == 400 || status == 403) {
          final data = e.response?.data;
          final message = data is Map
              ? data['error']?.toString()
              : null;
          throw Exception(
            (message == null || message.isEmpty) ? 'Could not delete user' : message,
          );
        }
      }
    }

    await _firestore.collection('profiles').doc(userId).delete();
  }

  /// Auth provider photos keyed by uid (Google photo when the user signed in that way).
  Future<Map<String, String>> fetchAuthPhotoUrls() async {
    final token = await currentUser?.getIdToken();
    if (token == null || token.isEmpty) return {};
    try {
      final dio = Dio(
        BaseOptions(
          baseUrl: 'https://edupal-backend.onrender.com',
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 60),
        ),
      );
      final response = await dio.get(
        '/users/auth-photos',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final raw = response.data is Map ? response.data['photos'] : null;
      if (raw is! Map) return {};
      return {
        for (final entry in raw.entries)
          if (entry.key.toString().isNotEmpty &&
              '${entry.value}'.trim().isNotEmpty)
            entry.key.toString(): '${entry.value}'.trim(),
      };
    } catch (_) {
      return {};
    }
  }

  Future<String> currentRole() async {
    final user = currentUser;
    if (user == null) return 'student';

    final doc = await _firestore.collection('profiles').doc(user.uid).get();
    final role = (doc.data()?['role'] as String?)?.toLowerCase().trim();
    if (role == null || role.isEmpty) return 'student';
    return role;
  }

  Future<bool> isRegistrationNumberTaken(
    String registrationNumber, {
    String? excludeUid,
  }) async {
    final snapshot = await _firestore
        .collection('profiles')
        .where('registration_number', isEqualTo: registrationNumber)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return false;
    if (excludeUid != null && snapshot.docs.first.id == excludeUid) {
      return false;
    }
    return true;
  }

  DocumentReference<Map<String, dynamic>> get _accountCreationDoc =>
      _firestore.collection('config').doc('accountCreation');

  Future<AccountCreationSettings> fetchAccountCreationSettings() async {
    try {
      final doc = await _accountCreationDoc.get();
      final data = doc.data();
      if (data == null) {
        return const AccountCreationSettings(
          allowNewAccounts: true,
          restrictionMessage: defaultSignupRestrictionMessage,
        );
      }

      final message = (data['restrictionMessage'] as String?)?.trim() ?? '';
      return AccountCreationSettings(
        allowNewAccounts: data['allowNewAccounts'] != false,
        restrictionMessage:
            message.isEmpty ? defaultSignupRestrictionMessage : message,
      );
    } catch (_) {
      return const AccountCreationSettings(
        allowNewAccounts: true,
        restrictionMessage: defaultSignupRestrictionMessage,
      );
    }
  }

  Future<void> saveAccountCreationSettings({
    required bool allowNewAccounts,
    required String restrictionMessage,
  }) async {
    final message = restrictionMessage.trim();
    await _accountCreationDoc.set({
      'allowNewAccounts': allowNewAccounts,
      'restrictionMessage':
          message.isEmpty ? defaultSignupRestrictionMessage : message,
      'updated_at': FieldValue.serverTimestamp(),
      'updated_by': currentUser?.email,
    }, SetOptions(merge: true));
  }

  Future<bool> profileExists(String uid) async {
    final doc = await _firestore.collection('profiles').doc(uid).get();
    return doc.exists;
  }

  Future<void> signUp({
    required String email,
    required String password,
    required String fullName,
    String registrationNumber = '',
  }) async {
    final invite = await ClientService.instance.clientForInviteEmail(email);
    if (invite == null) {
      final settings = await fetchAccountCreationSettings();
      if (!settings.allowNewAccounts) {
        throw FirebaseAuthException(
          code: 'operation-not-allowed',
          message: settings.restrictionMessage,
        );
      }
    }

    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    final user = credential.user;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'Account could not be created. Please try again.',
      );
    }

    await _writeSignupProfile(
      uid: user.uid,
      email: email,
      fullName: fullName,
      registrationNumber: registrationNumber,
      invite: invite,
    );
  }

  Future<void> completeStudentProfile({
    required String fullName,
    String registrationNumber = '',
  }) async {
    final user = currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'Please sign in again to finish setting up your account.',
      );
    }

    final email = user.email?.trim();
    if (email == null || email.isEmpty) {
      throw FirebaseAuthException(
        code: 'invalid-email',
        message: 'Your Google account has no email. Please use another account.',
      );
    }

    final invite = await ClientService.instance.clientForInviteEmail(email);
    final docRef = _firestore.collection('profiles').doc(user.uid);
    final existing = await docRef.get();
    if (!existing.exists && invite == null) {
      final settings = await fetchAccountCreationSettings();
      if (!settings.allowNewAccounts) {
        throw FirebaseAuthException(
          code: 'operation-not-allowed',
          message: settings.restrictionMessage,
        );
      }
    }

    await _writeSignupProfile(
      uid: user.uid,
      email: email,
      fullName: fullName,
      registrationNumber: registrationNumber,
      invite: invite,
      existingRole: existing.data()?['role'] as String?,
      googlePhoto: googlePhotoUrlFor(user),
      isNewProfile: !existing.exists,
    );
  }

  Future<void> _writeSignupProfile({
    required String uid,
    required String email,
    required String fullName,
    required String registrationNumber,
    ClientWorkspace? invite,
    String? existingRole,
    String? googlePhoto,
    bool isNewProfile = true,
  }) async {
    final isClient = invite != null;
    await _firestore.collection('profiles').doc(uid).set({
      'full_name': fullName,
      'email': email,
      if (isClient) 'registration_number': '',
      if (!isClient) 'registration_number': registrationNumber,
      'role': isClient ? clientRole : (existingRole ?? 'student'),
      if (isClient) 'client_id': invite.id,
      if (googlePhoto != null) 'google_photo_url': googlePhoto,
      if (isNewProfile) 'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (invite != null) {
      await ClientService.instance.claimInvite(client: invite, uid: uid);
    }
  }

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  /// Returns null if the user cancelled the Google account picker.
  ///
  /// Throws [FirebaseAuthException] with code `operation-not-allowed` when a
  /// brand-new Google account is blocked by system admin settings.
  Future<UserCredential?> signInWithGoogle() async {
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) return null;

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final userCredential = await _auth.signInWithCredential(credential);
    final isNewUser = userCredential.additionalUserInfo?.isNewUser == true;
    final uid = userCredential.user?.uid;
    final hasProfile = uid != null && await profileExists(uid);

    if (isNewUser || !hasProfile) {
      final invite = await ClientService.instance.clientForInviteEmail(
        userCredential.user?.email,
      );
      if (invite == null) {
        final settings = await fetchAccountCreationSettings();
        if (!settings.allowNewAccounts) {
          await _discardIncompleteGoogleSession(
            userCredential.user,
            deleteAuthUser: isNewUser,
          );
          throw FirebaseAuthException(
            code: 'operation-not-allowed',
            message: settings.restrictionMessage,
          );
        }
      }
    }

    await _syncGooglePhotoToProfile(
      userCredential.user,
      photoUrl: googleUser.photoUrl,
    );
    return userCredential;
  }

  /// Writes the Google photo onto an existing profile so other screens can
  /// fall back to it. Does not create a stub profile for unfinished sign-ups.
  Future<void> _syncGooglePhotoToProfile(User? user, {String? photoUrl}) async {
    if (user == null) return;
    final fromGoogle = photoUrl?.trim();
    final photo = (fromGoogle != null && fromGoogle.isNotEmpty)
        ? fromGoogle
        : googlePhotoUrlFor(user);
    if (photo == null) return;
    final ref = _firestore.collection('profiles').doc(user.uid);
    final existing = await ref.get();
    if (!existing.exists) return;
    await ref.set({
      'google_photo_url': photo,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _discardIncompleteGoogleSession(
    User? user, {
    required bool deleteAuthUser,
  }) async {
    if (deleteAuthUser) {
      try {
        await user?.delete();
      } catch (_) {}
    }
    await signOut();
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
    await _auth.signOut();
  }

  String authErrorMessage(FirebaseAuthException error) {
    switch (error.code) {
      case 'email-already-in-use':
        return 'An account with this email already exists.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'weak-password':
        return 'Password must be at least 6 characters.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Invalid email or password.';
      case 'account-exists-with-different-credential':
        return 'This email is already registered. Please log in with your password.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'missing-email':
        return 'Please enter your email address.';
      default:
        return error.message ?? 'Authentication failed. Please try again.';
    }
  }
}
