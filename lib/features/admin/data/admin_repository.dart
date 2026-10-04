import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/firestore_paths.dart';
import '../../../core/constants/roles.dart';
import '../../auth/auth_providers.dart';
import '../../intake/data/intake_repository.dart' show firestoreProvider;
import '../../review/models/decision.dart';
import '../models/app_user.dart';
import '../models/follow_up_settings.dart';
import '../models/notice_template.dart';

final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  return AdminRepository(firestore: ref.watch(firestoreProvider), auth: ref.watch(firebaseAuthProvider));
});

/// The whole user directory, live (FR-USR-1).
final usersProvider = StreamProvider<List<AppUserProfile>>((ref) {
  return ref.watch(adminRepositoryProvider).watchUsers();
});

/// The follow-up period defaults (BR-4). Read by Review & Decision for
/// every role, so this is deliberately a plain stream that falls back to
/// [FollowUpSettings.defaults] wherever it hasn't loaded yet.
final followUpSettingsProvider = StreamProvider<FollowUpSettings>((ref) {
  return ref.watch(adminRepositoryProvider).watchSettings();
});

/// Every custom notice template, keyed by decision-type Firestore value.
final noticeTemplatesProvider = StreamProvider<Map<String, NoticeTemplateState>>((ref) {
  return ref.watch(adminRepositoryProvider).watchTemplates();
});

/// Everything the Admin screen (§7.12, FR-USR-1..3) reads and writes.
class AdminRepository {
  AdminRepository({required this.firestore, required this.auth});

  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  // ---- Users & roles (FR-USR-1, FR-USR-2) ------------------------------------

  Stream<List<AppUserProfile>> watchUsers() {
    return firestore.collection(FirestorePaths.users).snapshots().map((snap) {
      final users = snap.docs.map(AppUserProfile.fromFirestore).toList();
      users.sort((a, b) => a.displayName.compareTo(b.displayName));
      return users;
    });
  }

  /// Registers the signed-in administrator in the directory if they
  /// predate it (their role came from a custom claim). Without this the
  /// Users tab would list everyone except the person looking at it.
  Future<void> ensureOwnProfile() async {
    final user = auth.currentUser;
    if (user == null) return;
    final ref = firestore.collection(FirestorePaths.users).doc(user.uid);
    final snap = await ref.get();
    if (snap.exists) return;
    final email = user.email ?? '';
    await ref.set({
      'email': email,
      'displayName': (user.displayName?.trim().isNotEmpty ?? false) ? user.displayName : email.split('@').first,
      'role': AppRole.admin.value,
      'active': true,
      'createdAt': FieldValue.serverTimestamp(),
      'createdByUid': user.uid,
    });
  }

  /// Creates a real sign-in account AND its directory entry.
  ///
  /// `createUserWithEmailAndPassword` signs the new account in, which
  /// would replace the administrator's own session. So the account is
  /// created on a second, throwaway [FirebaseApp] instance with its own
  /// auth state, then that instance is signed out — the administrator's
  /// session on the main app is never touched.
  Future<void> createUser({
    required String email,
    required String password,
    required String displayName,
    required AppRole role,
  }) async {
    final adminUid = auth.currentUser?.uid ?? '';
    final uid = await _createAuthAccount(email.trim(), password);
    try {
      await firestore.collection(FirestorePaths.users).doc(uid).set({
        'email': email.trim(),
        'displayName': displayName.trim(),
        'role': role.value,
        'active': true,
        'createdAt': FieldValue.serverTimestamp(),
        'createdByUid': adminUid,
      });
    } catch (e) {
      throw StateError(
        'أُنشئ حساب الدخول لكن تعذّر حفظ الدور في الدليل ($e). تحقق من قواعد الأمان ثم عدّل المستخدم من القائمة.',
      );
    }
  }

  Future<String> _createAuthAccount(String email, String password) async {
    const appName = 'user-creation';
    FirebaseApp secondary;
    try {
      secondary = Firebase.app(appName);
    } catch (_) {
      secondary = await Firebase.initializeApp(name: appName, options: Firebase.app().options);
    }
    final secondaryAuth = FirebaseAuth.instanceFor(app: secondary);
    try {
      final cred = await secondaryAuth.createUserWithEmailAndPassword(email: email, password: password);
      return cred.user!.uid;
    } finally {
      await secondaryAuth.signOut();
    }
  }

  Future<void> updateUser(String uid, {required String displayName, required AppRole role, required bool active}) {
    return firestore.collection(FirestorePaths.users).doc(uid).update({
      'displayName': displayName.trim(),
      'role': role.value,
      'active': active,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> sendPasswordReset(String email) => auth.sendPasswordResetEmail(email: email);

  // ---- Follow-up periods (BR-4, FR-USR-3) ------------------------------------

  Stream<FollowUpSettings> watchSettings() {
    return firestore
        .collection(FirestorePaths.settings)
        .doc(FollowUpSettings.docId)
        .snapshots()
        .map((doc) => FollowUpSettings.fromMap(doc.data()));
  }

  Future<void> saveSettings(FollowUpSettings settings) {
    return firestore.collection(FirestorePaths.settings).doc(FollowUpSettings.docId).set({
      ...settings.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedByUid': auth.currentUser?.uid ?? '',
    });
  }

  // ---- Notice templates (FR-USR-3, FR-ACT-2) ---------------------------------

  Stream<Map<String, NoticeTemplateState>> watchTemplates() {
    return firestore.collection(FirestorePaths.noticeTemplates).snapshots().map((snap) {
      return {
        for (final doc in snap.docs)
          doc.id: NoticeTemplateState(
            version: (doc.data()['version'] as num?)?.toInt() ?? NoticeTemplates.builtInVersion,
            body: doc.data()['body'] as String? ?? '',
            updatedAt: (doc.data()['updatedAt'] as Timestamp?)?.toDate(),
          ),
      };
    });
  }

  /// Saves an edit as the NEXT version number — never overwrites a
  /// previous one. Runs in a transaction so two administrators saving at
  /// once can't both claim the same version number.
  Future<int> saveTemplate(DecisionAction action, String body) {
    final ref = firestore.collection(FirestorePaths.noticeTemplates).doc(action.firestoreValue);
    final uid = auth.currentUser?.uid ?? '';
    return firestore.runTransaction<int>((tx) async {
      final snap = await tx.get(ref);
      final current = (snap.data()?['version'] as num?)?.toInt() ?? NoticeTemplates.builtInVersion;
      final next = current + 1;
      tx.set(ref, {
        'body': body,
        'version': next,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedByUid': uid,
      });
      tx.set(ref.collection('versions').doc('$next'), {
        'version': next,
        'body': body,
        'savedAt': FieldValue.serverTimestamp(),
        'savedByUid': uid,
      });
      return next;
    });
  }

  /// Saved versions, newest first. The built-in version 1 is never
  /// stored, so it isn't included — the screen adds it itself.
  Future<List<NoticeTemplateVersion>> getVersions(DecisionAction action) async {
    final snap = await firestore
        .collection(FirestorePaths.noticeTemplates)
        .doc(action.firestoreValue)
        .collection('versions')
        .orderBy('version', descending: true)
        .get();
    return [
      for (final d in snap.docs)
        NoticeTemplateVersion(
          version: (d.data()['version'] as num?)?.toInt() ?? 0,
          body: d.data()['body'] as String? ?? '',
          savedAt: (d.data()['savedAt'] as Timestamp?)?.toDate(),
        ),
    ];
  }
}