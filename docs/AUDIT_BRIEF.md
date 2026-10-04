# Audit Brief — Collapse-Risk Building Follow-Up System

## What this file is

This project was built across many long chat sessions with a different Claude instance that had no direct access to this codebase — it worked from pasted file contents and manual descriptions, never ran `flutter analyze` or a real compiler, and validated its own output with text-pattern heuristics (brace counting, regex symbol search) rather than actual Dart tooling. That gap produced a recurring, specific class of bug, documented below. Your job is to find and fix what that process couldn't catch, using the real tools you have (`flutter analyze`, `dart analyze`, actually running the app) that it never had.

Do not assume anything in this codebase compiles or works just because it looks complete or well-commented. Verify everything from first principles.

## Project context

- **What it is:** an internal POC web app for the Municipality of Tripoli tracking buildings at risk of collapse, from citizen complaint through enforcement (evacuation/shoring/restoration/demolition) to closure.
- **Stack:** Flutter Web, Firebase (Auth with custom claims + a `users` directory for RBAC, Firestore, Storage), Riverpod, go_router. No backend server and no Cloud Functions exist — several features (PDF generation, the audit log) are deliberately client-side with disclosed trade-offs; see doc comments in the code for exactly where and why.
- **Language/locale:** Arabic-only UI, RTL. Don't be surprised by Arabic string literals everywhere — that's intentional, not a bug.
- **Spec of record:** if a spec markdown/PDF is present in the repo or project files, treat it as ground truth for intended behavior (section references like "§7.5", "BR-7", "FR-EVC-2" in code comments point back to it).

## Your mission, in priority order

### 1. Get a real compiler's opinion first

Run `flutter analyze` (or `dart analyze`) across the whole `lib/` tree before doing anything else. Fix every error it reports. This alone will likely surface several issues no amount of manual review would catch — that's the whole point of using you instead of continuing the chat-based process.

### 2. Hunt specifically for these five recurring bug patterns

These aren't hypothetical — every single one of them actually happened during this project's development. Search for each pattern explicitly rather than assuming a general review will catch them.

**A. Stale files that "exist" but have an outdated signature.**
Several times, a file was declared "pre-existing, no changes needed" because it existed on disk, without checking whether its *content* still matched what newer code expected. Concretely: `report_pdf_builder.dart` and `excel_export.dart` were found to still use an old `{headers, rows}` function signature while `reports_screen.dart` had already been rewritten to call them with `{sections}`. **Action:** for every file that's imported by multiple other files, confirm its actual exported signatures match every call site — don't trust existence alone.

**B. A newer model field referenced by one file but missing from the model's actual definition in another.**
`parcels_repository.dart`'s timeline builder referenced `Notice.reference`, `EvacuationExecution.complianceHours`, and `AuditLogEntry.actorUid` at various points — fields that had been added to the canonical model file in one session but apparently never made it into the version actually sitting in the project. **Action:** for every field access (`.someField`) on a custom class, confirm that field is actually declared on that class's definition, not just assumed from a doc comment or prior chat message.

**C. Duplicate type definitions across files, causing ambiguous-import errors.**
`core/constants/parcel_status.dart` and `features/review/models/review.dart` both ended up defining an enum called `ReviewPriority`. Any file importing both broke with "name is defined in two libraries." **Action:** grep the whole `lib/` tree for duplicate `class`/`enum`/`mixin` names across different files. For each duplicate found, determine which one is actually used and remove or rename the other — don't just paper over it with an import `hide` clause (that was a stopgap, not a real fix).

**D. A constructor signature change that silently breaks a call site elsewhere in the codebase.**
When `ParcelsRepository`'s constructor gained new required parameters (`storage`, `auth`, `auditLog`) to support a new feature, a completely different file (`reports_repository.dart`) that constructed `ParcelsRepository` directly (bypassing its Riverpod provider) broke, because nobody checked for other call sites before changing the constructor. **Action:** before trusting that any class's constructor is safe, grep for every place that class is instantiated — directly (`ClassName(...)`) and via its provider — and confirm all of them still compile against the current signature.

