---
quick_task: 260624-tag
description: Implement the Photo Edit Extension removal audit
type: execute
status: ready
created: 2026-06-24
autonomous: true
requirements: []
files_modified:
  - Watermark.xcodeproj/project.pbxproj
  - Watermark.xcodeproj/xcuserdata/osama.xcuserdatad/xcschemes/xcschememanagement.plist
  - PhotoEditExtension/
  - Packages/WatermarkCore/Sources/WatermarkCore/UI/PhotosExtensionRootView.swift
  - Packages/WatermarkCore/Sources/WatermarkCore/UI/ExtensionRendering.swift
  - Packages/WatermarkCore/Sources/WatermarkCore/Models/WatermarkConfiguration.swift
  - Packages/WatermarkCore/Sources/WatermarkCore/Storage/AppGroupConfigSync.swift
  - Packages/WatermarkCore/Sources/WatermarkCore/Processing/LivePhotoProcessor.swift
  - Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/EmptyStateView.swift
  - Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/ShareActionButton.swift
  - Packages/WatermarkCore/Sources/WatermarkCore/UI/TextWatermarkInputView.swift
  - Packages/WatermarkCore/Sources/WatermarkCore/UI/WatermarkConfigurable.swift
  - Packages/WatermarkCore/Tests/WatermarkCoreTests/PhotosExtensionTests.swift
  - Packages/WatermarkCore/Tests/WatermarkCoreTests/ExtensionSnapshotTests.swift
  - Packages/WatermarkCore/Tests/WatermarkCoreTests/TestHelpers/SnapshotTestViewModel.swift
  - Packages/WatermarkCore/Tests/WatermarkCoreTests/SignatureInputTests.swift
  - Packages/WatermarkCore/Tests/WatermarkCoreTests/__Snapshots__/photos-ext-idle.png
  - Packages/WatermarkCore/Tests/WatermarkCoreTests/__Snapshots__/photos-ext-preview.png
  - App/Views/Templates/TemplateListView.swift
  - scripts/build-gate.sh
  - .planning/PROJECT.md
  - .planning/STATE.md
  - .planning/research/STACK.md
  - AGENTS.md
---

# Quick Task 260624-tag Plan

## Objective

Retire the Photos native edit extension completely while preserving the main app, PhotosPicker import, Share Extension, Live Photo processing, App Group synchronization, templates, metadata/HDR behavior, and original-quality processing.

The implementation is governed by `.planning/PHOTO-EDIT-EXTENSION-REMOVAL-AUDIT.md`. Historical milestone plans, summaries, requirements, verification reports, `.planning/MILESTONES.md`, and `.planning/RETROSPECTIVE.md` remain unchanged because they accurately describe what shipped at the time.

## Dirty-Worktree Safeguards

Before changing any file:

1. Capture `git status --short` and `git diff -- <all removal-related paths>` as the implementation baseline.
2. Inspect the current content and diff of every overlapping modified file before editing or deleting it, especially `project.pbxproj`, the scheme-management plist, `PhotoEditExtension/`, `PhotosExtensionRootView.swift`, `WatermarkConfiguration.swift`, and `TemplateListView.swift`.
3. Treat all pre-existing modifications as user work. Preserve unrelated hunks and incorporate relevant in-progress work into the removal rather than restoring the file from `HEAD`.
4. Do not use `git reset`, `git checkout --`, `git restore`, broad generated-project rewrites, or any command that discards uncommitted changes.
5. Use narrow patches. Before completion, compare the final diff against the baseline and confirm every newly changed hunk belongs to this removal.

## Tasks

