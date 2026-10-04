import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_providers.dart';

/// The signed-in user's uid, or null when nobody is signed in.
///
/// Any long-lived provider that reads from Firestore on the user's behalf
/// should `ref.watch` this, so that it is torn down and rebuilt whenever
/// the signed-in user changes. Without it, a provider created under one
/// account outlives that account's session: when a user signs out, their
/// Firestore listeners are cut off with `permission-denied`, the provider
/// keeps that error as its state, and the NEXT user to sign in on the same
/// page load inherits the dead listener — seeing a wall of "permission
/// denied" even though their own account is perfectly entitled to the data.
///
/// A plain [Provider] only notifies its dependents when the value actually
/// changes, so token refreshes and other auth noise don't cause rebuilds —
/// only a real sign-in, sign-out, or account switch does.
final signedInUidProvider = Provider<String?>((ref) {
  return ref.watch(authStateChangesProvider).valueOrNull?.uid;
});