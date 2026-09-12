## MODIFIED Requirements

### Requirement: Frame style selection

A frame SHALL have a style, and the style SHALL determine the mat geometry and the caption layout. The system SHALL offer at least four styles: `classic`, the uniform border with a single centred caption; `gallery`, the two-column caption bar on a graduated mat; `slate`, the same two-column caption bar as `gallery` but on a flat, ungraduated mat; and `studio`, a flat-mat uniform border with a centred two-line caption crediting the device and manufacturer above the shooting details. `classic` SHALL be the default.

#### Scenario: Default style
- **WHEN** a frame is enabled without the user choosing a style
- **THEN** the frame renders in the `classic` style — the uniform border with a single centred caption

#### Scenario: Saved template from a previous version
- **WHEN** a template saved before frame styles existed is loaded
- **THEN** it loads without error
- **AND** its frame resolves to the `classic` style with the keyline disabled and no logo
- **AND** it renders with the new outside-the-photo geometry, so its export is larger than the source

#### Scenario: Switching style updates the preview
- **WHEN** the user changes the frame style
- **THEN** the live preview re-renders in the newly selected style without requiring any other interaction

#### Scenario: Saved template naming an unknown future style
- **WHEN** a template names a style newer than the running build understands
- **THEN** it resolves to `classic` rather than failing to load, per the style enum's existing lenient-decode behavior

#### Scenario: Choosing among all four styles
- **WHEN** the user opens the style picker
- **THEN** `classic`, `gallery`, `slate` and `studio` are all offered, each showing only the settings relevant to it

## ADDED Requirements

### Requirement: Mat fill is flat or graduated, per style

Each frame style SHALL use exactly one of two mat fills: a flat, uniform color, or a top-to-bottom graduated color. Which fill a style uses SHALL be fixed by that style, not user-configurable. `classic`, `slate` and `studio` SHALL use a flat mat. `gallery` SHALL use a graduated mat, as today.

#### Scenario: Slate has no gradient
- **WHEN** a photo is rendered in the `slate` style
- **THEN** the mat is a single flat color with no visible gradient anywhere on it, including the side borders

#### Scenario: Gallery keeps its gradient
- **WHEN** a photo is rendered in the `gallery` style
- **THEN** the mat still grades from a lighter tone at the top to a darker tone at the bottom, unchanged from before this change

#### Scenario: Studio has no gradient
- **WHEN** a photo is rendered in the `studio` style
- **THEN** the mat is a single flat color on all four sides

### Requirement: Slate reuses gallery's caption on a flat mat

The `slate` style SHALL present the identical two-column caption layout as `gallery` — the same slots, the same brand mark and divider behavior, the same physical-unit sizing — differing from `gallery` only in that its mat is flat rather than graduated.

#### Scenario: Same configuration, different fill
- **WHEN** a `gallery` configuration (slots, keyline, logo variant, millimetre settings) is applied to the `slate` style instead
- **THEN** the caption content, layout and sizing are identical between the two
- **AND** only the mat's fill differs — flat for `slate`, graduated for `gallery`

#### Scenario: Slate's brand mark and keyline
- **WHEN** the `slate` style is used
- **THEN** its brand mark resolution, colour/monochrome variant handling and optional keyline all behave exactly as they do in `gallery`

### Requirement: Studio caption — device credit and shooting details

The `studio` style's caption SHALL be two centred lines. The first line SHALL read "Shot on" followed by the device model rendered with visual emphasis (heavier weight than the surrounding text) followed by the resolved manufacturer's name in the surrounding (non-emphasized) weight — e.g. "Shot on **iPhone 15 Pro Max** Apple". This first line SHALL NOT be user-configurable, mirroring how `classic`'s single line is not slot-configurable. The manufacturer name SHALL be resolved from the source image's metadata using the same manufacturer recognition the system already applies to select `gallery`'s brand mark, and SHALL NOT be user-chosen.

The second line SHALL be built from the user's selected metadata fields, using the same field-selection mechanism `classic` already offers, joined with plain spacing rather than `classic`'s "·" separator.

`studio` SHALL NOT offer the free-text caption prefix that `classic` offers, because its fixed first line already occupies that role and offering both would let the same lead-in appear twice. A prefix the user has previously set SHALL be preserved rather than discarded, so returning to a style that does offer it finds it intact.

#### Scenario: Device and manufacturer both resolve
- **WHEN** a photo whose metadata resolves both a device model and a recognized manufacturer is rendered in `studio`
- **THEN** the first line reads "Shot on", the device model in emphasized weight, then the manufacturer's name in normal weight, all on one line

#### Scenario: No manufacturer resolves
- **WHEN** a photo's metadata names no manufacturer the system recognizes
- **THEN** the first line reads "Shot on" and the device model only, with no trailing manufacturer name — the same "gracefully omit" behavior `gallery` already applies to its brand mark

#### Scenario: No device model at all
- **WHEN** a photo's metadata carries no device model
- **THEN** the first line is omitted entirely rather than reading "Shot on" with nothing after it

#### Scenario: Second line reflects selected fields
- **WHEN** the user selects a set of metadata fields for `studio`'s caption
- **THEN** the second line shows exactly those fields, in the system's canonical field order, separated by plain spacing

#### Scenario: No caption prefix is offered
- **WHEN** the user selects `studio` and opens its caption settings
- **THEN** the free-text caption prefix offered by `classic` is not shown, and only the field selection is

#### Scenario: A previously typed prefix survives the round trip
- **WHEN** the user types a caption prefix in `classic`, switches to `studio`, then switches back to `classic`
- **THEN** the prefix they typed is still there

#### Scenario: Second line fields all missing
- **WHEN** every field selected for the second line is unavailable in the photo's metadata
- **THEN** the second line is omitted, and if the first line is also empty the caption band collapses to the same width as the other mat edges, consistent with how an empty caption behaves in other styles
