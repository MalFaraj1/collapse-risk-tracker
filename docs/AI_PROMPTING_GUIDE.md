# AI Prompting Guide — How to Ask an AI to Build a Screen

This document exists so all 9 of us get consistent, correctly-integrated code out
of an AI coding assistant, regardless of who's prompting it or which screen
they're building. Skipping the checklist below is the single most common way
AI-generated Flutter code technically "works" but doesn't fit this project —
wrong state-management pattern, restyled buttons instead of reusing
`AppButton`, a Firestore query that the security rules will silently reject,
etc.

---

## Does your AI tool have direct access to the repo?

This changes *how* you supply context, not *what* you supply.

- **Agentic tools with file access** (Claude Code, Cursor, GitHub Copilot
  Workspace, etc.): point them at the file paths listed below directly — e.g.
  "read `lib/features/dashboard/dashboard_screen.dart` and
  `docs/ARCHITECTURE.md` before starting." They read the files themselves.
- **Plain chat AI with no repo access** (a web chat window): you must
  manually attach or paste the relevant files every time. This is where
  skipping something in the checklist is easy to do by accident — go through
  it explicitly.

Either way, the underlying bundle of context is identical. The checklist
below applies to both.

---

## The context bundle — attach every item, every time

| # | What | Why the AI needs it |
|---|---|---|
| 1 | The relevant screen's section from `Screen-by-Screen Functional Specification.docx` (just that section, not the whole document) | The overview, business rules, and the ready-made "Prompt for AI Code Generation" paragraph for that exact screen |
| 2 | `docs/ARCHITECTURE.md` | So it uses Riverpod + go_router the way this project already decided to, not whatever the model defaults to |
| 3 | `lib/app/theme/app_colors.dart`, `app_typography.dart`, `app_theme.dart`, and everything in `lib/core/widgets/` | So it reuses `AppButton`, `AppCard`, `StatusBadge`, `CountdownRing`, `TimelineRail`, etc. instead of inventing new styled widgets |
| 4 | `lib/core/constants/parcel_status.dart`, `roles.dart`, `firestore_paths.dart` | The exact enum values, role strings, and collection names — these must match the security rules character-for-character |
| 5 | `firestore.rules` and `storage.rules` | So generated queries/writes are actually authorized, and so it knows which paths are server-write-only (e.g. never write directly to `notices/` or `reports/exports/`) |
| 6 | **One already-built reference screen** — `lib/features/dashboard/dashboard_screen.dart` or `lib/features/parcels/parcel_detail_screen.dart` | The actual coding pattern to copy: how a provider is written, how a screen consumes it, how widgets are composed |
| 7 | The current stub file for the screen being built (e.g. `lib/features/evacuation/evacuation_screen.dart`) | So it edits/replaces the existing `ComingSoonScreen` stub in place, instead of creating a new, slightly-differently-named file |

If you're not sure an item applies (e.g. a screen with no Storage usage),
include it anyway — a security rules file the AI doesn't need to touch is
harmless; a security rules file it needed but didn't have leads to code that
looks correct and fails at runtime.

---

## The task instruction — what varies per screen

On top of the bundle, write an explicit instruction. Keep every one of these
five parts:

