## Why

The frame feature has exactly one look: a uniform white border with a single centred caption. It is the only "presentation" output the app offers, and it cannot reproduce the layout the iPhone-photography community actually posts — a light mat with a two-column caption bar carrying the device, the date, the photographer's handle, and the capture settings, set off from the photo by a thin black keyline.

Adding a *second* style is cheap; adding the *concept* of styles is what unlocks every style after it. This change does both, and pays the abstraction cost only once.

## What Changes

- **Frame styles.** `WhiteFrameConfig` gains a `FrameStyle` enum. `.classic` is today's uniform border with a centred caption and stays the default, so saved templates keep their look. `.gallery` is the new two-column mat.
- **The `.gallery` style.** A light-grey mat, even on three sides with a taller bottom band, carrying a caption row split into a left group (two stacked lines) and a right group (two stacked lines) preceded by a logo and a thin vertical divider rule. In each group the first line is bold and dark, the second lighter and grey.
- **Four configurable caption slots.** `leftPrimary`, `leftSecondary`, `rightPrimary`, `rightSecondary` each resolve to a `CaptionField` or to free text. Defaults reproduce the reference: camera model over date on the left; handle over lens/focal-length/aperture on the right.
- **Optional black keyline.** A thin black stroke between the photo edge and the mat, on/off. It lives in the shared renderer, so `.classic` gets it too rather than it being special-cased into the new style.
- **A metadata-derived brand mark.** The mark is chosen by the manufacturer recorded in the photo's metadata — an iPhone shot gets the Apple mark, a Samsung shot gets Samsung's, and so on across roughly fifteen phone and camera makers. The user cannot pick the brand; a photo can only ever carry the mark of the device that took it. A photo whose metadata names no manufacturer, or one the app ships no mark for, simply gets no mark and no divider. The only choice the user has is colour versus monochrome, offered where the resolved brand ships both.
- **BREAKING: the mat now sits outside the photo.** Both styles enlarge the exported canvas and place the mat around the source instead of drawing it over the source's outer edge. Exports get bigger and nothing is cropped. This also deletes the `frameInset` workaround that pushed watermark placement inward to keep corner watermarks out from under the border.
- **Config stays backward-compatible.** Every new field decodes with `decodeIfPresent`; an old saved template deserialises to `.classic` with the keyline off and no logo. It renders with the new geometry — same border, larger output.

## Capabilities

### New Capabilities
- `photo-frames`: the decorative frame composited around an exported photo or video — its style, geometry, caption content and layout, keyline, and logo slot.

### Modified Capabilities
<!-- None. `openspec/specs/` is empty; this change introduces the first spec for
     this area, so the frame behaviour is captured wholly as a new capability. -->

## Impact

- **Models** — `WhiteFrameConfig.swift`: new `FrameStyle`, four caption slots, keyline and logo fields, all Codable-compatible with existing saved templates.
- **Rendering** — `WhiteFrameRenderer.swift`: style branch in `drawFrame`, a two-column caption layout, keyline stroke, vector logo drawing. Both the UIKit path and the macOS Core Text path (used by `swift test` and the `markepi` CLI) must render the new style.
- **UI** — `WhiteFrameToggleView.swift`: a style picker plus the rows each style needs, shown conditionally.
- **Preview freshness** — `previewIdentifier` must mirror every new render-affecting field or the live preview goes stale.
- **Pipeline** — `WatermarkEngine.buildFilterGraph` composites the photo into an enlarged canvas and reports the enlarged size in its metadata; `VideoLayerBuilder` and `VideoProcessor` grow `renderSize` and inset the video layer to match. Both lose their `frameInset` watermark-positioning workaround.
- **Assets** — roughly fifteen brand marks, each up to two variants, supplied by the user as vectors and converted to PDF resources in the package. A brand whose asset has not landed yet simply resolves to no mark, so implementation does not block on sourcing.
- **Legal** — every brand mark is a third-party registered trademark. Deriving the mark from metadata keeps its use factual — the mark of the device that actually took the photo — which is a materially better footing than letting users stamp any brand on any image. Recorded in design.md as an accepted risk.
- **Tests** — `WhiteFrameRendererTests`, `CaptionBuilderTests`, `MediaPipelineRegressionTests`, and the snapshot suite.
