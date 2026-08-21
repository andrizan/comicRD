# Flutter Decoupled UI Packages Adoption Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate `app_flutter` off the Material/Cupertino libraries bundled inside the Flutter SDK to the new standalone `material_ui` and `cupertino_ui` packages, ahead of the formal deprecation of the bundled libraries in the November 2026 stable release.

**Driver:** "What's new in Flutter 3.47" (https://flutter.dev/blog/whats-new-in-flutter-3-47) — Flutter 3.47 ships `material_ui`/`cupertino_ui` 1.0 on pub.dev as opt-in standalone design systems. Bundled copies stay functional in 3.47 but are scheduled for deprecation in the next stable.

---

## Verified Facts (do not re-litigate)

- `material_ui` latest = **1.0.1** (pub.dev, 2026-08-19). Env: `sdk ^3.12.0`, `flutter >=3.44.0`. Depends on `cupertino_ui ^1.0.0`.
- Migration command from the blog: `dart fix --apply --code=migrate_design_widgets` (rewrites `package:flutter/material.dart` / `package:flutter/cupertino.dart` imports).
- **Known early bug**: the fixer may fail to edit `pubspec.yaml`; remedy is manual `flutter pub add material_ui` (and `cupertino_ui`), then re-run the fixer.
- Localizations are unbundled too: use `GlobalMaterialLocalizations.delegates` from `material_ui` instead of the three explicit delegates from `package:flutter_localizations`.
- `MaterialUiCompatibilityBridge` exists so an app can migrate while third-party dependencies still use legacy SDK imports.
- This repo's coupling points (audited 2026-08-22):
  - `MaterialApp.router` + localization delegates: `lib/app.dart`
  - `package:flutter/material.dart` imports in 8 files: `lib/app.dart`, `lib/main.dart`, `lib/utils/forui_theme.dart`, `lib/widgets/back_to_top_button.dart`, `lib/pages/{comic,library,settings,reader}_page.dart`, `lib/state/settings_state.dart`
  - No `CupertinoIcons` usage anywhere in `lib/` — `cupertino_icons` in pubspec is dead weight.
  - Design system is **forui** (0.25.0). Forui itself still consumes SDK Material internally until upstream migrates.
- Known unrelated blocker kept as-is: widget test `settings page exposes unlimited scroll switches` is skipped due to the Flutter 3.47.0 semantics traversal assert (`semantics.dart:5053`, PR #186118 rework). Not fixed in 3.47.1. Do not confuse failures here with this migration.

## Non-Goals

- Do NOT replace forui widgets with Material widgets. Forui stays the design system.
- Do NOT adopt experimental multi-window or desktop flavors.
- Do NOT touch `crates/` — Rust core and bridge are out of scope.
- Do NOT commit automatically; commit only when the user asks.

---

## Phase 0 — Preconditions

- [x] Confirm local Flutter is 3.47.x stable and `rtk flutter analyze` + `rtk flutter test` are green before any change (baseline).
- [x] Confirm `material_ui`/`cupertino_ui` versions still satisfy our constraints at implementation time.

## Phase 1 — Adopt Standalone Packages

- [x] In `app_flutter/`: `rtk flutter pub add material_ui cupertino_ui`.
- [x] Run `rtk dart fix --apply --code=migrate_design_widgets` in `app_flutter/`.
- [x] If imports were rewritten but pubspec was not updated (known bug): run `rtk flutter pub add material_ui cupertino_ui` manually and re-run the fixer. *(Not needed — fixer updated pubspec correctly.)*
- [x] Review every rewritten import; files must keep compiling (basic widgets like `Text`, `Icon`, `TextStyle` come along via the new packages' exports).

## Phase 2 — Localizations

- [x] In `lib/app.dart`, replace the three-delegate list with `localizationsDelegates: GlobalMaterialLocalizations.delegates` (from `material_ui`).
- [x] Drop the `package:flutter_localizations/flutter_localizations.dart` import from app code.
- [x] Remove the direct `flutter_localizations` entry from `app_flutter/pubspec.yaml` if nothing in first-party code imports it anymore (it remains a transitive dep of `material_ui` — that is fine).
- [x] Verify en/id locales still resolve (app title, dates, widget-level strings). *(Compile + default-locale widget tests pass; interactive en/id toggle is covered by the settings test currently skipped over the unrelated semantics bug.)*

## Phase 3 — Compatibility Bridge

- [x] While forui (and any other dep) still imports legacy SDK Material, wrap the routed child in `MaterialUiCompatibilityBridge` inside the `MaterialApp.router` builder (alongside `FTheme`), per the blog's bridging pattern.
- [ ] Add a TODO referencing removal once forui publishes a release migrated to the standalone packages; check forui changelog each upgrade. *(TODO comment added inline in `app.dart`; actual removal tracked here.)*

## Phase 4 — Cleanup

- [x] Remove dead `cupertino_icons` dependency from `app_flutter/pubspec.yaml`.
- [x] Update README tech-stack/toolchain lines: Flutter 3.47.x, Dart 3.12.1, mention standalone `material_ui`/`cupertino_ui` adoption.
- [x] Leave `AGENTS.md` ownership boundaries unchanged (no new design-system rules needed).

## Phase 5 — Verification

- [x] `rtk flutter analyze` — zero issues.
- [x] `rtk flutter test` — all pass except the documented skipped settings test.
- [x] Smoke build: `rtk flutter build linux --debug` succeeds.
- [ ] Push nothing; let user trigger CI. When CI runs, confirm desktop-build workflow passes on Flutter 3.47.x with the new packages.

---

## Implementation Notes (2026-08-22)

Deviations from the original plan, all evidence-based:

- **`cupertino_ui` is not a direct dependency.** First-party code had zero cupertino imports before and after migration, and `material_ui` itself depends on `cupertino_ui ^1.0.0`, so it stays in the graph transitively. Platform note: package usage is code-driven, not OS-driven — macOS builds gain nothing from a direct dep (forui already renders a CupertinoSwitch on every platform via SDK cupertino).
- **Root theme is now modern.** `MaterialApp.router` resolves to `material_ui`'s, whose `ThemeData` is a distinct class from the SDK's. Forui's `toApproximateMaterialTheme()` returns the *legacy* type, so `app.dart` builds a modern `ThemeData` (`_materialTheme`) from the same `ComicReaderFTheme` palette plus the `ComicReaderColors` extension; `MaterialUiCompatibilityBridge` maps it down to legacy Material for forui's subtree. `ComicReaderColors` therefore extends the *modern* `ThemeExtension`.
- **Baseline repair while executing:** the previously applied settings-test skip had been reverted in the working tree and was re-applied (Flutter 3.47.1 does not fix the semantics assert). Also fixed a real cross-test bug surfaced on 3.47.1: `opens comic paths that contain URL special characters` left ComicPage mounted during viewport teardown, whose RenderFlex overflow got attributed to the following test; it now navigates home before teardown.
- **Tooling note:** the `rtk` wrapper binary was not present in PATH this session; commands ran natively per the global agents policy ("native output only").

---

## Risks

| Risk | Mitigation |
| --- | --- |
| `dart fix` pubspec bug | Manual `flutter pub add` fallback (documented above). |
| forui incompatible with standalone packages | `MaterialUiCompatibilityBridge`; keep bridge until forui migrates. |
| Localization delegate swap breaks locale-dependent tests | Run full suite; compare failing tests against pre-change baseline. |
| Semantics assert bug resurfaces in more widget tests on scroll/toggle | Unrelated to this plan; extend the documented skip pattern only with a comment referencing the framework issue. |
