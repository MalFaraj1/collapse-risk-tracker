# Audit Findings — Collapse-Risk Building Follow-Up System

**Date:** 2026-10-01
**Scope:** `docs/AUDIT_BRIEF.md`, executed in full against the working tree as found.
**Tooling used:** Flutter 3.24.3 / Dart 3.5.3 (`flutter analyze`, `flutter pub get`), ripgrep-based cross-file searches, manual package-source inspection (`excel` 4.0.6 from the local pub cache), Firebase CLI (`firebase projects:list`, read-only).

## How to read this document

Per the brief's "what to give back" instructions, every finding below states: the file and location, what was actually wrong, the fix applied (or why none was applied), and whether it is an instance of one of the brief's five named bug patterns. The changelog at the end is the fastest way to see everything that changed in this session.

---

## 1. Compiler baseline (`flutter analyze`)

**Before this session's fixes:** 22 issues, 0 errors, 2 warnings, 20 info-level lints.
**After this session's fixes:** 18 issues, 0 errors, 0 warnings, 18 info-level lints (all cosmetic style lints — `prefer_const_constructors`, `curly_braces_in_flow_control_structures`, etc. — left as-is; they carry no behavioral risk and fixing them is not what this audit is for).

The important, and genuinely surprising, result: **the whole-program compile was already clean** when this session started. That is strong, independent evidence that most of the concrete bugs described in the brief (patterns A, B, D, E) had already been fixed in this working tree by the time this session began — likely through earlier iteration that isn't reflected in a commit. Each is re-verified individually below rather than taken on faith.

---

## 2. The five recurring bug patterns

