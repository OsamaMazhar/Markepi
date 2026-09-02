## Purpose

Describes the decorative frame the app composites around an exported photo or video: which style it uses, how the mat is proportioned, what the caption says and where each part of it sits, and the optional keyline and logo that separate and sign the image.

## ADDED Requirements

### Requirement: Frame style selection

A frame SHALL have a style, and the style SHALL determine the mat geometry and the caption layout. The system SHALL offer at least two styles: `classic`, the uniform border with a single centred caption, and `gallery`, the two-column caption bar. `classic` SHALL be the default.

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

### Requirement: Frame geometry places the mat outside the photo

Every frame style SHALL place the mat *outside* the photo: the exported image SHALL be larger than the source, and every pixel of the source SHALL remain visible and uncropped. **BREAKING** — this replaces the previous behaviour, where the border was drawn over the source's outer edge and the export kept the source's dimensions.

Mat width and caption size SHALL scale with the source image's shorter dimension, so a frame looks the same at any export resolution. In the `gallery` style the mat SHALL be of uniform width on the left, right and top edges, with a taller bottom band sized to hold the caption.

#### Scenario: Source image is never cropped
- **WHEN** a photo is exported with a frame in any style
- **THEN** the exported image is larger than the source in both dimensions
- **AND** the whole source image is visible inside the mat with no part of it covered or cut off

#### Scenario: Bottom band is taller than the other edges
- **WHEN** a photo is rendered in the `gallery` style with the caption enabled
- **THEN** the bottom mat band is taller than the left, right and top mat edges
- **AND** the caption is fully contained within that bottom band

#### Scenario: Proportions hold across resolutions
- **WHEN** the same photo is rendered at two different export resolutions
- **THEN** the ratio of mat width to source shorter dimension is the same in both
- **AND** the ratio of caption text size to source shorter dimension is the same in both

#### Scenario: Portrait and landscape
- **WHEN** a photo is rendered with a frame in either portrait or landscape orientation
- **THEN** the mat is drawn on all four sides and no caption content is clipped

#### Scenario: Other watermark layers keep their position on the photo
- **WHEN** a photo carrying text, logo or signature watermarks is exported with a frame enabled
- **THEN** each of those layers sits at the same place on the photo as it does without a frame
- **AND** none of them is displaced onto the mat by the canvas growing

### Requirement: Four-slot gallery caption

The `gallery` caption SHALL be composed of four independently configurable slots: `leftPrimary`, `leftSecondary`, `rightPrimary` and `rightSecondary`. Each slot SHALL resolve to either a metadata field or to free text supplied by the user. The left slots SHALL be rendered as two stacked lines aligned to the left edge of the caption band; the right slots SHALL be rendered as two stacked lines aligned to the right edge. In each pair the primary line SHALL be visually emphasised — heavier weight and darker — and the secondary line SHALL be lighter and less prominent.

#### Scenario: Reference defaults
- **WHEN** the `gallery` style is selected for the first time
- **THEN** `leftPrimary` resolves to the camera model, `leftSecondary` to the capture date, `rightPrimary` to the user's handle as free text, and `rightSecondary` to the lens and exposure details

#### Scenario: Reassigning a slot
- **WHEN** the user assigns a different metadata field to any slot
- **THEN** only that slot's text changes and the other three are unaffected

#### Scenario: Metadata missing for a slot
- **WHEN** a slot resolves to a metadata field the source image does not carry
- **THEN** that line is omitted
- **AND** the remaining lines stay in their group and the layout does not leave a visible gap where the missing line would have been

#### Scenario: All four slots empty
- **WHEN** every slot resolves to empty
- **THEN** no caption is drawn and the bottom mat band is reduced to the same width as the other mat edges

#### Scenario: Caption disabled
- **WHEN** the user turns the caption off
- **THEN** the mat is drawn with uniform width on all four sides and no text or logo appears

### Requirement: Gallery caption logo and divider

The `gallery` caption SHALL support a logo drawn immediately before the right-hand text group, separated from it by a thin vertical divider rule. The logo SHALL be selectable from the available marks or set to none, and none SHALL be a valid choice that removes both the logo and its divider. The logo SHALL be rendered from a vector source so that it stays sharp at full export resolution.

#### Scenario: Logo renders sharply at export resolution
- **WHEN** a photo is exported at its full resolution with a logo selected
- **THEN** the logo's edges are sharp, showing no resampling softness or visible pixel stepping

#### Scenario: No logo selected
- **WHEN** the logo is set to none
- **THEN** neither the logo nor the vertical divider is drawn
- **AND** the right-hand text group remains aligned to the right edge of the caption band

#### Scenario: Logo is vertically centred against the text group
- **WHEN** a logo is drawn
- **THEN** its vertical centre aligns with the vertical centre of the two-line right-hand text group

### Requirement: Optional keyline

The system SHALL offer an optional thin black keyline stroked between the edge of the photo and the surrounding mat. The keyline SHALL be available to every frame style, not only `gallery`, and SHALL default to disabled. Its thickness SHALL scale with the exported image's shorter dimension.

#### Scenario: Keyline enabled
- **WHEN** the keyline is enabled
- **THEN** a continuous black stroke is drawn around all four edges of the photo, between the photo and the mat
- **AND** the stroke covers no more of the photo than its own thickness

#### Scenario: Keyline available in every style
- **WHEN** the keyline is enabled and the style is switched between `classic` and `gallery`
- **THEN** the keyline is drawn in both styles

#### Scenario: Keyline disabled by default
- **WHEN** a frame is enabled without the user touching the keyline option
- **THEN** no keyline is drawn

### Requirement: Style parity across render paths and media types

Every frame style SHALL produce the same layout regardless of which platform render path draws it, and SHALL apply to video exports as well as photo exports.

#### Scenario: Platform parity
- **WHEN** the same photo and frame configuration are rendered on each supported platform render path
- **THEN** both produce the same mat geometry and the same caption layout, with text upright and correctly positioned in each

#### Scenario: Video export
- **WHEN** a video is exported with a frame enabled in any style
- **THEN** the frame is applied to every frame of the video, using that style's geometry
- **AND** the export completes and the source metadata is preserved

#### Scenario: Expanded output stays a valid export
- **WHEN** an export enlarges the canvas to place the mat outside the source
- **THEN** the resulting file's recorded dimensions match the enlarged canvas
- **AND** the source's metadata is preserved as it is for an unframed export
