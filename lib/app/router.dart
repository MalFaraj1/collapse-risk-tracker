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

/// Wraps a feature screen in the shell's scrollable content area. The
/// [AppShell] itself (sidebar + top bar) is built once by the [ShellRoute]
/// below and stays mounted across navigations, so the sidebar keeps its
/// scroll position instead of being rebuilt with every page.
Widget _page(Widget child) => ShellContent(child: child);

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

      // Every authenticated route lives under this ShellRoute — only `/login`
      // doesn't.
      ShellRoute(
        builder: (context, state, child) => AppShell(currentRoute: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => _page(const DashboardScreen()),
          ),

          // --- Parcels / neighborhoods ---------------------------------------------
          // `all` and `area/:neighborhoodId` are declared BEFORE the catch-all
          // `:parcelId` route on purpose: go_router matches static path
          // segments against sibling routes in declaration order, and a real
          // parcel ID (e.g. "4471_Z12") will never collide with the literal
          GoRoute(
            path: '/parcels',
            builder: (context, state) => _page(const ParcelsListScreen()),
            routes: [
              GoRoute(
                path: ':parcelId',
                builder: (context, state) => _page(
                  ParcelDetailScreen(parcelId: state.pathParameters['parcelId']!),
                ),
              ),
            ],
          ),

          GoRoute(
            path: '/intake/new',
            builder: (context, state) => _page(const IntakeScreen()),
          ),
          GoRoute(
            path: '/triage',
            builder: (context, state) => _page(const TriageScreen()),
            routes: [
              GoRoute(
                path: ':complaintId',
                builder: (context, state) => _page(
                  TriageScreen(complaintId: state.pathParameters['complaintId']),
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/review',
            builder: (context, state) => _page(const ReviewScreen()),
            routes: [
              GoRoute(
                path: ':caseId',
                builder: (context, state) => _page(
                  ReviewScreen(caseId: state.pathParameters['caseId']),
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/notices/:noticeId',
            builder: (context, state) => _page(
              NoticePreviewScreen(noticeId: state.pathParameters['noticeId']),
            ),
          ),
          GoRoute(
            path: '/evacuation',
            builder: (context, state) => _page(const EvacuationScreen()),
            routes: [
              GoRoute(
                path: ':decisionId',
                builder: (context, state) => _page(
                  EvacuationScreen(decisionId: state.pathParameters['decisionId']),
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/sitevisits',
            builder: (context, state) => _page(const SiteVisitScreen()),
            routes: [
              GoRoute(
                path: ':decisionId',
                builder: (context, state) => _page(
                  SiteVisitScreen(decisionId: state.pathParameters['decisionId']),
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/assessment',
            builder: (context, state) => _page(const AssessmentScreen()),
            routes: [
              GoRoute(
                path: ':decisionId',
                builder: (context, state) => _page(
                  AssessmentScreen(decisionId: state.pathParameters['decisionId']),
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/demolition',
            builder: (context, state) => _page(const DemolitionScreen()),
            routes: [
              GoRoute(
                path: ':decisionId',
                builder: (context, state) => _page(
                  DemolitionScreen(decisionId: state.pathParameters['decisionId']),
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/import',
            builder: (context, state) => _page(const ImportScreen()),
          ),
          GoRoute(
            path: '/reports',
            builder: (context, state) => _page(const ReportsScreen()),
          ),
          GoRoute(
            path: '/admin',
            builder: (context, state) => _page(const AdminScreen()),
          ),
        ],
      ),
    ],
  );
});

class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(Ref ref) {
    ref.listen(authStateChangesProvider, (_, __) => notifyListeners());
  }
}
