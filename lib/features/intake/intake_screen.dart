import 'package:file_picker/file_picker.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_typography.dart';
import '../../core/widgets/app_alert.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/location_picker_map.dart';
import '../../core/widgets/step_indicator.dart';
import '../../core/widgets/timeline_rail.dart';
import 'data/intake_repository.dart';
import 'models/case.dart';
import 'models/complaint.dart';
import 'models/parcel.dart';

/// New Complaint intake — "شكوى جديدة" (§7.1, FR-INT-1..4, BR-2, BR-3).
///
/// Matches the approved design exactly: ONE continuous scrollable form, not
/// a gated multi-step wizard. The step indicator at the top is decorative —
/// it reflects progress, it never hides fields or blocks the user from
/// scrolling to any part of the form. The only real gate is the final
/// submit button, which requires a resolved parcel and a non-empty
/// narrative.
class IntakeScreen extends ConsumerStatefulWidget {
  const IntakeScreen({super.key});

  @override
  ConsumerState<IntakeScreen> createState() => _IntakeScreenState();
}

class _IntakeScreenState extends ConsumerState<IntakeScreen> {
  static const _stepLabels = ['تحديد العقار', 'تفاصيل الشكوى', 'مراجعة وتأكيد'];

  bool _busy = false;
  String? _error;

  // --- Parcel identification --------------------------------------------------
  final _parcelNoController = TextEditingController();
  final _zoneController = TextEditingController();
  final _addressController = TextEditingController();

  Parcel? _resolvedParcel; // non-null only once confirmed to exist in Firestore
  bool _isCreatingNew = false; // true once a search comes back with no match
  List<Case> _priorCases = [];
  List<Complaint> _priorComplaints = [];
  double? _latitude;
  double? _longitude;
  int _mapKeySeed = 0; // forces the map widget to reset cleanly between searches

  // --- Complaint details --------------------------------------------------------
  final _narrativeController = TextEditingController();
  final _contactController = TextEditingController();
  late final TextEditingController _dateController;
  DateTime _complaintDate = DateTime.now();
  ComplaintChannel _channel = ComplaintChannel.phone;
  final List<PlatformFile> _photos = [];

  @override
  void initState() {
    super.initState();
    _dateController = TextEditingController(text: _fmt(_complaintDate));
    // Purely so the decorative step indicator can reflect progress as the
    // user types — this never gates anything, see class doc comment.
    _narrativeController.addListener(_refreshStepIndicator);
  }

  @override
  void dispose() {
    _narrativeController.removeListener(_refreshStepIndicator);
    _parcelNoController.dispose();
    _zoneController.dispose();
    _addressController.dispose();
    _narrativeController.dispose();
    _contactController.dispose();
    _dateController.dispose();
    super.dispose();
  }

  void _refreshStepIndicator() => setState(() {});

  /// Decorative only — see class doc comment. Never used to hide fields.
  int get _currentStepIndex {
    if (_resolvedParcel == null && !_isCreatingNew) return 0;
    if (_narrativeController.text.trim().isEmpty) return 1;
    return 2;
  }

  IntakeRepository get _repo => ref.read(intakeRepositoryProvider);

