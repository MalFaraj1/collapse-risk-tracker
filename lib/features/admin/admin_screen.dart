import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../core/constants/roles.dart';
import '../../core/utils/error_utils.dart';
import '../../core/widgets/app_alert.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/status_badge.dart';
import '../auth/auth_providers.dart';
import '../intake/data/intake_repository.dart' show firestoreProvider;
import '../review/models/decision.dart';
import 'data/admin_repository.dart';
import 'models/app_user.dart';
import 'models/follow_up_settings.dart';
import 'models/notice_template.dart';

/// System Settings — "إعدادات النظام" (§7.12, FR-USR-1..3).
///
/// Three tabs, as approved in the design:
///  - Users & Roles — create accounts, assign one of the four roles,
///    deactivate (FR-USR-1). Roles come from the `users` directory, which
///    the security rules also read (FR-USR-2).
///  - Notice Templates — edit the legal wording of each notice type. Every
///    save is a NEW immutable version; an issued notice keeps rendering
///    with the version it was issued under.
///  - Default Periods (BR-4) — the per-action follow-up periods that
///    auto-fill execution dates across the app.
///
/// Administrator-only: reaching `/admin` by URL with any other role shows
/// an explanation instead of the tabs.
class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen> {
  int _tab = 0;
  bool _profileEnsured = false;

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(currentUserRoleProvider).valueOrNull;
    if (role != AppRole.admin) {
      return const AppCard(
        child: AppAlert(
          kind: AppAlertKind.info,
          title: 'صلاحية غير كافية',
          message: 'إعدادات النظام متاحة لمدير النظام فقط.',
        ),
      );
    }

    if (!_profileEnsured) {
      _profileEnsured = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(adminRepositoryProvider).ensureOwnProfile().catchError((_) {});
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PageHeader(
          title: 'إعدادات النظام',
          subtitle: 'إدارة المستخدمين والقوالب والمهل الافتراضية (§7.12, FR-USR-1..3).',
        ),
        const SizedBox(height: 18),
        _tabBar(),
        const SizedBox(height: 18),
        switch (_tab) {
          0 => const _UsersTab(),
          1 => const _TemplatesTab(),
          _ => const _PeriodsTab(),
        },
      ],
    );
  }

  Widget _tabBar() {
    Widget tab(int index, String label) {
      final selected = _tab == index;
      return InkWell(
        onTap: () => setState(() => _tab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: selected ? AppColors.gold : Colors.transparent, width: 2.5)),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: selected ? AppColors.text : AppColors.textMuted,
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
      child: Row(
        children: [
          tab(0, 'المستخدمون والأدوار'),
          tab(1, 'قوالب الإشعارات'),
          tab(2, 'المهل الافتراضية (BR-4)'),
        ],
      ),
    );
  }
}

// =============================================================================
// Tab 1 — Users & Roles
// =============================================================================
class _UsersTab extends ConsumerWidget {
  const _UsersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(usersProvider);
    final myUid = ref.watch(authStateChangesProvider).valueOrNull?.uid;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.groups_outlined, size: 18, color: AppColors.textMuted),
              const SizedBox(width: 8),
              const Text('المستخدمون', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: AppColors.text)),
              const Spacer(),
              AppButton(
                label: 'إضافة مستخدم',
                icon: Icons.person_add_alt_1_outlined,
                onPressed: () => showDialog<void>(context: context, builder: (_) => const _UserDialog()),
              ),
            ],
          ),
          const SizedBox(height: 16),
          usersAsync.when(
            loading: () => const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => AppAlert(
              kind: AppAlertKind.danger,
              title: 'تعذّر تحميل المستخدمين',
              message: describeFirebaseError(e, 'تعذّر تحميل دليل المستخدمين — تحقق من نشر قواعد الأمان المحدَّثة'),
            ),
            data: (users) {
              if (users.isEmpty) {
                return const AppEmptyState(
                  icon: Icons.group_off_outlined,
                  title: 'لا يوجد مستخدمون في الدليل بعد',
                  description: 'أضف أول مستخدم بالضغط على "إضافة مستخدم".',
                );
              }
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('المستخدم')),
                    DataColumn(label: Text('الدور')),
                    DataColumn(label: Text('الحالة')),
                    DataColumn(label: Text('')),
                  ],
                  rows: [for (final u in users) _row(context, u, isSelf: u.uid == myUid)],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  DataRow _row(BuildContext context, AppUserProfile u, {required bool isSelf}) {
    return DataRow(cells: [
      DataCell(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 15,
              backgroundColor: AppColors.navy,
              child: Text(u.initials, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 10),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  u.displayName.isEmpty ? '—' : u.displayName + (isSelf ? '  (أنت)' : ''),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.text),
                ),
                Text(u.email, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ],
            ),
          ],
        ),
      ),
      DataCell(Pill(
        label: u.role?.label ?? 'بدون دور',
        color: AppColors.navy,
        backgroundColor: AppColors.iceTint,
        borderColor: AppColors.border,
      )),
      DataCell(u.active
          ? const Pill(label: 'نشط', color: AppColors.success, backgroundColor: AppColors.successBg, borderColor: AppColors.border)
          : const Pill(label: 'معطّل', color: AppColors.textMuted, backgroundColor: AppColors.bg, borderColor: AppColors.border)),
      DataCell(
        AppButton(
          label: 'تعديل',
          variant: AppButtonVariant.outline,
          dense: true,
          onPressed: () => showDialog<void>(context: context, builder: (_) => _UserDialog(existing: u, isSelf: isSelf)),
        ),
      ),
    ]);
  }
}

