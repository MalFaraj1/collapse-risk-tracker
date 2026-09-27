import 'dart:typed_data';
import 'package:excel/excel.dart';

/// Builds a single-sheet .xlsx workbook from a plain header row + data
/// rows — every report's Excel export goes through this one function, so
/// styling (bold header) stays consistent without each report
/// reimplementing it.
///
/// NOTE: written against the `excel` package's documented v4.x API
/// (`TextCellValue`, `Sheet.appendRow(List<CellValue?>)`,
/// `Excel.save()` returning `List<int>?`). If the resolved package
/// version in this project differs enough to change that surface,
/// `flutter pub get` will surface the exact mismatch at analysis time —
/// worth a quick check after first install, same as any new dependency.
Uint8List buildExcelWorkbook({
  required String sheetName,
  required List<String> headers,
  required List<List<String>> rows,
}) {
  final workbook = Excel.createExcel();
  final defaultSheet = workbook.getDefaultSheet();
  final sheet = workbook[sheetName];
  if (defaultSheet != null && defaultSheet != sheetName) {
    workbook.delete(defaultSheet);
  }

  sheet.appendRow(headers.map<CellValue>((h) => TextCellValue(h)).toList());
  for (final row in rows) {
    sheet.appendRow(row.map<CellValue>((c) => TextCellValue(c)).toList());
  }

  for (var col = 0; col < headers.length; col++) {
    final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0));
    cell.cellStyle = CellStyle(bold: true);
  }

  final bytes = workbook.save();
  return Uint8List.fromList(bytes ?? []);
}