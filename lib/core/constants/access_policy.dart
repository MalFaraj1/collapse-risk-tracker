import 'roles.dart';

/// The single source of truth for "which role may use which part of the
/// app" (spec §3, Appendix A).
///
/// Before this existed, the rule lived in exactly one place — the sidebar's
/// `allowedRoles` — which only controls what a user can SEE in the menu.
/// It never stopped anyone from opening a screen by typing its URL, and it
/// had no influence on the Dashboard, which showed every queue (and every
/// action button) to every role. Three consumers now read from here, so
/// they can never drift apart:
///
///  * the sidebar        — `nav_items.dart`
///  * the route guard    — `router.dart`  (blocks direct URLs)
///  * the dashboard      — `dashboard_screen.dart` (which queues and
///                          stat cards a role gets)
///
/// This is a UX and navigation layer only. The real enforcement of who can
/// WRITE what remains the Firestore/Storage security rules — a hidden
/// button is not a security boundary, and nothing here replaces the rules.
///
/// To change who can do something, change it HERE, once.
class AccessPolicy {
  AccessPolicy._();

  /// Log a citizen complaint / open a case (مركز الاتصال).
  static const intake = {AppRole.callCenter, AppRole.admin};

  /// Urgency triage — the Engineering team's job (الفريق الهندسي).
  static const triage = {AppRole.engineering, AppRole.admin};

  /// Municipal review and the single decision.
  static const review = {AppRole.engineering, AppRole.admin};

  /// External assessment, restoration study and funding candidates.
  static const assessment = {AppRole.engineering, AppRole.admin};

  /// Evacuation execution (فريق الشرطة).
  static const evacuation = {AppRole.police, AppRole.admin};

  /// Site visits — compliance verification (فريق الشرطة).
  static const siteVisits = {AppRole.police, AppRole.admin};

  /// Demolition orders (فريق الشرطة).
  static const demolition = {AppRole.police, AppRole.admin};

  /// Legacy-warnings import.
  static const imports = {AppRole.admin};

  /// Users, roles, templates, default follow-up periods.
  static const adminSettings = {AppRole.admin};

  /// Route prefix → roles allowed to open it. A route that isn't listed
  /// (dashboard, parcels, reports, notices, login) is open to every
  /// signed-in role.
  static const _routeRoles = <String, Set<AppRole>>{
    '/intake': intake,
    '/triage': triage,
    '/review': review,
    '/assessment': assessment,
    '/evacuation': evacuation,
    '/sitevisits': siteVisits,
    '/demolition': demolition,
    '/import': imports,
    '/admin': adminSettings,
  };

  /// Whether [role] may open [location] (a path such as `/triage/abc123`).
  /// Matches the exact prefix or anything beneath it, so `/triage` and
  /// `/triage/abc123` are both covered but a hypothetical `/triageX` isn't.
  static bool canOpen(String location, AppRole role) {
    for (final entry in _routeRoles.entries) {
      if (location == entry.key || location.startsWith('${entry.key}/')) {
        return entry.value.contains(role);
      }
    }
    return true;
  }
}