import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../../review/models/decision.dart';
import '../models/import_models.dart';

/// The uploaded file can't be read as a legacy-warnings spreadsheet at all
/// (wrong format, or a required column is missing). Its message is shown
/// to the user as-is, so it is written for them, not for developers.
class ImportFormatException implements Exception {
  ImportFormatException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Reads a spreadsheet (.xlsx or .csv) of legacy warnings and validates
/// every row against the minimum fields — parcel number, cadastral zone,
/// warning type, date (FR-IMP-1, OQ-4). Pure logic: no Firestore, no UI.
///
/// Deliberately forgiving about how a paper-era spreadsheet was typed:
/// Arabic or English column headers in any of several spellings, Arabic-
/// Indic digits, several date layouts (including Excel's serial numbers),
/// and Arabic or English warning-type wording.
class ImportParser {
  ImportParser._();

  static List<ParsedImportRow> parse(Uint8List bytes, String fileName) {
    final ext = fileName.toLowerCase().split('.').last;
    final List<List<String>> grid;
    if (ext == 'csv') {
      grid = _readCsv(bytes);
    } else if (ext == 'xlsx') {
      grid = _readXlsx(bytes);
    } else {
      throw ImportFormatException('صيغة الملف غير مدعومة — استخدم ملف Excel (.xlsx) أو CSV.');
    }

    final nonEmpty = grid.where((r) => r.any((c) => c.trim().isNotEmpty)).toList();
    if (nonEmpty.length < 2) {
      throw ImportFormatException('الملف فارغ أو لا يحتوي إلا على صف العناوين.');
    }

    // The first non-empty row is the header row.
    final headerRowIndex = grid.indexOf(nonEmpty.first);
    final header = grid[headerRowIndex].map(_norm).toList();
    int col(Set<String> names) => header.indexWhere(names.contains);

    final parcelCol = col(_parcelNames);
    final zoneCol = col(_zoneNames);
    final typeCol = col(_typeNames);
    final dateCol = col(_dateNames);
    final refCol = col(_referenceNames);

    final missing = <String>[
      if (parcelCol < 0) 'رقم العقار',
      if (zoneCol < 0) 'المنطقة العقارية',
      if (typeCol < 0) 'نوع الإنذار',
      if (dateCol < 0) 'التاريخ',
    ];
    if (missing.isNotEmpty) {
      throw ImportFormatException('أعمدة مطلوبة غير موجودة في الملف: ${missing.join('، ')}.');
    }

    String cell(List<String> row, int index) => (index >= 0 && index < row.length) ? row[index].trim() : '';

    final rows = <ParsedImportRow>[];
    for (var i = headerRowIndex + 1; i < grid.length; i++) {
      final r = grid[i];
      if (r.every((c) => c.trim().isEmpty)) continue;
      rows.add(buildRow(
        rowNumber: i + 1,
        parcelRaw: cell(r, parcelCol),
        zoneRaw: cell(r, zoneCol),
        typeRaw: cell(r, typeCol),
        dateRaw: cell(r, dateCol),
        reference: cell(r, refCol),
      ));
    }
    if (rows.isEmpty) throw ImportFormatException('لا توجد صفوف بيانات بعد صف العناوين.');
    return rows;
  }

  /// Validates one row's four minimum fields. Public because the manual
  /// review dialog re-validates a corrected row with the same rules.
  static ParsedImportRow buildRow({
    required int rowNumber,
    required String parcelRaw,
    required String zoneRaw,
    required String typeRaw,
    required String dateRaw,
    String? reference,
  }) {
    final parcelNo = _cleanId(parcelRaw);
    final zone = _cleanId(zoneRaw).toUpperCase();
    final type = parseType(typeRaw);
    final date = parseDate(dateRaw);

    final errors = <String>[
      if (parcelNo.isEmpty) 'رقم العقار مفقود',
      if (zone.isEmpty) 'المنطقة العقارية مفقودة',
      if (type == null) (typeRaw.trim().isEmpty ? 'نوع الإنذار مفقود' : 'نوع الإنذار غير معروف'),
      if (date == null) 'التاريخ مفقود أو غير صالح',
    ];

    return ParsedImportRow(
      rowNumber: rowNumber,
      parcelNoRaw: parcelRaw,
      zoneRaw: zoneRaw,
      typeRaw: typeRaw,
      dateRaw: dateRaw,
      reference: (reference == null || reference.trim().isEmpty) ? null : reference.trim(),
      parcelNo: parcelNo.isEmpty ? null : parcelNo,
      zone: zone.isEmpty ? null : zone,
      type: type,
      date: date,
      error: errors.isEmpty ? null : errors.join(' · '),
    );
  }

  // --- Warning type ------------------------------------------------------------

  /// Maps free-form wording to one of the four action types. Order matters:
  /// "تأكيدي بالتدعيم" contains "تدعيم", so the confirmatory form is
  /// checked first; a bare "تدعيم" is a plain shoring warning.
  static DecisionAction? parseType(String raw) {
    final n = _norm(raw);
    if (n.isEmpty) return null;
    if (n.contains('تاكيدي') || n.contains('confirm')) return DecisionAction.shoringConfirm;
    if (n.contains('ترميم') || n.contains('restor')) return DecisionAction.restorationWarning;
    if (n.contains('تدعيم') || n.contains('shoring')) return DecisionAction.shoringWarning;
    if (n.contains('اخلاء') || n.contains('evacuat')) return DecisionAction.evacuation;
    return null;
  }

