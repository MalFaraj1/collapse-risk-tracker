/// One table inside a report. Most reports are a single table; some need
/// more (R2 counts by status AND by action type; R4 by team AND by user;
/// R6 a parcel summary followed by its timeline). Both export builders
/// take a list of these, so every format renders every report the same way.
class ReportSection {
  const ReportSection({this.title, this.note, required this.headers, required this.rows});

  /// Heading printed above the table (omit for a single-table report).
  final String? title;

  /// A short caveat printed under the heading — used to state honestly
  /// what a report does NOT contain.
  final String? note;
  final List<String> headers;
  final List<List<String>> rows;
}

class ReportResult {
  const ReportResult(this.sections);

  ReportResult.single({required List<String> headers, required List<List<String>> rows})
      : sections = [ReportSection(headers: headers, rows: rows)];

  final List<ReportSection> sections;

  /// Total data rows across every section.
  int get rowCount => sections.fold(0, (sum, s) => sum + s.rows.length);
}