  Future<void> _searchParcel() async {
    if (_parcelNoController.text.trim().isEmpty || _zoneController.text.trim().isEmpty) {
      setState(() => _error = 'الرجاء إدخال رقم العقار والمنطقة العقارية.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _resolvedParcel = null;
      _isCreatingNew = false;
      _priorCases = [];
      _priorComplaints = [];
      _latitude = null;
      _longitude = null;
      _mapKeySeed++;
    });
    try {
      final parcel = await _repo.findParcel(
        parcelNo: _parcelNoController.text,
        cadastralZone: _zoneController.text,
      );
      if (!mounted) return;
      if (parcel == null) {
        setState(() {
          _isCreatingNew = true;
          _addressController.clear();
        });
      } else {
        // Fetch both in parallel: the case-level status list (for the BR-3
        // banner) and the actual complaint content (narrative/photos/etc.)
        // that was previously reported — see IntakeRepository for why both
        // are needed rather than just one.
        final history = await _repo.getCaseHistory(parcel.id);
        final complaints = await _repo.getComplaintHistory(parcel.id);
        if (!mounted) return;
        setState(() {
          _resolvedParcel = parcel;
          _addressController.text = parcel.address;
          _priorCases = history;
          _priorComplaints = complaints;
          _latitude = parcel.latitude;
          _longitude = parcel.longitude;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = _describeError(e, 'تعذّر البحث عن العقار'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _resetParcelSelection() {
    setState(() {
      _resolvedParcel = null;
      _isCreatingNew = false;
      _priorCases = [];
      _priorComplaints = [];
      _addressController.clear();
      _latitude = null;
      _longitude = null;
      _mapKeySeed++;
    });
  }

  Future<void> _pickPhotos() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true, // guarantees `bytes` is populated on every platform
    );
    if (result != null && result.files.isNotEmpty && mounted) {
      setState(() => _photos.addAll(result.files));
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _complaintDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null && mounted) {
      setState(() {
        _complaintDate = picked;
        _dateController.text = _fmt(picked);
      });
    }
  }

  Future<void> _submit() async {
    if (_resolvedParcel == null && !_isCreatingNew) {
      setState(() => _error = 'الرجاء تحديد العقار أولًا (البحث برقم العقار والمنطقة العقارية).');
      return;
    }
    if (_isCreatingNew && _addressController.text.trim().isEmpty) {
      setState(() => _error = 'الرجاء إدخال عنوان العقار الجديد.');
      return;
    }
    if (_narrativeController.text.trim().isEmpty) {
      setState(() => _error = 'وصف الشكوى مطلوب.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // FR-INT-2: create the parcel first if this is a new one.
      final parcel = _resolvedParcel ??
          await _repo.createParcel(
            parcelNo: _parcelNoController.text,
            cadastralZone: _zoneController.text,
            address: _addressController.text,
            latitude: _latitude,
            longitude: _longitude,
          );

      // BR-2, enforced atomically — see IntakeRepository for why this must
      // be a transaction rather than a query-then-write.
      final caseId = await _repo.getOrCreateOpenCaseId(parcel.id);

      await _repo.submitComplaint(
        caseId: caseId,
        parcelId: parcel.id,
        date: _complaintDate,
        channel: _channel,
        narrative: _narrativeController.text.trim(),
        complainantContact:
            _contactController.text.trim().isEmpty ? null : _contactController.text.trim(),
        photos: _photos,
      );

      if (!mounted) return;
      context.go('/dashboard');
    } catch (e) {
      if (mounted) setState(() => _error = _describeError(e, 'تعذّر حفظ الشكوى'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('شكوى جديدة', style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 4),
        const Text(
          'تسجيل بلاغ مواطن وربطه بالعقار المعني (FR-INT-1..4).',
          style: TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
        const SizedBox(height: 22),
        StepIndicator(steps: _stepLabels, currentIndex: _currentStepIndex),
        const SizedBox(height: 22),
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 900;
            final mainCard = AppCard(child: _buildForm());
            final hasHistory = _priorCases.isNotEmpty || _priorComplaints.isNotEmpty;
            if (!isWide || !hasHistory) return mainCard;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: mainCard),
                const SizedBox(width: 18),
                Expanded(child: _buildHistoryPanel()),
              ],
            );
          },
        ),
      ],
    );
  }

  /// The entire form, top to bottom, exactly as laid out in the approved
  /// design: parcel search → BR-3 alert (if applicable) → address →
  /// location map → divider → channel/date → narrative → contact →
  /// photos → actions.
  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('البحث عن العقار', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _parcelNoController,
                decoration: const InputDecoration(
                  labelText: 'رقم العقار',
                  prefixIcon: Icon(Icons.search, size: 20),
                ),
                onSubmitted: (_) => _searchParcel(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _zoneController,
                decoration: const InputDecoration(labelText: 'المنطقة العقارية'),
                onSubmitted: (_) => _searchParcel(),
              ),
            ),
            const SizedBox(width: 12),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: AppButton(
                label: 'بحث',
                icon: Icons.search,
                variant: AppButtonVariant.outline,
                onPressed: _busy ? null : _searchParcel,
              ),
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text(
            'إن لم يكن العقار مسجّلاً، يمكنك إنشاؤه أدناه (FR-INT-2).',
            style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
          ),
        ),
        const SizedBox(height: 16),
        if (_error != null) ...[
          AppAlert(kind: AppAlertKind.danger, message: _error!),
          const SizedBox(height: 16),
        ],
        if (_priorCases.isNotEmpty) ...[
          AppAlert(
            kind: AppAlertKind.warning,
            title: 'يوجد سجلّ سابق على هذا العقار (BR-3)',
            message:
                'عُثر على ${_priorCases.length == 1 ? "حالة واحدة سابقة" : "${_priorCases.length} حالات سابقة"} '
                '— طالع القائمة الجانبية قبل المتابعة لتفادي تكرار المعلومات.',
          ),
          const SizedBox(height: 16),
        ],
        if (_resolvedParcel != null || _isCreatingNew) ...[
          if (_resolvedParcel != null)
            Row(
              children: [
                const Icon(Icons.check_circle, size: 16, color: AppColors.success),
                const SizedBox(width: 6),
                Text(_resolvedParcel!.id, style: AppTypography.mono(fontSize: 12.5, weight: FontWeight.w700)),
                const Spacer(),
                TextButton(onPressed: _resetParcelSelection, child: const Text('تغيير')),
              ],
            )
          else
            Row(
              children: [
                const Icon(Icons.add_business_outlined, size: 16, color: AppColors.info),
                const SizedBox(width: 6),
                const Text(
                  'لم يُعثر على هذا العقار — سيُنشأ عقار جديد عند الحفظ',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.info),
                ),
                const Spacer(),
                TextButton(onPressed: _resetParcelSelection, child: const Text('تغيير')),
              ],
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _addressController,
            // Editing an EXISTING parcel's address isn't Intake's job — that
            // belongs to the parcel registry. Only a brand-new parcel's
            // address is editable here.
            readOnly: _resolvedParcel != null,
            decoration: InputDecoration(
              labelText: 'العنوان',
              filled: _resolvedParcel != null,
              fillColor: _resolvedParcel != null ? AppColors.bg : null,
            ),
          ),
          if (_isCreatingNew)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'سيُسجَّل مبنى واحد لهذا العقار — يمكن إضافة مبانٍ إضافية لاحقًا من سجلّ العقارات.',
                style: TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
            ),
          const SizedBox(height: 16),
          const Text(
            'الموقع على الخريطة',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppColors.text),
          ),
          const SizedBox(height: 8),
          _locationSection(),
          const Divider(height: 36),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<ComplaintChannel>(
                  value: _channel,
                  decoration: const InputDecoration(labelText: 'قناة البلاغ'),
                  items: ComplaintChannel.values
                      .map((c) => DropdownMenuItem(value: c, child: Text(c.label)))
                      .toList(),
                  onChanged: (v) => setState(() => _channel = v ?? _channel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  readOnly: true,
                  controller: _dateController,
                  decoration: const InputDecoration(labelText: 'تاريخ البلاغ'),
                  onTap: _pickDate,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _narrativeController,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'وصف الشكوى *',
              hintText: 'اكتب وصفًا تفصيليًا لما أبلغ عنه المواطن...',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _contactController,
            decoration: const InputDecoration(labelText: 'معلومات التواصل مع المُبلّغ (اختياري)'),
          ),
          const SizedBox(height: 20),
          const Text(
            'الصور المرفقة',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppColors.text),
          ),
          const SizedBox(height: 8),
          _photoPicker(),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AppButton(
                label: 'إلغاء',
                variant: AppButtonVariant.outline,
                onPressed: _busy ? null : () => context.go('/dashboard'),
              ),
              const SizedBox(width: 10),
              AppButton(
                label: _busy ? 'جارٍ الحفظ...' : 'حفظ وفتح الحالة',
                icon: Icons.check,
                onPressed: _busy ? null : _submit,
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// Existing parcel → read-only map + coordinates (Intake doesn't own
  /// editing an existing parcel's location, same reasoning as its
  /// address). New parcel → an interactive map: tap to drop a pin, and
  /// the resulting lat/lng are captured automatically, not typed by hand.
  Widget _locationSection() {
    if (_resolvedParcel != null) {
      if (_latitude == null || _longitude == null) {
        return const AppAlert(
          kind: AppAlertKind.info,
          message: 'لم يتم تحديد موقع لهذا العقار على الخريطة بعد.',
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LocationPickerMap(
            key: ValueKey('map-$_mapKeySeed'),
            initialLatitude: _latitude,
            initialLongitude: _longitude,
            readOnly: true,
          ),
          const SizedBox(height: 8),
          _coordinatesRow(),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LocationPickerMap(
          key: ValueKey('map-$_mapKeySeed'),
          initialLatitude: _latitude,
          initialLongitude: _longitude,
          onLocationSelected: (point) => setState(() {
            _latitude = point.latitude;
            _longitude = point.longitude;
          }),
        ),
        const SizedBox(height: 8),
        if (_latitude != null && _longitude != null)
          _coordinatesRow()
        else
          const Text(
            'لم يتم تحديد الموقع بعد — اضغط على الخريطة أعلاه لتثبيت الموقع (اختياري).',
            style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
          ),
      ],
    );
  }

  Widget _coordinatesRow() {
    return Row(
      children: [
        const Icon(Icons.place_outlined, size: 14, color: AppColors.textMuted),
        const SizedBox(width: 5),
        Text('خط العرض: ${_latitude!.toStringAsFixed(6)}',
            style: AppTypography.mono(fontSize: 11.5, color: AppColors.textMuted)),
        const SizedBox(width: 14),
        Text('خط الطول: ${_longitude!.toStringAsFixed(6)}',
            style: AppTypography.mono(fontSize: 11.5, color: AppColors.textMuted)),
      ],
    );
  }

  Widget _photoPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_photos.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < _photos.length; i++)
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 84,
                      height: 84,
                      decoration:
                          BoxDecoration(borderRadius: BorderRadius.circular(9), color: AppColors.navy2),
                      clipBehavior: Clip.antiAlias,
                      child: _photoThumbnail(_photos[i]),
                    ),
                    Positioned(
                      top: -6,
                      right: -6,
                      child: GestureDetector(
                        onTap: () => setState(() => _photos.removeAt(i)),
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: const BoxDecoration(color: AppColors.danger, shape: BoxShape.circle),
                          child: const Icon(Icons.close, size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        const SizedBox(height: 10),
        InkWell(
          onTap: _pickPhotos,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 26),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.borderStrong, width: 1.5),
              borderRadius: BorderRadius.circular(12),
              color: AppColors.bg,
            ),
            child: const Column(
              children: [
                Icon(Icons.add_photo_alternate_outlined, size: 28, color: AppColors.textFaint),
                SizedBox(height: 8),
                Text('اسحب الصور هنا أو اضغط للرفع',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.text)),
                SizedBox(height: 4),
                Text(
                  'تُستخدم هذه الصور لاحقًا في فرز الأولوية الهندسية',
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Renders a photo the user is CURRENTLY attaching — in-memory bytes,
  /// not yet uploaded. Compare with [_networkPhotoThumbnail], which loads
  /// an already-saved photo from its Storage URL.
  Widget _photoThumbnail(PlatformFile file) {
    final bytes = file.bytes;
    if (bytes == null) {
      return const Icon(Icons.image_not_supported_outlined, color: Colors.white70);
    }
    return Image.memory(bytes, fit: BoxFit.cover, width: 84, height: 84);
  }

  /// Prior history on this parcel (BR-3) — the case-level status rail
  /// (open/closed) PLUS the actual content of every prior complaint:
  /// narrative, photos, channel, date, and contact info.
  Widget _buildHistoryPanel() {
    return AppCardWithHeader(
      title: 'الحالات والبلاغات السابقة على هذا العقار',
      contentPadding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_priorCases.isNotEmpty) ...[
            TimelineRail(
              items: _priorCases
                  .map((c) => TimelineRailItem(
                        state: c.status == CaseStatus.closed ? RailItemState.done : RailItemState.current,
                        icon: c.status == CaseStatus.closed ? Icons.check : Icons.folder_open,
                        title: '${c.id} — ${c.status.label}',
                        meta: 'آخر تحديث: ${_fmt(c.closedAt ?? c.openedAt)}',
                      ))
                  .toList(),
            ),
          ],
          if (_priorComplaints.isNotEmpty) ...[
            if (_priorCases.isNotEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1)),
            const Text(
              'تفاصيل البلاغات السابقة',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.text),
            ),
            const SizedBox(height: 10),
            for (final c in _priorComplaints) _complaintHistoryCard(c),
          ],
        ],
      ),
    );
  }

  /// One prior complaint's full saved content — description AND media.
  Widget _complaintHistoryCard(Complaint c) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                switch (c.channel) {
                  ComplaintChannel.phone => Icons.call_outlined,
                  ComplaintChannel.walkIn => Icons.person_outline,
                  ComplaintChannel.officialReferral => Icons.assignment_outlined,
                },
                size: 14,
                color: AppColors.textMuted,
              ),
              const SizedBox(width: 5),
              Text(c.channel.label,
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
              const Spacer(),
              Text(_fmt(c.date), style: AppTypography.mono(fontSize: 11, color: AppColors.textMuted)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            c.narrative.isEmpty ? '(لا يوجد وصف)' : c.narrative,
            style: const TextStyle(fontSize: 12.5, color: AppColors.textBody, height: 1.6),
          ),
          if (c.complainantContact != null && c.complainantContact!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.contact_phone_outlined, size: 13, color: AppColors.textFaint),
                const SizedBox(width: 5),
                Text(c.complainantContact!, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
              ],
            ),
          ],
          if (c.photoUrls.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final url in c.photoUrls) _networkPhotoThumbnail(url)],
            ),
          ],
        ],
      ),
    );
  }

  /// A saved (already-uploaded) photo, loaded from its Storage download
  /// URL. Tapping enlarges it.
  Widget _networkPhotoThumbnail(String url) {
    return GestureDetector(
      onTap: () => showDialog(
        context: context,
        builder: (_) => Dialog(
          child: InteractiveViewer(child: Image.network(url)),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          url,
          width: 64,
          height: 64,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return const SizedBox(
              width: 64,
              height: 64,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          },
          errorBuilder: (context, error, stack) => Container(
            width: 64,
            height: 64,
            color: AppColors.navy2,
            child: const Icon(Icons.broken_image_outlined, color: Colors.white70, size: 20),
          ),
        ),
      ),
    );
  }

  String _fmt(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Turns a caught exception into a message that actually tells you what
  /// went wrong, instead of a generic "please try again."
  String _describeError(Object error, String prefix) {
    debugPrint('$prefix: $error');
    if (error is FirebaseException) {
      return '$prefix (${error.code})${error.message != null ? ': ${error.message}' : ''}';
    }
    return '$prefix: $error';
  }
}