1. **Which screen, in Arabic and English, and which file to edit.**
2. **Which reference screen's pattern to copy.**
3. **Which spec section governs it** (so it doesn't invent requirements).
4. **Any signature component it must reuse** (`CountdownRing`, `TimelineRail`)
   rather than rebuild.
5. **A closing instruction to stop and ask rather than guess on ambiguity.**
   This single line prevents more integration problems across 9 people's
   independent AI sessions than anything else on this list.

---

## Worked examples

### Example 1 — Evacuation Execution (uses a signature component)

```
Implement the "تنفيذ الإخلاء" (Evacuation Execution) screen.
File to edit: lib/features/evacuation/evacuation_screen.dart
(currently a ComingSoonScreen stub — replace its contents)

Follow the pattern in lib/features/dashboard/dashboard_screen.dart exactly:
a Riverpod StreamProvider reading from Firestore, consumed by a
ConsumerWidget, built from the existing core/widgets/ components.

Requirements are in section 8 of the attached Functional Specification.
Reuse CountdownRing for the 48-hour compliance clock — compute the deadline
as postedDate + 48 hours, do not store it as a separate field.
Reuse AppCard and the checklist-row pattern; do not create new card or
list styling.

Only Police and Admin can write to evacuationExecutions — match this
against the attached firestore.rules exactly.

Do not add any package not already in pubspec.yaml. If something in the
spec is ambiguous, stop and ask rather than guessing.
```

### Example 2 — Review & Decision (a business-rule-critical screen)

```
Implement the "المراجعة والقرار" (Review & Decision) screen.
File to edit: lib/features/review/review_screen.dart

Follow the pattern in lib/features/parcels/parcel_detail_screen.dart for
how to structure a ConsumerWidget with a side panel + main content layout.

Requirements are in section 6 of the attached Functional Specification.

This screen enforces Business Rule BR-1: the "تأكيدي بالتدعيم" (Confirmatory
Shoring) option must be shown as visually disabled, with the exact reason
displayed inline, whenever no prior Shoring Warning notice exists for this
parcel. Do NOT implement this check as client-side-only logic that merely
toggles the UI — the actual write must be rejected by a Cloud Function too;
the UI check is only for user experience. If no such Cloud Function exists
yet in this codebase, say so explicitly instead of silently skipping that
half of the requirement.

Reuse StatusBadge and AppAlert for the rule explanation callout — do not
build a new alert-box widget.

If anything about how the prior-warning check should be structured is
unclear, stop and ask rather than guessing.
```

### Example 3 — Reports Hub (read-only, cross-cutting)

```
Implement the "التقارير" (Reports Hub) screen.
File to edit: lib/features/reports/reports_screen.dart

Follow the pattern in lib/features/parcels/parcels_list_screen.dart for how
a screen reads and displays Firestore data via a StreamProvider.

Requirements are in section 13 of the attached Functional Specification —
this covers all seven reports (R1–R7).

Every export (PDF and Excel) must be triggered client-side but generated
server-side — do not attempt to assemble a PDF or spreadsheet directly in
Dart/Flutter. Assume a Cloud Function named generateReport(reportId,
filters) exists or needs to be requested from whoever owns Cloud Functions
on this project; the Flutter side only calls it and then downloads the
resulting file from Storage.

Reuse AppCard for each report tile and AppButton for the export actions.

If the generateReport Cloud Function doesn't exist yet, build the UI to
call it as if it does, and clearly list what the function needs to accept
and return, rather than inventing a client-side export mechanism.
```

---

## After the AI generates code

Before merging, whoever wrote the prompt (not a different reviewer) should
confirm:

- [ ] It imports and reuses `core/widgets/` components — no new one-off
      styled `Container`/`ElevatedButton`/`Card` that duplicates something
      already in the design system.
- [ ] Enum values, role strings, and collection names match
      `parcel_status.dart` / `roles.dart` / `firestore_paths.dart` exactly —
      no invented status strings or slightly-renamed collections.
- [ ] Any cross-document business rule (anything with a BR-# in the spec) is
      flagged as needing server-side enforcement, not left as client-only.
- [ ] The file structure matches `docs/ARCHITECTURE.md` — the right
      provider file, the right screen file, nothing dropped in `lib/` root.
- [ ] It actually replaces the `ComingSoonScreen` stub rather than leaving
      it alongside a new, separate file.

If the AI skipped or guessed at anything instead of asking, that's a sign
the prompt was missing one of the seven context items above — not that the
AI made a one-off mistake. Fix the prompt, not just the output, so the next
person prompting for a different screen doesn't hit the same gap.