class _UserDialog extends ConsumerStatefulWidget {
  const _UserDialog({this.existing, this.isSelf = false});

  final AppUserProfile? existing;
  final bool isSelf;

  @override
  ConsumerState<_UserDialog> createState() => _UserDialogState();
}

class _UserDialogState extends ConsumerState<_UserDialog> {
  late final TextEditingController _name;
  late final TextEditingController _email;
  final _password = TextEditingController();
  late AppRole _role;
  late bool _active;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.displayName ?? '');
    _email = TextEditingController(text: widget.existing?.email ?? '');
    _role = widget.existing?.role ?? AppRole.callCenter;
    _active = widget.existing?.active ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final email = _email.text.trim();
    if (name.isEmpty) return setState(() => _error = 'اسم المستخدم مطلوب.');
    if (!_isEdit) {
      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) return setState(() => _error = 'البريد الإلكتروني غير صالح.');
      if (_password.text.length < 6) return setState(() => _error = 'كلمة المرور المؤقتة يجب ألا تقل عن 6 محارف.');
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    final repo = ref.read(adminRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (_isEdit) {
        await repo.updateUser(widget.existing!.uid, displayName: name, role: _role, active: _active);
      } else {
        await repo.createUser(email: email, password: _password.text, displayName: name, role: _role);
      }
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(SnackBar(content: Text(_isEdit ? 'تم حفظ التعديلات.' : 'تم إنشاء المستخدم.')));
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = describeFirebaseError(e, _isEdit ? 'تعذّر حفظ التعديلات' : 'تعذّر إنشاء المستخدم');
          _saving = false;
        });
      }
    }
  }

  Future<void> _sendReset() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(adminRepositoryProvider).sendPasswordReset(widget.existing!.email);
      messenger.showSnackBar(const SnackBar(content: Text('تم إرسال رابط إعادة تعيين كلمة المرور إلى البريد الإلكتروني.')));
    } catch (e) {
      if (mounted) setState(() => _error = describeFirebaseError(e, 'تعذّر إرسال رابط إعادة التعيين'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'تعديل مستخدم' : 'إضافة مستخدم'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_error != null) ...[AppAlert(kind: AppAlertKind.danger, message: _error!), const SizedBox(height: 14)],
              TextField(controller: _name, decoration: const InputDecoration(labelText: 'الاسم الكامل')),
              const SizedBox(height: 14),
              TextField(
                controller: _email,
                enabled: !_isEdit,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'البريد الإلكتروني'),
              ),
              if (!_isEdit) ...[
                const SizedBox(height: 14),
                TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'كلمة مرور مؤقتة',
                    helperText: 'يُنصح بتغييرها من رابط "إعادة التعيين" بعد أول دخول.',
                  ),
                ),
              ],
              const SizedBox(height: 14),
              DropdownButtonFormField<AppRole>(
                value: _role,
                decoration: const InputDecoration(labelText: 'الدور'),
                items: [for (final r in AppRole.values) DropdownMenuItem(value: r, child: Text(r.label))],
                onChanged: widget.isSelf ? null : (v) => setState(() => _role = v ?? _role),
              ),
              if (_isEdit) ...[
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('الحساب نشط', style: TextStyle(fontSize: 13)),
                  subtitle: const Text('تعطيل الحساب يمنع صاحبه من استخدام النظام فورًا.', style: TextStyle(fontSize: 11.5)),
                  value: _active,
                  onChanged: widget.isSelf ? null : (v) => setState(() => _active = v),
                ),
                if (widget.isSelf)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'لا يمكنك تغيير دورك أو تعطيل حسابك بنفسك — لتفادي فقدان صلاحية الإدارة.',
                      style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                    ),
                  ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _saving ? null : _sendReset,
                  icon: const Icon(Icons.mail_outline, size: 16),
                  label: const Text('إرسال رابط إعادة تعيين كلمة المرور'),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ')),
      ],
    );
  }
}

