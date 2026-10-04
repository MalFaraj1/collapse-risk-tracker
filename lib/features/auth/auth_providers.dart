import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/firestore_paths.dart';
import '../../core/constants/roles.dart';
import '../admin/models/app_user.dart';

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) => FirebaseAuth.instance);

final authStateChangesProvider = StreamProvider<User?>((ref) {
  return ref.watch(firebaseAuthProvider).authStateChanges();
});

/// The role stamped on the sign-in token (a Firebase custom claim). Only
/// a fallback now — see [currentUserRoleProvider].
final _claimRoleProvider = FutureProvider<AppRole?>((ref) async {
  final user = ref.watch(authStateChangesProvider).valueOrNull;
  if (user == null) return null;
  final idTokenResult = await user.getIdTokenResult(false);
  return AppRole.fromClaim(idTokenResult.claims?['role'] as String?);
});

/// The signed-in user's directory entry (`users/{uid}`), live — so an
/// administrator deactivating or re-roling someone takes effect on that
/// person's screen immediately, without them signing out and back in.
/// Null when the account has no directory entry.
final currentUserProfileProvider = StreamProvider<AppUserProfile?>((ref) {
  final user = ref.watch(authStateChangesProvider).valueOrNull;
  if (user == null) return Stream.value(null);
  return FirebaseFirestore.instance
      .collection(FirestorePaths.users)
      .doc(user.uid)
      .snapshots()
      .map((doc) => doc.exists ? AppUserProfile.fromFirestore(doc) : null);
});

/// The signed-in user's effective role (FR-USR-2).
///
/// Resolution order:
///  1. A directory entry, if one exists — its role, or null (no access)
///     if the account is deactivated.
///  2. Otherwise the custom claim, so accounts that predate the directory
///     (including the original administrator) keep working untouched.
///
/// If the directory can't be read at all (for instance the updated
/// security rules haven't been published yet), this falls back to the
/// claim instead of failing — a configuration gap must never lock every
/// user out of the application.
final currentUserRoleProvider = Provider<AsyncValue<AppRole?>>((ref) {
  final user = ref.watch(authStateChangesProvider).valueOrNull;
  if (user == null) return const AsyncData<AppRole?>(null);

  final claim = ref.watch(_claimRoleProvider);
  final profile = ref.watch(currentUserProfileProvider);

  if (profile.hasError) return claim;
  if (profile.isLoading) return const AsyncLoading<AppRole?>();

  final entry = profile.valueOrNull;
  if (entry != null) return AsyncData<AppRole?>(entry.active ? entry.role : null);
  return claim;
});