import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'pdf_fonts.dart';

/// Builds a plain, consistent "تقرير" PDF — a header (municipality name,
/// title, subtitle, generation date) followed by a data table. Every
/// report in the Reports Hub renders through this one function, so every
/// export looks and behaves the same way rather than each report
/// reinventing its own PDF layout.
///
/// NOTE: written against `pdf` package's documented v3.x table API
/// (`pw.TableHelper.fromTextArray`, the current name for what older
/// versions called `pw.Table.fromTextArray`). If the resolved package
/// version differs, `flutter pub get` / analysis will surface the exact
/// mismatch — worth a quick check after first install, same as any new
/// dependency.
Future<Uint8List> buildReportPdf({
  required String title,
  required String subtitle,
  required List<String> headers,
  required List<List<String>> rows,
}) async {
  final doc = pw.Document(theme: await PdfFonts.theme());
  final now = DateTime.now();
  final generatedAt = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

  doc.addPage(
    pw.MultiPage(
      textDirection: pw.TextDirection.rtl,
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      header: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('بلدية طرابلس \u2014 لجنة التحوّل الرقمي', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          pw.SizedBox(height: 4),
          pw.Text(title, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.Text(subtitle, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
          pw.SizedBox(height: 2),
          pw.Text('تاريخ الإصدار: $generatedAt', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
          pw.SizedBox(height: 8),
          pw.Divider(thickness: 1, color: PdfColors.grey400),
        ],
      ),
      build: (context) => [
        if (rows.isEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 24),
            child: pw.Text('لا توجد بيانات مطابقة ضمن النطاق المحدد لهذا التقرير.', style: const pw.TextStyle(fontSize: 11)),
          )
        else
          pw.TableHelper.fromTextArray(
            headers: headers,
            data: rows,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF1B2A4A)),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignment: pw.Alignment.centerRight,
            headerAlignment: pw.Alignment.centerRight,
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          ),
      ],
    ),
  );

  return doc.save();
}