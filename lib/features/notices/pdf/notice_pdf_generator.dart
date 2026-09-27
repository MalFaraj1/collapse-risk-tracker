import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/pdf/pdf_fonts.dart';
import '../../intake/models/parcel.dart';
import '../../review/models/decision.dart';
import '../../review/models/notice.dart';

/// Renders one official notice as a real PDF, matching the exact layout
/// already shown on-screen in Notice Preview — same municipal header,
/// same underlined title, same key-value rows, same legal body text,
/// same signature footer. The title and body text are passed in rather
/// than recomputed here, so Notice Preview's own `noticeTitle`/`_bodyText`
/// logic remains the single place that owns that wording per decision
/// type — this generator only lays it out.
Future<Uint8List> buildNoticePdf({
  required Notice notice,
  required Decision decision,
  required Parcel parcel,
  required String noticeTitle,
  required String bodyText,
  String? linkedWarningShortId,
}) async {
  final doc = pw.Document(theme: await PdfFonts.theme());
  String fmt(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  final shortId = (notice.id.length <= 8 ? notice.id : notice.id.substring(0, 8)).toUpperCase();

  doc.addPage(
    pw.Page(
      textDirection: pw.TextDirection.rtl,
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text('بلدية طرابلس', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)),
          pw.SizedBox(height: 3),
          pw.Text(
            'لجنة التحوّل الرقمي — متابعة المباني الآيلة للسقوط',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 22),
          pw.Text(
            noticeTitle,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 15, decoration: pw.TextDecoration.underline),
          ),
          pw.SizedBox(height: 22),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              _kv('رقم العقار', parcel.parcelNo),
              _kv('المنطقة العقارية', parcel.cadastralZone),
              _kv('العنوان', parcel.address),
              _kv('رقم الإشعار وتاريخه', '$shortId \u00b7 ${fmt(notice.createdAt ?? decision.executionDate)}'),
              _kv('المهلة القانونية للتنفيذ', 'حتى ${fmt(decision.executionDate)}'),
              if (linkedWarningShortId != null) _kv('الإنذار الأصلي المرجعي', linkedWarningShortId),
            ],
          ),
          pw.SizedBox(height: 22),
          pw.Text(bodyText, textAlign: pw.TextAlign.justify, style: const pw.TextStyle(fontSize: 11, lineSpacing: 3)),
          pw.SizedBox(height: 60),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('ختم البلدية', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
              pw.Text('توقيع المسؤول الهندسي', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
            ],
          ),
        ],
      ),
    ),
  );

  return doc.save();
}

pw.Widget _kv(String k, String v) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 5),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(k, style: const pw.TextStyle(fontSize: 10.5, color: PdfColors.grey700)),
        pw.Text(v, style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
      ],
    ),
  );
}