<task type="auto">
  <name>Task 1: Remove the target and extension-only production code</name>
  <files>
    Watermark.xcodeproj/project.pbxproj
    Watermark.xcodeproj/xcuserdata/osama.xcuserdatad/xcschemes/xcschememanagement.plist
    PhotoEditExtension/
    Packages/WatermarkCore/Sources/WatermarkCore/UI/PhotosExtensionRootView.swift
    Packages/WatermarkCore/Sources/WatermarkCore/UI/ExtensionRendering.swift
    Packages/WatermarkCore/Sources/WatermarkCore/Models/WatermarkConfiguration.swift
    Packages/WatermarkCore/Sources/WatermarkCore/Storage/AppGroupConfigSync.swift
    Packages/WatermarkCore/Sources/WatermarkCore/Processing/LivePhotoProcessor.swift
  </files>
  <action>
    First apply the dirty-worktree safeguards above. In `project.pbxproj`, remove only the audited Photo Edit objects: build files `017`, `018`, `01B`, and `4AF4A26D2FE9816900C77DCC`; references `610`, `611`, `613`, `614`, and `621`; group `305`; target `411`; phases `404`, `406`, and `408`; configurations `63D`, `63E`, and list `71E`; plus target `411` from TargetAttributes and the project targets array. Remove product `621` from Products and remove only `01B` from app embed phase `409`; preserve that phase and the Share Extension embed entry.

    Remove the `PhotoEditExtension.xcscheme_^#shared#^_` scheme-management entry. Delete the complete `PhotoEditExtension/` directory and `PhotosExtensionRootView.swift`.

    Delete `PhotosExtensionRendering` from `ExtensionRendering.swift`, retain `ShareExtensionRendering`, and make its `sourceURL` documentation Share Extension-specific. Remove the complete `PHAdjustmentData Image Stripping` extension (`strippedPlaceholderPNG`, `strippingImageData()`, and `rehydrateImageData()`) from `WatermarkConfiguration.swift`. Keep `AppGroupConfigSync` and revise only its now-stale rehydration comment. Remove the obsolete future-Photo-Edit comment and unused `Photos` import from `LivePhotoProcessor.swift` only if compilation confirms the import is unnecessary; retain the Live Photo implementation.
  </action>
  <verify>
    `xcodebuild -project Watermark.xcodeproj -list` lists `WatermarkApp` and `ShareExtension` but not `PhotoEditExtension`. A focused `rg` scan of production/project paths finds no target, protocol, PHContentEditing, PHAdjustmentData, or retired bundle-ID references.
  </verify>
</task>

<task type="auto">
  <name>Task 2: Reconcile tests, snapshots, copy, and current project documentation</name>
  <files>
    Packages/WatermarkCore/Tests/WatermarkCoreTests/PhotosExtensionTests.swift
    Packages/WatermarkCore/Tests/WatermarkCoreTests/ExtensionSnapshotTests.swift
    Packages/WatermarkCore/Tests/WatermarkCoreTests/TestHelpers/SnapshotTestViewModel.swift
    Packages/WatermarkCore/Tests/WatermarkCoreTests/SignatureInputTests.swift
    Packages/WatermarkCore/Tests/WatermarkCoreTests/__Snapshots__/photos-ext-idle.png
    Packages/WatermarkCore/Tests/WatermarkCoreTests/__Snapshots__/photos-ext-preview.png
    App/Views/Templates/TemplateListView.swift
    Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/EmptyStateView.swift
    Packages/WatermarkCore/Sources/WatermarkCore/DesignSystem/ShareActionButton.swift
    Packages/WatermarkCore/Sources/WatermarkCore/UI/TextWatermarkInputView.swift
    Packages/WatermarkCore/Sources/WatermarkCore/UI/WatermarkConfigurable.swift
    scripts/build-gate.sh
    .planning/PROJECT.md
    .planning/STATE.md
    .planning/research/STACK.md
    AGENTS.md
  </files>
  <action>
    Remove the Photos Extension idle/preview snapshot tests and their two PNG references. Remove Photos-only conformance and stubs (`PhotosExtensionRendering`, `FinishOutput`, `finishEditing`) from `SnapshotTestViewModel`, while retaining all Share Extension snapshot infrastructure. Remove the signature test coupled only to `strippingImageData()` and preserve all other signature coverage.

    Review every test in `PhotosExtensionTests.swift` before deleting or renaming the file. Delete the extension-specific/local-helper cases named in the audit. Preserve unique generic regressions for photo/video processing, media detection, metadata/HDR, configuration round trips, orientation, and ImageIO URL behavior by moving them into the closest existing engine/metadata/video test suite, or into a clearly named non-extension regression test file when no suitable suite exists. Do not duplicate tests that already cover the same behavior. Ensure neither the remaining filename nor suite names claim Photos Extension coverage.

    Update `TemplateListView` copy to promise template reuse only in the main app and Share Extension. Remove Photos Edit-specific statements from comments in the audited shared UI/design-system files without changing behavior. Update `scripts/build-gate.sh` wording from three targets to the two remaining targets; leave `scripts/test-build-gate.sh` unchanged unless verification exposes a genuine failure.

    Update `.planning/PROJECT.md`, `.planning/STATE.md`, and `.planning/research/STACK.md` so current scope, architecture, constraints, target counts, and cross-target risk describe only the main app and Share Extension. Synchronize the generated/source-backed sections of `AGENTS.md` with those current planning sources. Record Photos Edit as retired rather than pretending it never existed. Do not rewrite historical phase/milestone evidence or archived MEDI-03, PHDR-01, and XTG-02 completion records.
  </action>
  <verify>
    Active copy and comments contain no promise of Photos Edit support. Share Extension snapshots and tests remain. Current planning sources and `AGENTS.md` agree on two targets, while archived planning records remain untouched.
  </verify>
