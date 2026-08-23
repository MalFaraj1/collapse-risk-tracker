import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/widgets/app_shell.dart';
import '../features/auth/auth_providers.dart';
import '../features/auth/login_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/parcels/parcels_list_screen.dart';
import '../features/parcels/parcel_detail_screen.dart';
import '../features/intake/intake_screen.dart';
import '../features/triage/triage_screen.dart';
import '../features/review/review_screen.dart';
import '../features/notices/notice_preview_screen.dart';
import '../features/evacuation/evacuation_screen.dart';
import '../features/sitevisits/sitevisit_screen.dart';
import '../features/assessment/assessment_screen.dart';
import '../features/demolition/demolition_screen.dart';
import '../features/imports/import_screen.dart';
import '../features/reports/reports_screen.dart';
import '../features/admin/admin_screen.dart';

/// Wraps a feature screen with [AppShell] (sidebar + top bar). Every
/// authenticated route uses this — only `/login` doesn't.
Widget _shelled(String route, Widget child) => AppShell(currentRoute: route, child: child);

final routerProvider = Provider<GoRouter>((ref) {
  // Re-evaluate redirect logic whenever auth state changes — this is what
  // makes signing out immediately kick the user back to /login without a
  // manual navigation call anywhere else in the app.
  final authNotifier = _AuthRefreshNotifier(ref);

  return GoRouter(
    initialLocation: '/dashboard',
    refreshListenable: authNotifier,
    redirect: (context, state) {
      final isSignedIn = ref.read(authStateChangesProvider).valueOrNull != null;
      final isLoggingIn = state.matchedLocation == '/login';

      if (!isSignedIn && !isLoggingIn) return '/login';
      if (isSignedIn && isLoggingIn) return '/dashboard';
      return null; // no redirect needed
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),

      GoRoute(
        path: '/dashboard',
        builder: (context, state) => _shelled('/dashboard', const DashboardScreen()),
      ),
      GoRoute(
        path: '/parcels',
        builder: (context, state) => _shelled('/parcels', const ParcelsListScreen()),
        routes: [
          GoRoute(
            path: ':parcelId',
            builder: (context, state) => _shelled(
              '/parcels',
              ParcelDetailScreen(parcelId: state.pathParameters['parcelId']!),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/intake/new',
        builder: (context, state) => _shelled('/intake/new', const IntakeScreen()),
      ),
      GoRoute(
        path: '/triage',
        builder: (context, state) => _shelled('/triage', const TriageScreen()),
      ),
      GoRoute(
        path: '/review',
        builder: (context, state) => _shelled('/review', const ReviewScreen()),
      ),
      GoRoute(
        path: '/notices/:noticeId',
        builder: (context, state) => _shelled('/notices', const NoticePreviewScreen()),
      ),
      GoRoute(
        path: '/evacuation',
        builder: (context, state) => _shelled('/evacuation', const EvacuationScreen()),
      ),
      GoRoute(
        path: '/sitevisits',
        builder: (context, state) => _shelled('/sitevisits', const SiteVisitScreen()),
      ),
      GoRoute(
        path: '/assessment',
        builder: (context, state) => _shelled('/assessment', const AssessmentScreen()),
      ),
      GoRoute(
        path: '/demolition',
        builder: (context, state) => _shelled('/demolition', const DemolitionScreen()),
      ),
      GoRoute(
        path: '/import',
        builder: (context, state) => _shelled('/import', const ImportScreen()),
      ),
      GoRoute(
        path: '/reports',
        builder: (context, state) => _shelled('/reports', const ReportsScreen()),
      ),
      GoRoute(
        path: '/admin',
        builder: (context, state) => _shelled('/admin', const AdminScreen()),
      ),
    ],
  );
});

/// Bridges Riverpod's [authStateChangesProvider] stream to a [Listenable]
/// go_router can watch, so sign-in/sign-out immediately re-runs `redirect`
/// above without needing any screen to manually call `context.go`.
class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(Ref ref) {
    ref.listen(authStateChangesProvider, (_, __) => notifyListeners());
  }
}
