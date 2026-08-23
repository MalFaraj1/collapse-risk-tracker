/// The four internal roles, mirroring spec §3 and Appendix A exactly.
///
/// The [value] string is what's stored in the Firebase Auth custom claim
/// (`request.auth.token.role`) that the Firestore/Storage security rules
/// check — keep this in sync with the rules and with whatever sets the
/// claim (the `setUserRole` Cloud Function). If you rename anything here,
/// you must rename it in the rules and the Cloud Function too.
enum AppRole {
  callCenter('CALL_CENTER', 'فريق مركز الاتصال'),
  engineering('ENGINEERING', 'الفريق الهندسي'),
  police('POLICE', 'فريق الشرطة'),
  admin('ADMIN', 'مدير النظام');

  const AppRole(this.value, this.label);

  final String value;
  final String label;

  static AppRole? fromClaim(String? value) {
    if (value == null) return null;
    for (final r in AppRole.values) {
      if (r.value == value) return r;
    }
    return null;
  }
}
