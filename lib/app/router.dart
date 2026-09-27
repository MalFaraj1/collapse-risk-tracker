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
  final authNotifier = _AuthRefreshNotifier(ref);

  return GoRouter(
    initialLocation: '/dashboard',
    refreshListenable: authNotifier,
    redirect: (context, state) {
      final isSignedIn = ref.read(authStateChangesProvider).valueOrNull != null;
      final isLoggingIn = state.matchedLocation == '/login';

      if (!isSignedIn && !isLoggingIn) return '/login';
      if (isSignedIn && isLoggingIn) return '/dashboard';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),

      GoRoute(
        path: '/dashboard',
        builder: (context, state) => _shelled('/dashboard', const DashboardScreen()),
      ),

      // --- Parcels / neighborhoods -------------------------------------------------
      // `all` and `area/:neighborhoodId` are declared BEFORE the catch-all
      // `:parcelId` route on purpose: go_router matches static path
      // segments against sibling routes in declaration order, and a real
      // parcel ID (e.g. "4471_Z12") will never collide with the literal
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
        routes: [
          GoRoute(
            path: ':complaintId',
            builder: (context, state) => _shelled(
              '/triage',
              TriageScreen(complaintId: state.pathParameters['complaintId']),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/review',
        builder: (context, state) => _shelled('/review', const ReviewScreen()),
        routes: [
          GoRoute(
            path: ':caseId',
            builder: (context, state) => _shelled(
              '/review',
              ReviewScreen(caseId: state.pathParameters['caseId']),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/notices/:noticeId',
        builder: (context, state) => _shelled(
          '/notices',
          NoticePreviewScreen(noticeId: state.pathParameters['noticeId']),
        ),
      ),
      GoRoute(
        path: '/evacuation',
        builder: (context, state) => _shelled('/evacuation', const EvacuationScreen()),
        routes: [
          GoRoute(
            path: ':decisionId',
            builder: (context, state) => _shelled(
              '/evacuation',
              EvacuationScreen(decisionId: state.pathParameters['decisionId']),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/sitevisits',
        builder: (context, state) => _shelled('/sitevisits', const SiteVisitScreen()),
        routes: [
          GoRoute(
            path: ':decisionId',
            builder: (context, state) => _shelled(
              '/sitevisits',
              SiteVisitScreen(decisionId: state.pathParameters['decisionId']),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/assessment',
        builder: (context, state) => _shelled('/assessment', const AssessmentScreen()),
        routes: [
          GoRoute(
            path: ':decisionId',
            builder: (context, state) => _shelled(
              '/assessment',
              AssessmentScreen(decisionId: state.pathParameters['decisionId']),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/demolition',
        builder: (context, state) => _shelled('/demolition', const DemolitionScreen()),
        routes: [
          GoRoute(
            path: ':decisionId',
            builder: (context, state) => _shelled(
              '/demolition',
              DemolitionScreen(decisionId: state.pathParameters['decisionId']),
            ),
          ),
        ],
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

class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(Ref ref) {
    ref.listen(authStateChangesProvider, (_, __) => notifyListeners());
  }
}