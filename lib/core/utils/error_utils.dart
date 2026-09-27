import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Turns a caught exception into a message that actually tells you what
/// went wrong, instead of a generic "please try again."
///
/// [FirebaseException] (thrown by every Firebase plugin — Auth, Firestore,
/// Storage) always carries a `.code` that tells you exactly what happened.
/// The most common ones you'll see across this app:
///   - `permission-denied` → the signed-in user's role claim doesn't allow
///     this read/write, or the security rules weren't published.
///   - `unavailable` / `network-request-failed` → no connectivity.
///   - `failed-precondition` → a required Firestore composite index
///     doesn't exist yet — the exception itself contains a direct link
///     that creates it in one click.
///
/// Shared across every screen that talks to Firebase, rather than each
/// one reimplementing this (as `IntakeScreen` originally did, before this
/// was factored out).
String describeFirebaseError(Object error, String prefix) {
  debugPrint('$prefix: $error'); // always log the full detail to the console
  if (error is FirebaseException) {
    return '$prefix (${error.code})${error.message != null ? ': ${error.message}' : ''}';
  }
  return '$prefix: $error';
}