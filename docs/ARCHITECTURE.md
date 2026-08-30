# Architecture & Integration Guide

## Verification note — please read first

This project structure was built and checked without access to the Dart/Flutter
SDK (no internet in the build environment to install it), so **I could not run
`flutter analyze`, `flutter pub get`, or an actual compile.** What I did instead,
and what this does *not* substitute for:

- Verified every brace/paren/bracket is balanced, in every file.
- Verified every relative import path resolves to a real file.
- Verified every screen class the router references is actually defined.
- Verified every custom design-system widget used anywhere is actually defined,
  with matching constructor parameter names.
- Verified every `const` constructor call site has a matching `const` constructor
  declaration (a very common Dart compile error).

This catches most structural mistakes, but **it is not a substitute for actually
running `flutter pub get` && `flutter analyze` in your project** — do that as
the first step after integrating these files, and treat anything it flags as
real, not a false positive from my checks.

---

## Why Riverpod (not Provider or Bloc)

- **Compile-safe DI**: providers are plain top-level variables, so a typo or
  missing provider is a compile error, not a runtime "provider not found"
  crash — matters more here than usual since this is a safety-compliance
  system, not a prototype.
- **First-class async/stream support**: `StreamProvider` and `FutureProvider`
  map directly onto Firestore snapshots and Firebase Auth's `authStateChanges()`
  — see `auth_providers.dart` for exactly this pattern, which every feature's
  data layer should follow.
- **Testable without a widget tree**: providers can be overridden and tested
  in plain Dart tests, which matters for a 9-person team where different
  people need to test their feature in isolation.
- Bloc was considered and rejected for this project specifically: its
  ceremony (events → bloc → states) is more boilerplate than a 3-month POC
  team benefits from, and Riverpod already gives the same testability.

## Why go_router (not Navigator 1.0 / auto_route)

- **URL-based routes on Flutter Web** — `/parcels/PARCEL-4471-Z12` is a real,
  bookmarkable, shareable URL, not just an in-memory navigation stack.
- **Declarative redirect guards** — the entire authentication gate (`redirect:`
  in `router.dart`) is ~6 lines, and reacts automatically to sign-in/sign-out
  via `refreshListenable`, without any screen needing to manually navigate.

## Folder structure

```
lib/
  main.dart                    Firebase init + app entry point
  firebase_options.dart        ⚠️ PLACEHOLDER — see below, do not use as-is
  app/
    app.dart                   MaterialApp.router, RTL, theme wiring
    router.dart                All routes + the auth redirect guard
    theme/
      app_colors.dart          Color tokens (ported from the approved design)
      app_typography.dart      Cairo + JetBrains Mono type system
      app_spacing.dart         Spacing/radius tokens
      app_theme.dart           Assembles tokens into a real ThemeData
  core/
    constants/
      parcel_status.dart       State-machine enum, colors + Arabic labels baked in
      roles.dart                RBAC enum — values MUST match the Firestore
                                 security rules and the setUserRole Cloud Function
      firestore_paths.dart      Collection name constants — single source of
                                 truth, MUST match firestore.rules
    widgets/                    The reusable design-system component library —
                                 see "Design system" below
  features/
    auth/                       ✅ Fully implemented (login + role/auth providers)
    dashboard/                  ✅ Fully implemented (reference example, mock data)
    parcels/                    ✅ Fully implemented (list + detail/timeline,
                                 reference example, mock data)
    intake/ triage/ review/ notices/ evacuation/ sitevisits/
    assessment/ demolition/ imports/ reports/ admin/
                                 🚧 Clean stubs (ComingSoonScreen) — see each
                                 file's spec reference and TODO comment
```

## Design system — what's implemented and how to use it

Every reusable component lives in `core/widgets/`. **Do not style a raw
`Container`/`ElevatedButton`/`Card` in a feature screen** — reach for these
instead, so every screen stays visually consistent with the approved design
without anyone needing to remember the exact hex values or paddings:

| Widget | Use for |
|---|---|
| `AppButton` (5 variants) | Every button in the app |
| `AppCard` / `AppCardWithHeader` | Any grouped content block |
| `PageHeader` | The title + subtitle + actions row at the top of every screen |
| `StatCard` | Dashboard KPI tiles |
| `StatusBadge` | Any `ParcelStatus` value — color always comes from the enum |
| `Pill` / `RolePill` | Ad hoc status pills not covered by `ParcelStatus` |
| `AppAlert` | Business-rule explanations, warnings, confirmations |
| `CountdownRing` | **Signature component** — any hard deadline (BR-4, BR-7) |
| `TimelineRail` | **Signature component** — any sequential history view |
| `ComingSoonScreen` | Placeholder body for a not-yet-built feature screen |

## Integrating this into your existing project

You already have a Flutter Web project with Firebase wired up. To bring this
structure in:

1. **Do not overwrite** your real `lib/firebase_options.dart` — the one in
   this package is a deliberately broken placeholder (see the giant warning
   comment inside it). Keep your generated one.
2. Copy `lib/app/`, `lib/core/`, `lib/features/` into your project's `lib/`.
3. Merge `pubspec.yaml` — add the dependencies listed here to your existing
   file rather than overwriting it (you likely already have `firebase_core`,
   `firebase_auth`, `cloud_firestore`, `firebase_storage` from your earlier
   connection testing).
4. Replace your existing `lib/main.dart` with this one (or merge if you've
   already added other setup there).
5. Run `flutter pub get`, then `flutter analyze` — fix anything it flags
   before writing new feature code on top of this.
6. Run `flutter run -d chrome` and confirm: the login screen appears, signing
   in with your bootstrapped Admin account lands you on the dashboard, and
   the sidebar shows every nav group (since Admin sees everything per
   Appendix A).

## What to build next (per feature stub)

Each stub screen's file-level doc comment names its exact spec section and
business rules. Follow the same pattern the two reference screens
(`dashboard_screen.dart`, `parcel_detail_screen.dart`) demonstrate: a
`StreamProvider` in the feature's own `_providers.dart` reading from the
relevant Firestore collection (see `core/constants/firestore_paths.dart`),
consumed by a `ConsumerWidget` screen built from the `core/widgets/`
component library.

**Using an AI coding assistant to build a screen?** See
[`docs/AI_PROMPTING_GUIDE.md`](AI_PROMPTING_GUIDE.md) first — it lists the
exact context every prompt needs (the functional spec section, the security
rules, a reference screen, the design-system files) plus three worked
examples, so AI-assisted screens actually integrate with what's already
built instead of drifting into their own style.
