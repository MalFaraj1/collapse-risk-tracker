import 'package:flutter/material.dart';
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
/// groups exactly (§3, Appendix A). Admin implicitly sees everything —
/// enforced by including it in every `allowedRoles` set below, mirroring
/// "Admin: full visibility and edit rights across all cases" in Appendix A.
final navGroups = <NavGroup>[
  NavGroup(label: 'عام', items: [
    const NavItem(route: '/dashboard', icon: Icons.space_dashboard_outlined, label: 'الإجراءات المستحقة', allowedRoles: null),
    const NavItem(route: '/parcels', icon: Icons.home_work_outlined, label: 'سجلّ العقارات', allowedRoles: null),
  ]),
  NavGroup(label: 'مركز الاتصال', items: [
    const NavItem(route: '/intake/new', icon: Icons.add_call, label: 'شكوى جديدة',
        allowedRoles: {AppRole.callCenter, AppRole.admin}),
  ]),
  NavGroup(label: 'الفريق الهندسي', items: [
    const NavItem(route: '/triage', icon: Icons.rule_outlined, label: 'فرز الأولوية',
        allowedRoles: {AppRole.engineering, AppRole.admin}),
    const NavItem(route: '/review', icon: Icons.gavel_outlined, label: 'المراجعة والقرار',
        allowedRoles: {AppRole.engineering, AppRole.admin}),
    const NavItem(route: '/assessment', icon: Icons.architecture_outlined, label: 'التقييم والترميم',
        allowedRoles: {AppRole.engineering, AppRole.admin}),
  ]),
  NavGroup(label: 'فريق الشرطة', items: [
    const NavItem(route: '/evacuation', icon: Icons.directions_run_outlined, label: 'تنفيذ الإخلاء',
        allowedRoles: {AppRole.police, AppRole.admin}),
    const NavItem(route: '/sitevisits', icon: Icons.domain_verification_outlined, label: 'زيارة ميدانية',
        allowedRoles: {AppRole.police, AppRole.admin}),
    const NavItem(route: '/demolition', icon: Icons.domain_disabled_outlined, label: 'أوامر الهدم',
        allowedRoles: {AppRole.police, AppRole.admin}),
  ]),
  NavGroup(label: 'التقارير والإدارة', items: [
    const NavItem(route: '/reports', icon: Icons.bar_chart_outlined, label: 'التقارير', allowedRoles: null),
    const NavItem(route: '/import', icon: Icons.upload_file_outlined, label: 'استيراد إنذارات سابقة',
        allowedRoles: {AppRole.admin}),
    const NavItem(route: '/admin', icon: Icons.admin_panel_settings_outlined, label: 'إعدادات النظام',
        allowedRoles: {AppRole.admin}),
  ]),
];
