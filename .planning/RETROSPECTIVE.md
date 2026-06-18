# Project Retrospective

*A living document updated after each milestone. Lessons feed forward into future planning.*

## Milestone: v1.0 — MVP

**Shipped:** 2026-06-18
**Phases:** 7 | **Plans:** 20 | **Tasks:** 44

### What Was Built
- WatermarkCore Swift Package — CGImageSource → Core Image → CGImageDestination pipeline preserving HDR, EXIF, gain maps; text/image/signature watermarks; white frames with device metadata; multi-layer compositing with per-layer opacity/visibility
- 3 iOS targets sharing the engine via App Group: Main App (PhotosPicker + Files import + quick actions + Siri/Shortcuts), ShareExtension (share sheet), PhotoEditExtension (Photos app non-destructive editing with PHAdjustmentData)
- Video watermarking via AVFoundation CALayer overlay with HDR preservation, progress/cancel UX, and background completion notification
- Extended engine: ProRAW DNG at 48MP, dynamic EXIF tokens (8 tokens), Live Photo two-phase watermarking, PencilKit signature capture
- Export control: HEIC/JPEG/PNG/TIFF format choice, quality slider, before/after long-press comparison

### What Worked
- Swift Package shared by 3 targets eliminated engine duplication — single source of truth for watermarking logic
- CGImageSource → CGImageDestination pipeline preserved all metadata/HDR without third-party dependencies
- `WatermarkConfigurable` protocol enabled shared `ControlsView` across all 3 ViewModels
- MVP mode vertical slices — each plan delivered testable end-to-end value
- Codable backward compatibility via `decodeIfPresent` with defaults — old configs decoded cleanly when new fields (opacity, isVisible, signature) were added
- Wave-based parallel execution — Phase 3 Wave 1 ran two plans in parallel cleanly

### What Was Inefficient
- REQUIREMENTS.md traceability drift — 5 requirements (EXPT/COMP/VIDX) remained unchecked after Phase 6 completed; same for 5 v2 requirements after Phase 7. The checkbox update step wasn't automated per plan completion.
- No VERIFICATION.md files created for any phase — formal verification documentation was skipped throughout. Milestone audit had to rely on SUMMARY.md frontmatter + code inspection.
- 186 lines of near-duplicate ViewModel layer-management code across 3 targets — `WatermarkConfigurable` protocol defined the interface but no default implementations, so each target copy-pasted `updateLayerPosition`/`updateLayerScale`/`removeLayer`/`toggleWhiteFrame`/`addLogoLayer`.
- Phase 7 plan 07-03 executor hit a worktree-safety halt (HEAD on `main` instead of `worktree-agent-*`) — had to fall back to inline execution. Worktree setup for the task tool isn't creating per-agent branches.
- Pre-existing build errors accumulated across phases (enum opacity/isVisible pattern mismatches in 2 extension ViewModels, stale Xcode project file references, struct scoping bug) — only surfaced during Phase 7 post-merge gate. Earlier phases' self-checks reported "PASSED" despite broken builds.
- PhotosExtensionViewModel never populated `sourceHasHDR`/`sourceFormatLabel` — HDR→JPEG warning won't trigger in Photos extension context.

### Patterns Established
- `CGImageDestination` with `kCGImageDestinationMergeMetadata` is the only reliable metadata-preserving write path — never use `UIImage` for processing pipeline
- `CIFilter.colorMatrix.aVector` for per-layer opacity (separate from element rendering alpha)
- D-12 compositing order: text (bottom) → image (middle) → white frame (top) — enforced in both photo `buildFilterGraph` and video `VideoLayerBuilder`
- `decodeIfPresent` with defaults for all new Codable fields — backward compatibility by construction
- App Group UserDefaults for bidirectional config sync + pending intent handoff
- Two-phase Live Photo watermarking as pragmatic bridge when `PHLivePhotoEditingContext` is unavailable from PhotosPicker

### Key Lessons
1. **Automate REQUIREMENTS.md checkbox updates per plan completion.** Manual traceability updates drift — 10/35 requirements were unchecked at milestone close despite being satisfied. Either the execute-plan workflow should update REQUIREMENTS.md, or the milestone audit should auto-reconcile using SUMMARY.md frontmatter.
2. **Run post-merge build gate after every wave, not just at milestone audit.** Pre-existing build errors from Phases 5–6 (enum pattern mismatches, stale pbxproj refs) compounded undetected until Phase 7. Wave-level build gates would have caught them at source.
3. **Add default implementations to `WatermarkConfigurable` protocol.** 186 lines of duplicated layer-management code across 3 ViewModels is a maintenance hazard. A protocol extension with defaults would collapse this to ~20 lines.
4. **Executor self-checks claiming "PASSED" are not trustworthy without an actual build.** Multiple plans reported successful self-checks while the build was broken. The execute-plan workflow should require an `xcodebuild` invocation, not just file-existence checks.
5. **Consolidate AppDelegate + SceneDelegate into `WatermarkApp.swift` when adding to an existing target.** Editing `.pbxproj` to add new Swift files is error-prone; consolidation avoids that entirely. Deviates from conventional separation but ships faster.

### Cost Observations
- Model mix: ~100% sonnet (executor + verifier both configured to sonnet)
- Sessions: single session, 137 commits
- Notable: Entire v1.0 MVP (7 phases, 20 plans, 44 tasks, 13.2K LOC) shipped in 1 day — Swift Package architecture kept context costs low and enabled fast iteration

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Sessions | Phases | Key Change |
|-----------|----------|--------|------------|
| v1.0 | 1 | 7 | Greenfield → shipped MVP; established WatermarkCore package + 3-target architecture |

### Cumulative Quality

| Milestone | Tests | Coverage | Zero-Dep Additions |
|-----------|-------|----------|-------------------|
| v1.0 | 227 | N/A (no coverage tooling) | 0 (Apple system frameworks only) |

### Top Lessons (Verified Across Milestones)

1. _First milestone — trends will emerge in v1.1+_
2. _First milestone — trends will emerge in v1.1+_
