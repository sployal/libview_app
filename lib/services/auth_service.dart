import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

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

  Stream<DocumentSnapshot<Map<String, dynamic>>> profileDocStream(String uid) {
    return _firestore.collection('profiles').doc(uid).snapshots();
  }

  bool isProfileDataComplete(Map<String, dynamic>? data) {
    if (data == null) return false;
    final name = (data['full_name'] as String?)?.trim() ?? '';
    final registration = (data['registration_number'] as String?)?.trim() ?? '';
    return name.isNotEmpty && registration.isNotEmpty;
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

  Future<void> signUp({
    required String email,
    required String password,
    required String fullName,
    required String registrationNumber,
  }) async {
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

    await _firestore.collection('profiles').doc(user.uid).set({
      'full_name': fullName,
      'email': email,
      'registration_number': registrationNumber,
      'role': 'student',
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> completeStudentProfile({
    required String fullName,
    required String registrationNumber,
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

    final docRef = _firestore.collection('profiles').doc(user.uid);
    final existing = await docRef.get();

    await docRef.set({
      'full_name': fullName,
      'email': email,
      'registration_number': registrationNumber,
      'role': existing.data()?['role'] ?? 'student',
      if (!existing.exists) 'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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

  /// Returns null if the user cancelled the Google account picker.
  Future<UserCredential?> signInWithGoogle() async {
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) return null;

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    return _auth.signInWithCredential(credential);
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
      default:
        return error.message ?? 'Authentication failed. Please try again.';
    }
  }
}