</task>

<task type="auto">
  <name>Task 3: Prove removal, preserve remaining workflows, and close the GSD quick task</name>
  <files>
    .planning/quick/260624-tag-implement-the-photo-edit-extension-remov/260624-tag-SUMMARY.md
    .planning/STATE.md
  </files>
  <action>
    Run the residual scans, package tests, build gate, and built-product inspection below. Fix any failure caused by this removal without broadening scope. Confirm the app bundle contains `ShareExtension.appex` and no `PhotoEditExtension.appex`.

    Write `260624-tag-SUMMARY.md` with implementation details, verification evidence, dirty-worktree preservation notes, and `requirements-completed: []` because this task retires previously completed historical scope rather than completing a new requirement. Run `bash scripts/sync-requirements.sh .planning/quick/260624-tag-implement-the-photo-edit-extension-remov/260624-tag-SUMMARY.md`; any `not_found` or script error blocks completion. Update `.planning/STATE.md` with the completed quick task only after all gates pass.
  </action>
  <verify>
    All automated commands below exit zero; residual active-code scans are empty; package tests pass; build gate reports `BUILD GATE: PASSED`; final diff review confirms no pre-existing unrelated work was discarded.
  </verify>
</task>

## Automated Verification

```bash
rg -n -i \
  'PhotoEditExtension|PhotosExtension|PHContentEditing|PHAdjustmentData|com\.apple\.photo-editing|com\.watermark\.app\.photoedit' \
  App Packages ShareExtension Watermark.xcodeproj scripts AGENTS.md

rg -n \
  'strippingImageData|rehydrateImageData|PhotosExtensionRendering|PhotosExtensionRootView' \
  App Packages ShareExtension Watermark.xcodeproj scripts AGENTS.md

xcodebuild -project Watermark.xcodeproj -list
swift test --package-path Packages/WatermarkCore
bash scripts/build-gate.sh
bash scripts/sync-requirements.sh \
  .planning/quick/260624-tag-implement-the-photo-edit-extension-remov/260624-tag-SUMMARY.md
```

The two `rg` commands are expected to return no matches (exit 1 is the successful no-match condition and should be interpreted accordingly). Historical `.planning/` matches outside current documents are allowed.

After the build gate, locate the built `WatermarkApp.app/PlugIns` directory and verify:

```bash
find <WatermarkApp.app>/PlugIns -maxdepth 1 -type d -name '*.appex' -print
```

Expected: `ShareExtension.appex` is present and `PhotoEditExtension.appex` is absent.

## Manual Smoke Checks

- Import one photo and one video with the main-app PhotosPicker.
- Send a photo/video to Watermark through the Share Extension.
- Apply text, logo, signature, and frame watermarks and share without saving.
- Save/load/default a template across the main app and Share Extension.
- Exercise Live Photo processing and confirm supported metadata/HDR behavior is unchanged.

## Done When

- The Photo Edit target, product, source/config directory, shared root/protocol, adjustment-data helpers, extension-only tests, and snapshots are gone.
- The app embeds only `ShareExtension.appex`; the main app, Share Extension, PhotosPicker, Live Photo, App Group, template, metadata, and HDR paths remain intact.
- Active code/config/copy has no retired-extension references, while historical planning evidence remains accurate.
- Package tests, build gate, requirement synchronization, and final dirty-worktree review all pass.
