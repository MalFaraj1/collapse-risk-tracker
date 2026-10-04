import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/report_section.dart';
import 'pdf_fonts.dart';

/// Builds a consistent "تقرير" PDF — a header (municipality name, title,
/// subtitle, generation date) followed by one table per [ReportSection].
/// Every report in the Reports Hub renders through this one function, so
/// every export looks and behaves the same way rather than each report
/// reinventing its own PDF layout.
///
/// Wide reports (more than five columns) switch to landscape so columns
/// stay readable.
///
/// NOTE: written against `pdf` package's documented v3.x table API
/// (`pw.TableHelper.fromTextArray`). If the resolved package version
/// differs, analysis will surface the exact mismatch.
Future<Uint8List> buildReportPdf({
  required String title,
  required String subtitle,
  required List<ReportSection> sections,
}) async {
  final doc = pw.Document(theme: await PdfFonts.theme());
  final now = DateTime.now();
  final generatedAt = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  final maxColumns = sections.fold<int>(0, (m, s) => s.headers.length > m ? s.headers.length : m);

  doc.addPage(
    pw.MultiPage(
      textDirection: pw.TextDirection.rtl,
      pageFormat: maxColumns > 5 ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      header: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('بلدية طرابلس \u2014 لجنة التحوّل الرقمي', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          pw.SizedBox(height: 4),
          pw.Text(title, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          if (subtitle.isNotEmpty) pw.Text(subtitle, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
          pw.SizedBox(height: 2),
          pw.Text('تاريخ الإصدار: $generatedAt', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
          pw.SizedBox(height: 8),
          pw.Divider(thickness: 1, color: PdfColors.grey400),
        ],
      ),
      build: (context) => [
        for (final section in sections) ...[
          if (section.title != null)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 6, bottom: 4),
              child: pw.Text(section.title!, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            ),
          if (section.note != null)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 6),
              child: pw.Text(section.note!, style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
            ),
          if (section.rows.isEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 14),
              child: pw.Text('لا توجد بيانات مطابقة ضمن النطاق المحدد.', style: const pw.TextStyle(fontSize: 10)),
            )
          else
            pw.TableHelper.fromTextArray(
              headers: section.headers,
              data: section.rows,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF1B2A4A)),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellAlignment: pw.Alignment.centerRight,
              headerAlignment: pw.Alignment.centerRight,
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            ),
          pw.SizedBox(height: 16),
        ],
      ],
    ),
  );

  return doc.save();
}