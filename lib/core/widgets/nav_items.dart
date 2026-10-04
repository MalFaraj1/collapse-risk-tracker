import 'package:flutter/material.dart';
import '../constants/access_policy.dart';
import '../constants/roles.dart';

/// One entry in the sidebar navigation.
class NavItem {
  const NavItem({
    required this.route,
    required this.icon,
    required this.label,
    required this.allowedRoles, // null = visible to every signed-in role
    this.badgeCount,
  });

  final String route;
  final IconData icon;
  final String label;
  final Set<AppRole>? allowedRoles;
  final int? badgeCount;

  bool visibleTo(AppRole role) => allowedRoles == null || allowedRoles!.contains(role);
}

class NavGroup {
  const NavGroup({required this.label, required this.items});
  final String label;
  final List<NavItem> items;

  /// Returns this group with only the items visible to [role]. A group with
  /// zero visible items after filtering should not be rendered at all —
  /// see [AppShell].
  NavGroup filteredFor(AppRole role) =>
      NavGroup(label: label, items: items.where((i) => i.visibleTo(role)).toList());
}

/// The sidebar structure, matching the approved design prototype's nav
/// groups exactly (§3, Appendix A). Who sees each item now comes from
/// [AccessPolicy], the same table the router's route guard and the
/// dashboard use, so the three can't drift apart.
final navGroups = <NavGroup>[
  NavGroup(label: 'عام', items: [
    const NavItem(route: '/dashboard', icon: Icons.space_dashboard_outlined, label: 'الإجراءات المستحقة', allowedRoles: null),
    const NavItem(route: '/parcels', icon: Icons.home_work_outlined, label: 'سجلّ العقارات', allowedRoles: null),
  ]),
  NavGroup(label: 'مركز الاتصال', items: [
    const NavItem(route: '/intake/new', icon: Icons.add_call, label: 'شكوى جديدة',
        allowedRoles: AccessPolicy.intake),
  ]),
  NavGroup(label: 'الفريق الهندسي', items: [
    const NavItem(route: '/triage', icon: Icons.rule_outlined, label: 'فرز الأولوية',
        allowedRoles: AccessPolicy.triage),
    const NavItem(route: '/review', icon: Icons.gavel_outlined, label: 'المراجعة والقرار',
        allowedRoles: AccessPolicy.review),
    const NavItem(route: '/assessment', icon: Icons.architecture_outlined, label: 'التقييم والترميم',
        allowedRoles: AccessPolicy.assessment),
  ]),
  NavGroup(label: 'فريق الشرطة', items: [
    const NavItem(route: '/evacuation', icon: Icons.directions_run_outlined, label: 'تنفيذ الإخلاء',
        allowedRoles: AccessPolicy.evacuation),
    const NavItem(route: '/sitevisits', icon: Icons.domain_verification_outlined, label: 'زيارة ميدانية',
        allowedRoles: AccessPolicy.siteVisits),
    const NavItem(route: '/demolition', icon: Icons.domain_disabled_outlined, label: 'أوامر الهدم',
        allowedRoles: AccessPolicy.demolition),
  ]),
  NavGroup(label: 'التقارير والإدارة', items: [
    const NavItem(route: '/reports', icon: Icons.bar_chart_outlined, label: 'التقارير', allowedRoles: null),
    const NavItem(route: '/import', icon: Icons.upload_file_outlined, label: 'استيراد إنذارات سابقة',
        allowedRoles: AccessPolicy.imports),
    const NavItem(route: '/admin', icon: Icons.admin_panel_settings_outlined, label: 'إعدادات النظام',
        allowedRoles: AccessPolicy.adminSettings),
  ]),
];