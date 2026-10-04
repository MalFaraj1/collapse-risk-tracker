import 'dart:typed_data';
import 'package:excel/excel.dart';

import '../models/report_section.dart';

/// Builds a single-sheet, right-to-left .xlsx workbook from one or more
/// [ReportSection]s — every report's Excel export goes through this one
/// function, so styling (bold headers, RTL sheet) stays consistent.
///
/// A single untitled section is written as a plain table starting at A1
/// (ready to filter and pivot). Multiple sections are stacked, each with a
/// bold title row, separated by a blank row.
///
/// NOTE: written against the `excel` package's documented v4.x API
/// (`TextCellValue`, `Sheet.appendRow(List<CellValue?>)`, `Sheet.isRTL`,
/// `Excel.save()` returning `List<int>?`). If the resolved package
/// version differs, analysis will surface the exact mismatch.
Uint8List buildExcelWorkbook({
  required String sheetName,
  required List<ReportSection> sections,
}) {
  // Excel forbids  [ ] : * ? / \  in sheet names and caps them at 31 chars.
  var name = sheetName.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ').trim();
  if (name.isEmpty) name = 'التقرير';
  if (name.length > 31) name = name.substring(0, 31);

  final workbook = Excel.createExcel();
  final defaultSheet = workbook.getDefaultSheet();
  final sheet = workbook[name];
  if (defaultSheet != null && defaultSheet != name) {
    workbook.delete(defaultSheet);
  }
  sheet.isRTL = true;

  var rowIndex = 0;
  void boldRow(int columns) {
    for (var col = 0; col < columns; col++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: rowIndex)).cellStyle = CellStyle(bold: true);
    }
  }

  for (var i = 0; i < sections.length; i++) {
    final section = sections[i];
    if (section.title != null) {
      sheet.appendRow([TextCellValue(section.title!)]);
      boldRow(1);
      rowIndex++;
    }
    if (section.note != null) {
      sheet.appendRow([TextCellValue(section.note!)]);
      rowIndex++;
    }
    sheet.appendRow(section.headers.map<CellValue>((h) => TextCellValue(h)).toList());
    boldRow(section.headers.length);
    rowIndex++;
    for (final row in section.rows) {
      sheet.appendRow(row.map<CellValue>((c) => TextCellValue(c)).toList());
      rowIndex++;
    }
    if (i < sections.length - 1) {
      // An empty TEXT cell (not an empty row list) so the sheet's row count
      // really advances and later bold-header styling lands on the right row.
      sheet.appendRow([TextCellValue('')]);
      rowIndex++;
    }
  }

  final bytes = workbook.save();
  return Uint8List.fromList(bytes ?? []);
}