  // --- Dates ---------------------------------------------------------------------

  static DateTime? parseDate(String raw) {
    final s = _westernDigits(raw).trim();
    if (s.isEmpty) return null;

    // Excel stores dates as day counts since 1899-12-30.
    final serial = double.tryParse(s);
    if (serial != null) {
      if (serial > 20000 && serial < 80000) {
        final d = DateTime(1899, 12, 30).add(Duration(days: serial.floor()));
        return _plausible(d) ? d : null;
      }
      return null;
    }

    DateTime? build(int y, int m, int d) {
      if (m < 1 || m > 12 || d < 1 || d > 31) return null;
      final date = DateTime(y, m, d);
      if (date.month != m || date.day != d) return null; // e.g. 31 Feb rolled over
      return _plausible(date) ? date : null;
    }

    final ymd = RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})').firstMatch(s);
    if (ymd != null) return build(int.parse(ymd.group(1)!), int.parse(ymd.group(2)!), int.parse(ymd.group(3)!));

    // Lebanese convention: day first.
    final dmy = RegExp(r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})').firstMatch(s);
    if (dmy != null) return build(int.parse(dmy.group(3)!), int.parse(dmy.group(2)!), int.parse(dmy.group(1)!));

    return null;
  }

  static bool _plausible(DateTime d) => d.year >= 1970 && d.isBefore(DateTime.now().add(const Duration(days: 366)));

  // --- Text helpers --------------------------------------------------------------

  static String _westernDigits(String s) {
    const arabicIndic = '٠١٢٣٤٥٦٧٨٩';
    const extended = '۰۱۲۳۴۵۶۷۸۹';
    final b = StringBuffer();
    for (final ch in s.split('')) {
      final a = arabicIndic.indexOf(ch);
      final e = extended.indexOf(ch);
      b.write(a >= 0 ? '$a' : (e >= 0 ? '$e' : ch));
    }
    return b.toString();
  }

  /// Lower-cases, strips spaces/underscores/dashes/tatweel/diacritics and
  /// folds the alef variants, so header and wording comparisons don't
  /// depend on how something was typed.
  static String _norm(String s) => _westernDigits(s)
      .toLowerCase()
      .replaceAll(RegExp(r'[\s_\-\u0640\u064B-\u065F]+'), '')
      .replaceAll(RegExp('[أإآ]'), 'ا')
      .replaceAll('ى', 'ي');

  /// Cleans an identifier cell: Arabic digits → Western, "4471.0" (Excel's
  /// habit for whole numbers) → "4471", and "—"/"-" placeholders → empty.
  static String _cleanId(String raw) {
    var s = _westernDigits(raw).trim();
    if (RegExp(r'^\d+\.0+$').hasMatch(s)) s = s.split('.').first;
    if (RegExp(r'^[-–—\s]*$').hasMatch(s)) return '';
    return s;
  }

  static final _parcelNames = {'رقم العقار', 'العقار', 'parcel_no', 'parcelno', 'parcel number', 'parcel'}.map(_norm).toSet();
  static final _zoneNames = {'المنطقة العقارية', 'المنطقة', 'cadastral_zone', 'cadastralzone', 'zone'}.map(_norm).toSet();
  static final _typeNames = {'نوع الإنذار', 'نوع الانذار', 'النوع', 'نوع', 'warning_type', 'type'}.map(_norm).toSet();
  static final _dateNames = {'التاريخ', 'تاريخ الإنذار', 'تاريخ', 'date', 'warning_date'}.map(_norm).toSet();
  static final _referenceNames = {'المرجع', 'رقم المرجع', 'reference', 'ref'}.map(_norm).toSet();

  // --- File readers --------------------------------------------------------------

  static List<List<String>> _readXlsx(Uint8List bytes) {
    final Excel excel;
    try {
      excel = Excel.decodeBytes(bytes);
    } catch (_) {
      throw ImportFormatException('تعذّرت قراءة ملف Excel — تأكد أنه بصيغة .xlsx سليمة وغير محمي بكلمة مرور.');
    }
    for (final table in excel.tables.values) {
      final rows = [for (final row in table.rows) [for (final c in row) _cellText(c)]];
      if (rows.any((r) => r.any((c) => c.trim().isNotEmpty))) return rows;
    }
    return const [];
  }

  static String _cellText(Data? cell) {
    final v = cell?.value;
    if (v == null) return '';
    if (v is DateCellValue) return '${v.year}-${v.month}-${v.day}';
    if (v is DateTimeCellValue) return '${v.year}-${v.month}-${v.day}';
    return v.toString();
  }

  static List<List<String>> _readCsv(Uint8List bytes) {
    var text = utf8.decode(bytes, allowMalformed: true);
    if (text.startsWith('\uFEFF')) text = text.substring(1);

    final firstLine = text.split('\n').first;
    final delimiter = [',', ';', '\t'].reduce((a, b) => firstLine.split(a).length >= firstLine.split(b).length ? a : b);

    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var inQuotes = false;

    void endField() {
      row.add(field.toString());
      field.clear();
    }

    void endRow() {
      endField();
      rows.add(row);
      row = <String>[];
    }

    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          field.write(ch);
        }
      } else if (ch == '"') {
        inQuotes = true;
      } else if (ch == delimiter) {
        endField();
      } else if (ch == '\n') {
        endRow();
      } else if (ch != '\r') {
        field.write(ch);
      }
    }
    if (field.isNotEmpty || row.isNotEmpty) endRow();
    return rows;
  }
}