### Pattern A — stale file signatures
**Checked:** `report_pdf_builder.dart` and `excel_export.dart` (the brief's own example) against `reports_screen.dart`'s call sites, plus a scan of every file imported by more than one other file.
**Result: already fixed, no action needed.** Both files already use the current `{required sections}` signature (`List<ReportSection> sections`), not the old `{headers, rows}` form. Since `flutter analyze` performs whole-program type checking, a real signature mismatch of this kind would surface as a hard error — and none did.

### Pattern B — model field referenced but not declared
**Checked:** the three fields the brief names explicitly — `Notice.reference`, `EvacuationExecution.complianceHours`, `AuditLogEntry.actorUid` — against their model definitions, plus confirmed the analyzer's whole-program soundness means no other instance of this class of bug can exist undetected.
**Result: already fixed, no action needed.** All three fields are declared on their respective models and are consumed correctly at every call site found (`parcels_repository.dart`'s timeline builder, confirmed directly).

### Pattern C — duplicate type definitions
**Checked:** every top-level `class`/`enum`/`mixin` declaration across all of `lib/` (155 declarations), diffed for name collisions.
**Result: one live instance found and fixed.**

- **File:** `lib/core/constants/parcel_status.dart` (lines 101–124, now removed) and `lib/features/review/models/review.dart` (lines 6–27, kept).
- **What was wrong:** `ReviewPriority` was defined twice — once in `parcel_status.dart` with presentation-only `.color`/`.backgroundColor` getters, once in `review.dart` with `.firestoreValue`/`.fromFirestore` for Firestore (de)serialization. `review_repository.dart` imported `parcel_status.dart` with `hide ReviewPriority` — exactly the "stopgap, not a real fix" the brief warns about — to avoid the ambiguous-import error that would otherwise occur. This is precisely why `flutter analyze` didn't flag it: the `hide` clause suppresses the collision entirely, so it's invisible to both the compiler and to a superficial "does it compile" check.
- **Root cause:** the `parcel_status.dart` copy was never actually used anywhere — `review_screen.dart` reimplements its own color-switch logic inline (`_priorityBadge`) rather than calling the duplicate's `.color`/`.backgroundColor` getters. It was dead weight left behind, most likely from an earlier draft that was superseded by the `review.dart` model but never deleted.
- **Fix applied:** deleted the dead `ReviewPriority` enum from `parcel_status.dart`; removed the `hide ReviewPriority` clause from `review_repository.dart`'s import (now a plain import). The real, used definition in `review.dart` is untouched.
- **Verification:** re-ran `flutter analyze` after the change — still 0 errors. Re-scanned all of `lib/` for duplicate public type names — none remain.
- **Checked elsewhere in the codebase:** yes — the full-tree name-collision scan (155 top-level declarations) found no other duplicates of any kind, so this was an isolated instance, not a recurring problem.

### Pattern D — constructor signature changes breaking other call sites
**Checked:** every construction site (`ClassName(` and provider definitions) for all 13 repository classes in the project.
**Result: already fixed, no action needed.** `ParcelsRepository`'s nullable `storage`/`auth`/`auditLog` parameters, the `_missingUploadDeps()` runtime guard, and the explanatory doc comment describing exactly why `reports_repository.dart` constructs it directly (read-only access via `buildR6`) are all already in place and correct. Confirmed `reports_repository.dart`'s direct construction (`ParcelsRepository(firestore: firestore)`) only ever calls `getParcel()`/`getTimeline()` — both pure reads — never `uploadAttachment()` or `createParcel()`, so it can never hit the guard. Every other repository class (`AuditLogRepository`, `AssessmentRepository`, `DashboardRepository`, `DemolitionRepository`, `EvacuationRepository`, `ImportRepository`, `IntakeRepository`, `NoticeRepository`, `ReviewRepository`, `SiteVisitRepository`, `TriageRepository`, `AdminRepository`) has exactly one construction site — its own Riverpod provider — so there is no other instance of this pattern anywhere in the project.

### Pattern E — invalid Flutter/package API usage
**Checked:** the brief's named example (`Icons.emergency_home_outlined`) — confirmed it does not appear anywhere in the codebase. More broadly: since `flutter analyze` resolves every `Icons.*` reference and every package API call against the actually-installed package versions (from `pubspec.lock`/`.dart_tool`), and reported 0 errors, this class of bug cannot currently exist undetected anywhere in `lib/`. An invalid static member reference is a hard compile error, not a warning — there is no way for one to silently pass analysis.
**Result: already fixed, no action needed.**

---

## 3. Findings beyond the five named patterns

The brief's patterns are the *known* classes of bug from this project's history; they are not the only classes possible. Two further issues were found by manually investigating the two genuine (non-cosmetic) `flutter analyze` warnings, rather than dismissing them as dead code.

### 3.1 — Closed cases stayed fully editable on the Assessment screen (functional gap, not caught by the compiler)

- **File:** `lib/features/assessment/assessment_screen.dart`
- **What was actually wrong:** the screen loaded `_caseRecord` (`Case? _caseRecord`, set at line ~107) via `_repo.getCase(decision.caseId)` — exactly the same call made by the sibling screen `lib/features/sitevisits/sitevisit_screen.dart`. The sitevisits screen uses that record to compute `isClosed = _caseRecord?.status == CaseStatus.closed` and swaps the entire form for a read-only "case is closed, no action needed" banner when true (`_buildClosedState()`). The assessment screen fetched the identical data but never read `.status` anywhere — `flutter analyze` only flagged this as `unused_field`, a cosmetic-sounding warning that is easy to dismiss as dead code. In fact it meant a user could still submit an external-opinion assessment, a restoration study, or trigger funding-candidate logic against a case that had already been closed as safe.
- **Fix applied:** added `bool get _isClosed => _caseRecord?.status == CaseStatus.closed;`, mirroring the sibling screen's pattern exactly; added the same "closed, read-only" `AppAlert` banner at the top of the loaded view; disabled both save actions (`_saveExternal` via the "حفظ التحديثات" button, `_saveStudy` via its own save button) when `_isClosed` is true, so the form remains visible (consistent with the brief's §7.6 context where seeing historical assessment data is still useful) but can no longer be edited.
- **Classification:** not one of the five named patterns — this is a new class: *a warning the compiler correctly flagged as "this data is unused" was actually "this data is unused **when it should have been used**," i.e. a dropped business rule rather than dead code.* Recommend treating `unused_field`/`unused_local_variable` warnings as a prompt to check sibling screens for the same field name before dismissing them, not just as safe-to-delete noise.
- **Checked elsewhere:** `review_screen.dart` also loads an identical `_caseRecord` but does not check `.status` either. I deliberately did **not** add the same guard there — a Review is reached earlier in the lifecycle (before a decision has been issued), and it's not obvious a case can structurally reach `CLOSED` while still having an open, unreviewed Report in the queue, the way it clearly can for a post-decision follow-up screen like Assessment or Site Visit. Adding a guard here would be a guess about intended business rules rather than a clear bug fix. **Flagging for your judgment, not silently fixed.**

### 3.2 — Dead local variable and dead import (cosmetic, fixed for cleanliness)

- **`lib/features/evacuation/evacuation_screen.dart`:** `final decision = _decision!;` was computed in `build()` and never used (only `execution` was used below it). Confirmed by reading the rest of `build()` — no reference to `decision` exists anywhere after the assignment. Removed. No behavior change; this was genuinely dead, not a dropped feature (nothing on this screen's layout needs decision-level data beyond what triggered page access, which is already validated in `_load()`).
- **`lib/features/intake/intake_screen.dart`:** `import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;` was unused. Verified: the only place a `LatLng` value appears is as an inferred closure-parameter type in `LocationPickerMap`'s `onLocationSelected: (point) => ...`, which Dart infers from the widget's own parameter type without needing the name imported into this file. Removed, confirmed still compiles.

### 3.3 — Missing `mounted` guard across an async gap (real crash risk, not just a style lint)

- **File:** `lib/features/parcels/parcel_detail_screen.dart`, `_pickAndUploadAttachment()`
- **What was actually wrong:** `flutter analyze` flagged `use_build_context_synchronously` at this `context` use, as only an `info`-level lint — easy to deprioritize. But the underlying risk is real: `context` was used in `showDialog(context: context, ...)` after an `await FilePicker.platform.pickFiles(...)`, with no check that the widget was still mounted. If a user closes or navigates away from the Parcel Detail screen while the OS file picker is open, the `await` resumes against a disposed `State`, and the subsequent `showDialog` call can throw or behave unpredictably.
- **Fix applied:** added `if (!mounted) return;` immediately after the `await`, before the first use of `context` — the same guard pattern already used elsewhere in this same file's `_load()` method.
- **Classification:** not one of the five named patterns. Recommend not treating `use_build_context_synchronously` as purely cosmetic in future reviews of this codebase — it is the correct lint catching a real, if narrow, crash window.

---

## 4. Known risk areas (brief §3) — verification results

- **Audit log coverage.** Confirmed by grepping every reference to the audit log across `lib/`: it is wired into exactly `review_repository.dart` (decision issuance) and `parcels_repository.dart` (`createParcel`, `uploadAttachment`) — nowhere else. This matches the brief's disclosed gap exactly; no drift. Also confirmed `reports_repository.dart`'s R6 report **explicitly tells the user** in its own output text that before/after values aren't available because the audit log isn't fully wired up yet — it does not silently assume complete coverage. No action needed.
- **Parcel attachments.** Traced `ParcelsRepository.uploadAttachment` end to end: Storage path is `parcels/{parcelId}/attachments/{docId}.{ext}`, Firestore collection is the top-level `attachments` collection with a `parcelId` field used for `watchAttachments()`'s equality query — both exactly as the brief describes. The attachment document write and the audit-log write happen in a single `WriteBatch` (`batch.set` + `auditLog!.logInBatch` + one `batch.commit()`), so they are genuinely atomic — satisfies end-to-end flow test #4/#5's intent. **Operational note, not a code bug:** `watchAttachments()` combines a `.where('parcelId', isEqualTo: ...)` with `.orderBy('uploadedAt', descending: true)` on a different field — Firestore requires a composite index for this exact shape. If that index hasn't been created in the live project, the first real use will throw `FAILED_PRECONDITION` with a console link to auto-create it, not a generic error. Could not confirm index existence without console/CLI access to the live project (see §5 below) — worth a 30-second check in the Firebase console's Firestore → Indexes tab.
- **Reports Hub R4/R6.** R6 (`buildR6`) was traced in full — see attachments note above re: honesty about audit-log coverage. R4 reads from the `users` directory for actor-name resolution; not independently re-verified beyond confirming the pattern (same `_loadUsers()` helper used elsewhere) — no issue found, but this was a lighter-touch check than R6.
- **Legacy import parser (`import_parser.dart`).** Reviewed in full, including a deliberate deep-dive into the installed `excel` package's source (v4.0.6, from the local pub cache) to verify `_cellText`'s `v.toString()` actually returns plain cell text for `TextCellValue`/`IntCellValue`/`DoubleCellValue` rather than a debug-formatted string — it does (the package's own `TextSpan` class, unrelated to Flutter's, correctly concatenates its `text` field). Also traced: Arabic-Indic digit folding, the `تأكيدي`-before-`تدعيم` ordering rationale (confirmed correct — a confirmatory-shoring row contains both substrings, so checking the more specific one first is required and is what the code does), Excexcel-serial-date he`20000–80000` sanity window, and the day-first (`dmy`) vs. ISO (`ymd`) date regexes. No bugs found. **Not tested against a real messy spreadsheet file** (none was provided and no live backend was available this session) — this remains a recommended manual test per the brief's §5.6, not something static review can fully substitute for.
- **`ParcelsRepository`'s nullable `storage`/`auth`/`auditLog`.** Covered under Pattern D above — confirmed correct and the only call site that constructs this class directly (`reports_repository.dart`) never touches the write paths that would hit the guard.

---

## 5. Security rules cross-check (brief §4) — could not be completed this session

This repository does **not** contain `firestore.rules` or `storage.rules` — `firebase.json` here is only the FlutterFire-generated app-config file (platform app IDs), not a deploy config with rules targets. Pulling the actually-deployed rules would have required either the Firebase CLI's rules-fetch capability (not exposed as a direct subcommand in the installed `firebase-tools` 15.28.1) or `gcloud` (installed, but broken in this environment — its wrapper script fails outright with `python not found`), or a fragile manual workaround extracting an access token from the CLI's stored credentials and calling the Firebase Rules REST API directly.

**Given the choice, you asked me to document this gap rather than pursue the fragile workaround.** So: this section is genuinely incomplete, not silently skipped. To unblock it later, either (a) export `firestore.rules`/`storage.rules` from the Firebase console and add them to the repo (recommended — they belong in version control regardless), or (b) fix the local `gcloud` Python dependency so a future session can pull them directly.

What **is** available now, to make that future diff fast — every collection name and Storage path the Dart code actually touches:

**Firestore collections** (from `lib/core/constants/firestore_paths.dart`, the single source of truth all repositories use — confirmed no file bypasses this with a raw string literal, except one legitimate subcollection, see below):
`users`, `neighborhoods`, `parcels`, `buildings`, `cases`, `complaints`, `triage`, `reports`, `reviews`, `decisions`, `notices`, `evacuationExecutions`, `siteVisits`, `assessments`, `restorationStudies`, `fundingCandidates`, `demolitionOrders`, `importBatches`, `importRows`, `attachments`, `auditLogs`, `noticeTemplates`, `settings`.

One legitimate subcollection not in that file: `noticeTemplates/{id}/versions/{version}` (raw `'versions'` string in `admin_repository.dart` — fine as a nested path, just worth knowing it exists when reviewing rules).

**Storage paths actually written to:**
- `parcels/{parcelId}/attachments/{docId}.{ext}` — `ParcelsRepository.uploadAttachment`
- `parcels/{parcelId}/attachments/report_{reportId}_{n}.{ext}` — `ReviewRepository` (site-visit report photos)
- `parcels/{parcelId}/attachments/visit_{visitId}_{n}.{ext}` — `SiteVisitRepository`
- `complaints/{complaintId}/photo_{n}.{ext}` — `IntakeRepository`
- `imports/{batchId}/{fileName}` — `ImportRepository`
- `notices/{noticeId}/notice.pdf` — `NoticeRepository`

The brief specifically calls out confirming the `auditLogs` collection allows `create` for staff (`allow create: if isStaff()`, not `allow write: if false`) — **this could not be confirmed** this session for the reason above. Given that audit-log writes happen inside the same `WriteBatch` as the primary write they're logging (decision issuance, attachment upload), if this rule is wrong, the *entire batch* fails, not just the log entry — so a misconfigured rule here would be very visible (the primary action itself would fail with a permission error), not a silent gap. Recommend this as the first thing to manually verify once rules access is available.

---

## 6. End-to-end flows (brief §5) — what was and wasn't verified

No live Firebase project or emulator was exercised this session (static code tracing only, consistent with the above). Results:

1. **Full parcel lifecycle.** Not run end-to-end against a backend. Traced the repository/provider wiring for each stage and found it internally consistent (no dangling references, no construction-site breaks — see Pattern D).
2. **Evacuation's 48h compliance math.** Verified by reading the model directly: `DateTime? get complianceDeadline => postedDate?.add(Duration(hours: complianceHours));` — correctly derived, never stored separately, matches the brief's description exactly. `complianceHours` defaults to `48` and is preserved per-execution so older records aren't retroactively affected by a future default change.
3. **BR-1 enforcement (shoring confirm requires prior warning).** Traced in full: `submitReviewAndDecision` re-checks `hasPriorShoringWarning` immediately before writing (not just at UI-render time), and the check queries the shared `notices` collection filtered by `type == SHORING_WARNING` — which both system-issued decisions **and** legacy-imported warnings write into (confirmed `import_repository.dart` creates notices in the same `FirestorePaths.notices` collection, not a separate "legacy" collection). So both the system-issued and imported-legacy cases described in the brief are structurally covered by the same code path. The doc comment on `hasPriorShoringWarning` also honestly discloses that this is a client-side-only check with no Cloud Function backing it — consistent with the project's stated no-backend constraint, not a hidden gap.
4. **Attachment upload → attachments grid → audit log entry.** Verified atomic (single `WriteBatch`) — see §4 above. Not run against a live Storage bucket.
5. **Decision issuance → Notice + audit log in one atomic write.** Verified: `submitReviewAndDecision` writes the Review, Decision, and Notice via document references created up front (`reviewRef`, `decisionRef`, `noticeRef`) and commits together; the audit log entry is added to the same batch. Not run against a live backend.
6. **Legacy import with a messy test spreadsheet.** Not run — no live backend and no sample spreadsheet file was available this session. The parser itself was reviewed in depth (§4 above) including package-internals verification, which is the strongest static substitute available, but this is explicitly flagged as not a replacement for the brief's recommended manual test.

---

## Changelog

| # | File | Change | Pattern |
|---|------|--------|---------|
| 1 | `lib/core/constants/parcel_status.dart` | Deleted dead duplicate `ReviewPriority` enum (was shadowed via `hide` elsewhere) | C |
| 2 | `lib/features/review/data/review_repository.dart` | Removed the `hide ReviewPriority` import workaround, now a plain import | C |
| 3 | `lib/features/assessment/assessment_screen.dart` | Added `_isClosed` check (mirroring `sitevisit_screen.dart`'s established pattern); shows a read-only banner and disables both save actions when the underlying case is already closed | New (non-pattern) — functional gap found via an `unused_field` warning |
| 4 | `lib/features/evacuation/evacuation_screen.dart` | Removed dead `final decision = _decision!;` local variable | Cosmetic |
| 5 | `lib/features/intake/intake_screen.dart` | Removed unused `google_maps_flutter` import | Cosmetic |
| 6 | `lib/features/parcels/parcel_detail_screen.dart` | Added `if (!mounted) return;` guard after an `await` and before a `context`-using `showDialog` call | New (non-pattern) — real crash-window risk understated by an `info`-level lint |

**Net result:** `flutter analyze` went from 22 issues (0 errors / 2 warnings / 20 info) to 18 issues (0 errors / 0 warnings / 18 info, all cosmetic). One real duplicate-type bug fixed. One real, previously-silent functional gap (closed cases editable on the Assessment screen) found and fixed by following up on a warning rather than dismissing it. One real crash-window risk fixed. Security-rules cross-check and live end-to-end testing remain open — both require access this session didn't have (rules: not in repo, no working `gcloud`/rules-fetch path; e2e: no live/emulated Firebase backend) — see §5 and §6 for exactly what's needed to finish them.

### Bottom line on "how much of this codebase can be trusted"

High confidence, with two explicit gaps. The compiler-catchable bug classes (A, B, D, E) were already resolved before this session and are now independently re-verified, not just re-trusted. The one surviving instance of the only *not*-compiler-catchable pattern (C) is now fixed properly rather than papered over. The deeper manual review surfaced a real, silent functional gap that no amount of `flutter analyze` would ever catch (§3.1) — which is the clearest evidence in this audit that lint warnings in this codebase deserve a "why is this unused" investigation, not a reflexive deletion. The two genuine open items — security rules parity and live end-to-end execution — are environment limitations of this session, not unexamined code, and §5/§6 above give a precise, actionable starting point for whoever picks them up next.