// =============================================================================
// Tab 2 — Notice Templates
// =============================================================================
class _TemplatesTab extends ConsumerStatefulWidget {
  const _TemplatesTab();

  @override
  ConsumerState<_TemplatesTab> createState() => _TemplatesTabState();
}

class _TemplatesTabState extends ConsumerState<_TemplatesTab> {
  final _body = TextEditingController();
  DecisionAction _action = DecisionAction.shoringWarning;
  int _loadedVersion = NoticeTemplates.builtInVersion;
  String _loadedBody = '';
  List<NoticeTemplateVersion> _versions = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _success;

  @override
  void initState() {
    super.initState();
    _select(_action);
  }

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _select(DecisionAction action) async {
    setState(() {
      _action = action;
      _loading = true;
      _error = null;
      _success = null;
    });
    try {
      final firestore = ref.read(firestoreProvider);
      final version = await NoticeTemplates.currentVersion(firestore, action);
      final body = await NoticeTemplates.bodyFor(firestore, action);
      final versions = await ref.read(adminRepositoryProvider).getVersions(action);
      if (!mounted) return;
      setState(() {
        _loadedVersion = version;
        _loadedBody = body;
        _versions = versions;
        _body.text = body;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = describeFirebaseError(e, 'تعذّر تحميل القالب');
          _loading = false;
        });
      }
    }
  }

  List<String> get _unknownTokens {
    final known = NoticeTemplates.placeholders.keys.toSet();
    return RegExp(r'\{[a-zA-Z_]+\}').allMatches(_body.text).map((m) => m.group(0)!).where((t) => !known.contains(t)).toSet().toList();
  }

  bool get _canSave => !_saving && _body.text.trim().isNotEmpty && _body.text.trim() != _loadedBody.trim() && _unknownTokens.isEmpty;

  void _insert(String token) {
    final text = _body.text;
    final sel = _body.selection;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    _body.value = TextEditingValue(
      text: text.replaceRange(start, end, token),
      selection: TextSelection.collapsed(offset: start + token.length),
    );
    setState(() {});
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
      _success = null;
    });
    try {
      final next = await ref.read(adminRepositoryProvider).saveTemplate(_action, _body.text.trim());
      await _select(_action);
      if (mounted) setState(() => _success = 'تم الحفظ كإصدار جديد (الإصدار $next). تُستخدم النسخة الجديدة للإشعارات التي تُصدَر من الآن فصاعدًا؛ الإشعارات السابقة تحتفظ بنسختها.');
    } catch (e) {
      if (mounted) setState(() => _error = describeFirebaseError(e, 'تعذّر حفظ القالب'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final states = ref.watch(noticeTemplatesProvider).valueOrNull ?? const <String, NoticeTemplateState>{};

    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth > 900;
      final list = _buildList(states);
      final editor = _buildEditor();
      if (!wide) return Column(children: [list, const SizedBox(height: 16), editor]);
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 270, child: list),
          const SizedBox(width: 18),
          Expanded(child: editor),
        ],
      );
    });
  }

  Widget _buildList(Map<String, NoticeTemplateState> states) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('أنواع الإشعارات', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: AppColors.text)),
          const SizedBox(height: 10),
          for (final action in DecisionAction.values)
            InkWell(
              onTap: _saving ? null : () => _select(action),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 3),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                decoration: BoxDecoration(
                  color: _action == action ? AppColors.iceTint : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _action == action ? AppColors.navy : AppColors.border),
                ),
                child: Row(
                  children: [
                    Expanded(child: Text(action.noticeTitle, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.text))),
                    Builder(builder: (_) {
                      final custom = states[action.firestoreValue];
                      return Pill(
                        label: custom == null ? 'افتراضي' : 'v${custom.version}',
                        color: custom == null ? AppColors.textMuted : AppColors.navy,
                        backgroundColor: custom == null ? AppColors.bg : AppColors.iceTint,
                        borderColor: AppColors.border,
                      );
                    }),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEditor() {
    if (_loading) {
      return const AppCard(child: Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())));
    }
    final unknown = _unknownTokens;
    final preview = NoticeTemplates.render(
      _body.text,
      decisionDate: '2026-01-15',
      executionDate: '2026-02-14',
      parcelNo: '4471',
      cadastralZone: 'Z12',
      address: 'شارع الميناء — طرابلس',
    );

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('قالب: ${_action.noticeTitle}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: AppColors.text))),
              Pill(label: 'الإصدار الحالي: $_loadedVersion', color: AppColors.navy, backgroundColor: AppColors.iceTint, borderColor: AppColors.border),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'يُعدَّل هنا نصّ الفقرة القانونية فقط. العنوان وبيانات العقار والمهلة تُولَّد تلقائيًا في الإشعار ولا تُعدَّل من هذه الشاشة.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.6),
          ),
          const SizedBox(height: 14),
          if (_error != null) ...[AppAlert(kind: AppAlertKind.danger, message: _error!), const SizedBox(height: 12)],
          if (_success != null) ...[AppAlert(kind: AppAlertKind.success, message: _success!), const SizedBox(height: 12)],
          const Text('حقول الدمج (اضغط للإدراج عند المؤشر)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.text)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in NoticeTemplates.placeholders.entries)
                ActionChip(
                  label: Text('${entry.value}  ${entry.key}', style: const TextStyle(fontSize: 11.5)),
                  onPressed: () => _insert(entry.key),
                ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _body,
            minLines: 7,
            maxLines: 14,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'نص الفقرة القانونية', alignLabelWithHint: true),
          ),
          if (unknown.isNotEmpty) ...[
            const SizedBox(height: 10),
            AppAlert(kind: AppAlertKind.warning, message: 'حقول دمج غير معروفة: ${unknown.join('، ')} — استخدم الحقول المدرجة أعلاه فقط.'),
          ],
          const SizedBox(height: 16),
          const Text('معاينة (ببيانات تجريبية)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.text)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
            child: Text(preview, textAlign: TextAlign.justify, style: const TextStyle(fontSize: 13, color: AppColors.textBody, height: 1.9)),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AppButton(
                label: 'استعادة النص الافتراضي',
                variant: AppButtonVariant.outline,
                onPressed: _saving
                    ? null
                    : () => setState(() {
                          _body.text = NoticeTemplateDefaults.bodyFor(_action);
                          _success = null;
                        }),
              ),
              const SizedBox(width: 10),
              AppButton(label: _saving ? 'جارٍ الحفظ...' : 'حفظ كإصدار جديد', icon: Icons.save_outlined, onPressed: _canSave ? _save : null),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(height: 1),
          const SizedBox(height: 14),
          const Text('سجلّ الإصدارات', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.text)),
          const SizedBox(height: 8),
          for (final v in _versions) _versionRow(label: 'الإصدار ${v.version}', sub: v.savedAt == null ? '' : _fmt(v.savedAt!), body: v.body, current: v.version == _loadedVersion),
          _versionRow(
            label: 'الإصدار ${NoticeTemplates.builtInVersion} — النص الافتراضي المدمج',
            sub: '',
            body: NoticeTemplateDefaults.bodyFor(_action),
            current: _loadedVersion == NoticeTemplates.builtInVersion,
          ),
        ],
      ),
    );
  }

  Widget _versionRow({required String label, required String sub, required String body, required bool current}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              sub.isEmpty ? label : '$label · $sub',
              style: TextStyle(fontSize: 12.5, fontWeight: current ? FontWeight.w800 : FontWeight.w500, color: AppColors.text),
            ),
          ),
          if (current) const Pill(label: 'الحالي', color: AppColors.success, backgroundColor: AppColors.successBg, borderColor: AppColors.border),
          TextButton(
            onPressed: _saving ? null : () => setState(() => _body.text = body),
            child: const Text('تحميل في المحرّر', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

// =============================================================================
// Tab 3 — Default Periods (BR-4)
// =============================================================================
class _PeriodsTab extends ConsumerStatefulWidget {
  const _PeriodsTab();

  @override
  ConsumerState<_PeriodsTab> createState() => _PeriodsTabState();
}

class _PeriodsTabState extends ConsumerState<_PeriodsTab> {
  final _shoringWarning = TextEditingController();
  final _shoringConfirm = TextEditingController();
  final _restoration = TextEditingController();
  final _evacuation = TextEditingController();
  final _demolition = TextEditingController();
  final _window = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _success;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    for (final c in [_shoringWarning, _shoringConfirm, _restoration, _evacuation, _demolition, _window]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final s = await FollowUpSettings.load(ref.read(firestoreProvider));
    if (!mounted) return;
    setState(() {
      _shoringWarning.text = '${s.shoringWarningDays}';
      _shoringConfirm.text = '${s.shoringConfirmDays}';
      _restoration.text = '${s.restorationWarningDays}';
      _evacuation.text = '${s.evacuationHours}';
      _demolition.text = '${s.demolitionDays}';
      _window.text = '${s.dueSoonWindowDays}';
      _loading = false;
    });
  }

  int? _read(TextEditingController c, {required int max}) {
    final n = int.tryParse(c.text.trim());
    if (n == null || n < 1 || n > max) return null;
    return n;
  }

  Future<void> _save() async {
    final sw = _read(_shoringWarning, max: 3650);
    final sc = _read(_shoringConfirm, max: 3650);
    final rw = _read(_restoration, max: 3650);
    final ev = _read(_evacuation, max: 720);
    final dm = _read(_demolition, max: 3650);
    final win = _read(_window, max: 365);
    if ([sw, sc, rw, ev, dm, win].contains(null)) {
      setState(() {
        _success = null;
        _error = 'تحقق من القيم: كل مهلة رقم صحيح موجب (الإخلاء حتى 720 ساعة، النافذة حتى 365 يومًا، والبقية حتى 3650 يومًا).';
      });
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _success = null;
    });
    try {
      await ref.read(adminRepositoryProvider).saveSettings(FollowUpSettings(
            shoringWarningDays: sw!,
            shoringConfirmDays: sc!,
            restorationWarningDays: rw!,
            evacuationHours: ev!,
            demolitionDays: dm!,
            dueSoonWindowDays: win!,
          ));
      if (mounted) setState(() => _success = 'تم حفظ المهل الافتراضية. تُطبَّق على القرارات والأوامر الجديدة فقط؛ لا تتغيّر مواعيد ما صدر سابقًا.');
    } catch (e) {
      if (mounted) setState(() => _error = describeFirebaseError(e, 'تعذّر حفظ المهل'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(TextEditingController c, String label, String unit, String helper) {
    return SizedBox(
      width: 270,
      child: TextField(
        controller: c,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: label, suffixText: unit, helperText: helper, helperMaxLines: 2),
      ),
    );
  }

  Widget _group(String title, List<Widget> fields) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.text)),
        const SizedBox(height: 12),
        Wrap(spacing: 16, runSpacing: 16, children: fields),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const AppCard(child: Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())));

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('المهل الافتراضية للمتابعة', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: AppColors.text)),
          const SizedBox(height: 6),
          const Text(
            'لا توجد مُهل قانونية ثابتة (§5.2، BR-4): تُعبَّأ تواريخ التنفيذ تلقائيًا من هذه القيم، ويمكن للمستخدم تعديلها لكل إجراء على حدة.',
            style: TextStyle(fontSize: 12.5, color: AppColors.textMuted, height: 1.6),
          ),
          const SizedBox(height: 18),
          if (_error != null) ...[AppAlert(kind: AppAlertKind.danger, message: _error!), const SizedBox(height: 14)],
          if (_success != null) ...[AppAlert(kind: AppAlertKind.success, message: _success!), const SizedBox(height: 14)],
          _group('مهل القرارات', [
            _field(_shoringWarning, 'إنذار تدعيم', 'يومًا', 'المهلة الممنوحة للمالك لتنفيذ التدعيم'),
            _field(_shoringConfirm, 'تأكيدي بالتدعيم', 'يومًا', 'المهلة الجديدة بعد التأكيد'),
            _field(_restoration, 'إنذار ترميم', 'يومًا', 'المهلة الممنوحة للمالك لتنفيذ الترميم'),
          ]),
          const SizedBox(height: 22),
          _group('الإخلاء والهدم', [
            _field(_evacuation, 'مهلة الامتثال بعد الإخلاء (BR-7)', 'ساعة', 'تبدأ عند نشر أمر الإخلاء على المبنى'),
            _field(_demolition, 'موعد تنفيذ الهدم المجدول', 'يومًا', 'يُحدَّد تلقائيًا عند صدور رأي "هدم"'),
          ]),
          const SizedBox(height: 22),
          _group('التقارير', [
            _field(_window, 'نافذة "مستحقة قريبًا"', 'يومًا', 'الإجراءات المستحقة خلال هذه المدة تظهر في تقرير المتأخرة والمستحقة'),
          ]),
          const SizedBox(height: 24),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: AppButton(label: _saving ? 'جارٍ الحفظ...' : 'حفظ المهل', icon: Icons.save_outlined, onPressed: _saving ? null : _save),
          ),
        ],
      ),
    );
  }
}
