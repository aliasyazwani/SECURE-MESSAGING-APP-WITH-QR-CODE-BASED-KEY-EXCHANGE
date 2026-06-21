// ============================================================
//  services/auth_service.dart
//  Handles Firebase Authentication and Firestore user profile.
//
//  2-FACTOR AUTH FLOW:
//    Step 1 — Firebase email/password  (this service)
//    Step 2 — TOTP authenticator       (TotpService + SecureStorageService)
//
//  SECURITY NOTES:
//  - /users/{uid} Firestore stores ONLY safe metadata.
//  - TOTP secret is NEVER sent to Firestore.
//  - markTotpEnabled() writes only totpEnabled: true + updatedAt.
// ============================================================

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Current Firebase user (null if not logged in).
  User? get currentUser => _auth.currentUser;

  /// Stream of auth state changes.
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // ── Registration ───────────────────────────────────────────

  /// Register with email and password.
  /// Creates a Firestore user document with public info only.
  /// totpEnabled starts as false; set to true after TOTP enrolment.
  Future<UserModel> register({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    final user = credential.user!;
    await user.updateDisplayName(displayName);

    final now = DateTime.now();
    final userModel = UserModel(
      uid: user.uid,
      email: email.trim().toLowerCase(),
      displayName: displayName,
      totpEnabled: false,
      createdAt: now,
      updatedAt: now,
    );

    await _firestore
        .collection('users')
        .doc(user.uid)
        .set(userModel.toMap());

    return userModel;
  }

  // ── Login (Step 1 of 2) ────────────────────────────────────

  /// Step 1: Firebase email/password sign-in.
  /// After this succeeds, caller must complete TOTP (Step 2).
  Future<User> loginWithEmailPassword({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    return credential.user!;
  }

  // ── TOTP Enablement ────────────────────────────────────────

  /// Mark TOTP as enabled for the given user in Firestore.
  /// Called only after the TOTP code has been successfully verified.
  /// SECURITY: The TOTP secret itself is NOT written here.
  Future<void> markTotpEnabled(String uid) async {
    await _firestore.collection('users').doc(uid).update({
      'totpEnabled': true,
      'updatedAt': DateTime.now(),
    });
  }

  // ── Sign Out ───────────────────────────────────────────────

  Future<void> signOut() async {
    await _auth.signOut();
  }

  // ── User Profile ───────────────────────────────────────────

  /// Fetch public user data from Firestore by UID.
  Future<UserModel?> getUserById(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return UserModel.fromMap(doc.data()!);
  }

  /// Check whether the current user has completed TOTP setup.
  /// Returns false if user document not found or totpEnabled is absent.
  Future<bool> isTotpEnabled() async {
    final user = currentUser;
    if (user == null) return false;
    final model = await getUserById(user.uid);
    return model?.totpEnabled ?? false;
  }

  /// Search for a user by email (for future chat session initiation).
  Future<UserModel?> searchUserByEmail(String email) async {
    final query = await _firestore
        .collection('users')
        .where('email', isEqualTo: email.trim().toLowerCase())
        .limit(1)
        .get();

    if (query.docs.isEmpty) return null;
    return UserModel.fromMap(query.docs.first.data());
  }

  /// Get current user's Firestore model.
  Future<UserModel?> getCurrentUserModel() async {
    final user = currentUser;
    if (user == null) return null;
    return getUserById(user.uid);
  }
}
