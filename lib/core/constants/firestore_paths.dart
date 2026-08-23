/// Firestore collection names — the single source of truth.
///
/// These string values MUST match the `match /{collection}/{id}` paths in
/// `firestore.rules` exactly. If you rename a collection here, rename it in
/// the security rules too, or every read/write silently starts failing
/// permission checks against a collection the rules don't recognize.
abstract class FirestorePaths {
  FirestorePaths._();

  static const users = 'users';
  static const parcels = 'parcels';
  static const buildings = 'buildings';
  static const cases = 'cases';
  static const complaints = 'complaints';
  static const triage = 'triage';
  static const reports = 'reports';
  static const reviews = 'reviews';
  static const decisions = 'decisions';
  static const notices = 'notices';
  static const evacuationExecutions = 'evacuationExecutions';
  static const siteVisits = 'siteVisits';
  static const assessments = 'assessments';
  static const restorationStudies = 'restorationStudies';
  static const fundingCandidates = 'fundingCandidates';
  static const demolitionOrders = 'demolitionOrders';
  static const importBatches = 'importBatches';
  static const importRows = 'importRows';
  static const attachments = 'attachments';
  static const auditLogs = 'auditLogs';
  static const noticeTemplates = 'noticeTemplates';
  static const settings = 'settings';
}