**E. Invalid Flutter SDK API usage (wrong icon names, wrong method signatures) that looks plausible but doesn't exist.**
`Icons.emergency_home_outlined` was used in one file — it isn't a real Flutter Material icon name. **Action:** for anything referencing `Icons.*`, a package API (`pdf`, `excel`, `firebase_storage`, etc.), confirm it against the actual installed package version in `pubspec.lock`, not against what looks like a plausible name.

### 3. Specific known risk areas (recently built, less battle-tested)

These features are newer and have had fewer real eyes on them than the rest of the app:

- **Audit log** (`lib/features/audit/`) — currently wired into exactly two write paths: `ReviewRepository.submitReviewAndDecision` (issuing a decision) and `ParcelsRepository.createParcel` / `uploadAttachment`. Every other state-changing repository (Evacuation, Site Visit, Assessment, Demolition, Triage, Intake) does **not** yet log to the audit trail — this is a known, disclosed gap, not a bug, but confirm nothing else silently assumes audit coverage is complete.
- **Parcel attachments** (`ParcelsRepository.uploadAttachment`, the "المرفقات" card in `parcel_detail_screen.dart`) — brand new, never tested against a real Firebase project. Confirm the Storage path (`parcels/{parcelId}/attachments/{fileName}`) and Firestore collection (`attachments`) actually match your deployed security rules, and that upload → read-back → render (image/video/PDF tile) all genuinely work end to end.
- **Reports Hub R4 and R6** (`reports_repository.dart`) — these read from the `users` directory and from `ParcelsRepository.getTimeline()`'s `actorUid` field respectively. If actor attribution looks wrong or incomplete, check whether the relevant write sites actually populate `createdByUid`/`inspectorUid`/etc.
- **Legacy import** (`lib/features/imports/`) — the spreadsheet parser (`import_parser.dart`) handles Arabic/English headers, Arabic-Indic digits, and several date formats heuristically. Test it against a real messy spreadsheet, not just clean synthetic data.
- **`ParcelsRepository`'s nullable `storage`/`auth`/`auditLog`** — these were made nullable (see pattern D above) specifically so `reports_repository.dart`'s read-only direct construction keeps working. Confirm nothing else calls `uploadAttachment()` or `createParcel()` through a code path that doesn't go through `parcelsRepositoryProvider` (which always supplies all three) — that would hit the `_missingUploadDeps()` guard at runtime.

### 4. Verify the security rules match the code, in both directions

Pull the actual deployed Firestore and Storage rules and cross-check:
- Every collection name and field the Dart code reads/writes exists and is permitted by the rules.
- Every rule that exists is actually used by some code path (dead rules are a sign of a feature that was planned but never finished, or removed code that left rules behind).
- Pay specific attention to `auditLogs` — it requires `allow create: if isStaff()` (a deliberately weakened rule vs. a typical "server-only write" pattern) for the client-side audit logging to work at all. If this rule is still `allow write: if false`, every audit-logged action will fail silently or throw, depending on how errors are handled at each call site — check this explicitly.

### 5. End-to-end flow tests worth running manually

Beyond static analysis, actually exercise these flows against a real (or emulated) Firebase backend:
1. Full parcel lifecycle: complaint → triage → review/decision → one of each of the four enforcement actions → closure.
2. Evacuation's full 4-step sequence (post order, collect residents' data, send to relief, compliance visit) including the 48h compliance deadline math.
3. BR-1 enforcement: attempt a confirmatory shoring notice with no prior shoring warning (should block) and with one (should succeed) — for both a system-issued warning and an imported legacy one.
4. Upload an attachment and confirm it appears in both the attachments grid and generates an audit log entry.
5. Issue a decision and confirm it generates both a Notice and an audit log entry in the same atomic write.
6. Run a legacy import with a deliberately messy test spreadsheet (mixed Arabic/English headers, Arabic-Indic digits, a malformed row) and confirm the unmatched-row review flow works.

## What to give back

For each issue found, report:
- **File and exact location**
- **What's actually wrong** (not just "doesn't compile" — the root cause)
- **The fix applied**
- **Whether it's an isolated issue or an instance of one of the five patterns above** (if the latter, note whether you checked for other instances of the same pattern elsewhere in the codebase)

Don't silently patch and move on — a short changelog at the end summarizing everything found and fixed is more valuable here than a clean diff with no narrative, given the goal is also to understand how much of this codebase can actually be trusted.
