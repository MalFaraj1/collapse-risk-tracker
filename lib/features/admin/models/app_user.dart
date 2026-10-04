import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/constants/roles.dart';

/// One entry in the user directory (`users/{uid}`, FR-USR-1).
///
/// The directory — not Firebase custom claims — is the source of truth
/// for a user's role and active flag. Custom claims can only be set by
/// the Admin SDK (a server), which this project does not have; a
/// Firestore document can be managed by an administrator directly from
/// the Admin screen, and Firestore security rules can read it (see the
/// `role()` helper in the rules shipped with this feature). Claims remain
/// a fallback for accounts that predate the directory.
class AppUserProfile {
  const AppUserProfile({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.role,
    required this.active,
    this.createdAt,
  });

  final String uid;
  final String email;
  final String displayName;
  final AppRole? role;
  final bool active;
  final DateTime? createdAt;

  /// Up to two initials for the avatar circle.
  String get initials {
    final parts = displayName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return email.isNotEmpty ? email.substring(0, 1).toUpperCase() : '?';
    if (parts.length == 1) return parts.first.substring(0, 1);
    return parts[0].substring(0, 1) + parts[1].substring(0, 1);
  }

  factory AppUserProfile.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return AppUserProfile(
      uid: doc.id,
      email: data['email'] as String? ?? '',
      displayName: data['displayName'] as String? ?? '',
      role: AppRole.fromClaim(data['role'] as String?),
      active: data['active'] as bool? ?? true,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}