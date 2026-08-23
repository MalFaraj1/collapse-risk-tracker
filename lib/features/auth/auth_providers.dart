import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/roles.dart';

/// Raw FirebaseAuth instance. Kept as a provider (rather than calling
/// `FirebaseAuth.instance` directly all over the app) so it's mockable in
/// tests.
final firebaseAuthProvider = Provider<FirebaseAuth>((ref) => FirebaseAuth.instance);

/// Emits the current [User] (or null) every time sign-in state changes.
/// Everything else auth-related derives from this one stream.
final authStateChangesProvider = StreamProvider<User?>((ref) {
  return ref.watch(firebaseAuthProvider).authStateChanges();
});

/// The signed-in user's role, read from their ID token's custom claims
/// (`request.auth.token.role` — the same claim the Firestore/Storage
/// security rules check). This is deliberately NOT read from a Firestore
/// `users/{uid}` document field, since that would be client-writable and
/// therefore spoofable; custom claims can only be set server-side (see the
/// `setUserRole` Cloud Function).
///
/// Returns null while signed out, while the token is loading, or if a user
/// somehow has no role claim yet (treat that as "no access", not "default
/// access" — see [AppShell]/route guards).
final currentUserRoleProvider = FutureProvider<AppRole?>((ref) async {
  final user = ref.watch(authStateChangesProvider).valueOrNull;
  if (user == null) return null;

  // `false` = don't force-refresh on every rebuild; the app forces a
  // refresh once, right after sign-in, in the login flow (see
  // features/auth/login_screen.dart) since that's the one moment a claim
  // set moments earlier by an Admin might not be on the cached token yet.
  final idTokenResult = await user.getIdTokenResult(false);
  return AppRole.fromClaim(idTokenResult.claims?['role'] as String?);
});
