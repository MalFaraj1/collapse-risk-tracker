import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme/app_colors.dart';
import '../../core/constants/roles.dart';
import '../../features/auth/auth_providers.dart';
import 'app_button.dart';
import 'app_logo.dart';
import 'nav_items.dart';

/// The persistent app frame: sidebar navigation (filtered to the signed-in
/// user's real role — this is a live enforcement of Appendix A, not just a
/// visual convenience) + top bar, wrapping every authenticated screen.
///
/// Unlike the design-review prototype, there is no role *switcher* here —
/// that was a prototype-only device for reviewing every role's view in one
/// sitting. In the real app, the role comes from [currentUserRoleProvider]
/// and cannot be changed by the user.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.currentRoute, required this.child});

  final String currentRoute;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roleAsync = ref.watch(currentUserRoleProvider);
    final user = ref.watch(authStateChangesProvider).valueOrNull;

    return roleAsync.when(
      loading: () => const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppLogo(height: 110),
              SizedBox(height: 24),
              SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
            ],
          ),
        ),
      ),
      error: (e, _) => Scaffold(body: Center(child: Text('تعذّر تحميل صلاحيات المستخدم: $e'))),
      data: (role) {
        if (role == null) {
          // Signed in, but no role claim set yet — should be rare (only the
          // window between account creation and an Admin assigning a role).
          return const Scaffold(
            body: Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'حسابك لا يملك دورًا مُعيَّنًا بعد. الرجاء التواصل مع مدير النظام.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        return Scaffold(
          body: Row(
            children: [
              _Sidebar(role: role, currentRoute: currentRoute),
              Expanded(
                child: Column(
                  children: [
                    _TopBar(role: role, user: user),
                    Expanded(
                      child: Container(color: AppColors.bg, child: child),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The scrollable, padded content area for a single screen inside
/// [AppShell]. Lives per-route (not in the shell) because the shell's child
/// is go_router's nested [Navigator], which needs bounded height.
class ShellContent extends StatelessWidget {
  const ShellContent({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bg,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 26, 28, 60),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: child,
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.role, required this.currentRoute});

  final AppRole role;
  final String currentRoute;

  @override
  Widget build(BuildContext context) {
    final visibleGroups = navGroups.map((g) => g.filteredFor(role)).where((g) => g.items.isNotEmpty).toList();

    return Container(
      width: 260,
      color: AppColors.navy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0x14FFFFFF))),
            ),
            child: Row(
              children: [
                const AppLogo(height: 46, onDark: true),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'نظام متابعة المباني الآيلة للسقوط',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'بلدية طرابلس',
                        style: TextStyle(color: Colors.white.withOpacity(.55), fontWeight: FontWeight.w600, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                for (final group in visibleGroups) _NavGroupWidget(group: group, currentRoute: currentRoute),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              'Collapse-Risk Tracker\nنسخة الإنتاج',
              style: TextStyle(fontSize: 10.5, color: Colors.white.withOpacity(.4), height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavGroupWidget extends StatelessWidget {
  const _NavGroupWidget({required this.group, required this.currentRoute});

  final NavGroup group;
  final String currentRoute;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Text(
              group.label,
              style: TextStyle(
                fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: .6,
                color: Colors.white.withOpacity(.38),
              ),
            ),
          ),
          for (final item in group.items)
            _NavItemTile(item: item, selected: currentRoute.startsWith(item.route)),
        ],
      ),
    );
  }
}

class _NavItemTile extends StatelessWidget {
  const _NavItemTile({required this.item, required this.selected});

  final NavItem item;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? const Color(0x29C9A227) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => context.go(item.route),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                Icon(item.icon, size: 19, color: selected ? AppColors.gold : Colors.white.withOpacity(.55)),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    item.label,
                    style: TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : Colors.white.withOpacity(.72),
                    ),
                  ),
                ),
                if (item.badgeCount != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                    decoration: BoxDecoration(color: AppColors.danger, borderRadius: BorderRadius.circular(20)),
                    child: Text('${item.badgeCount}',
                        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.role, required this.user});

  final AppRole role;
  final User? user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayName = user?.displayName ?? user?.email ?? 'مستخدم';
    final initials = displayName.isNotEmpty ? displayName.substring(0, 1).toUpperCase() : '؟';

    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const Spacer(),
          AppIconButton(icon: Icons.notifications_outlined, showDot: true, onPressed: () {}),
          const SizedBox(width: 14),
          Container(
            padding: const EdgeInsets.only(right: 16),
            decoration: const BoxDecoration(
              border: Border(right: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(color: AppColors.navy3, shape: BoxShape.circle),
                  child: Center(
                    child: Text(initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 9),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(displayName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppColors.text)),
                    Text(role.label, style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
                  ],
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.logout, size: 18, color: AppColors.textMuted),
                  tooltip: 'تسجيل الخروج',
                  onPressed: () => ref.read(firebaseAuthProvider).signOut(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
