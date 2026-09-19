# photo-frames Specification

## Purpose
Describes the decorative frame the app composites around an exported photo or video: which style it uses, how the mat is proportioned, what the caption says and where each part of it sits, and the optional keyline and logo that separate and sign the image.

## Requirements

### Requirement: Frame style selection

A frame SHALL have a style, and the style SHALL determine the mat geometry and the caption layout. The system SHALL offer four styles: `classic`, the uniform border with a single centred caption; `gallery`, the two-column caption bar with a brand mark; `print`, which lifts the photo off a plain mat with a drop shadow and credits the device above the shooting details; and `banner`, which sets a full-bleed photo over a caption bar. `classic` SHALL be the default.

Two candidate styles were dropped for saying the same thing twice. Whether `gallery`'s mat is graduated SHALL be a setting of that style rather than a style of its own, because a flat `gallery` differs from a graduated one in nothing but the fill. A flat-mat centred credit SHALL NOT be a style of its own either: it differs from `classic` only in splitting the same caption across two lines, and `print` already draws that caption.

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

#### Scenario: Choosing among the styles
- **WHEN** the user opens the style picker
- **THEN** `classic`, `gallery`, `print` and `banner` are all offered
- **AND** each style shows only the controls it actually reads

### Requirement: Frame geometry places the mat outside the photo

Every frame style SHALL place the mat *outside* the photo: the exported image SHALL be larger than the source, and every pixel of the source SHALL remain visible and uncropped. **BREAKING** — this replaces the previous behaviour, where the border was drawn over the source's outer edge and the export kept the source's dimensions.

In the `gallery` style the mat SHALL be of uniform width on the left, right and top edges, with a taller bottom band sized to hold the caption. Each style SHALL size its mat and caption in a single unit — `classic` as a proportion of the source, `gallery` in physical units — so that the parts of a frame cannot be measured against each other in ways that fight.

#### Scenario: Source image is never cropped
- **WHEN** a photo is exported with a frame in any style
- **THEN** the exported image is larger than the source in both dimensions
- **AND** the whole source image is visible inside the mat with no part of it covered or cut off

#### Scenario: Bottom band is taller than the other edges
- **WHEN** a photo is rendered in the `gallery` style with the caption enabled
- **THEN** the bottom mat band is taller than the left, right and top mat edges
- **AND** the caption is fully contained within that bottom band

#### Scenario: Classic proportions hold across resolutions
- **WHEN** the same photo is rendered in the `classic` style at two different export resolutions
- **THEN** the ratio of mat width to source shorter dimension is the same in both
- **AND** the ratio of caption text size to source shorter dimension is the same in both

#### Scenario: Portrait and landscape
- **WHEN** a photo is rendered with a frame in either portrait or landscape orientation
- **THEN** the mat is drawn on all four sides and no caption content is clipped

#### Scenario: Other watermark layers keep their position on the photo
- **WHEN** a photo carrying text, logo or signature watermarks is exported with a frame enabled
- **THEN** each of those layers sits at the same place on the photo as it does without a frame
- **AND** none of them is displaced onto the mat by the canvas growing

### Requirement: Gallery is measured in physical units

In the `gallery` style the user SHALL set the border thickness, the caption text size and the brand mark height in millimetres. These SHALL be physical sizes: the same setting SHALL produce the same measurement on paper regardless of the photo's pixel dimensions.

Millimetres SHALL be converted to pixels using the photo's own recorded resolution where that resolution is a plausible print-intent measurement, and a print-standard default otherwise. The brand mark SHALL be sized by height, because these marks range from wide wordmarks to square glyphs and a width-based size would render them wildly inconsistently.

The bottom band SHALL grow and shrink with the border setting, and SHALL always remain tall enough to contain the caption lines and the brand mark.

#### Scenario: A millimetre setting is a physical size
- **WHEN** the same border setting is applied to a small photo and to a much larger one
- **THEN** the border occupies the same number of pixels in both
- **AND** so the two, printed at the same resolution, have borders that measure the same

#### Scenario: Resolution changes the pixel size
- **WHEN** a photo carries a higher print-intent resolution
- **THEN** the same millimetre settings resolve to proportionally more pixels
- **AND** the border, caption text and brand mark all scale together, keeping their relationship to one another

#### Scenario: A meaningless recorded resolution is not trusted
- **WHEN** a photo records a resolution too low to be a real print-intent measurement, as most camera files do by format default
- **THEN** the print-standard default is used instead, so the border does not collapse to something invisible

#### Scenario: The bottom band tracks the border
- **WHEN** the user increases the border setting
- **THEN** the bottom band grows with it and remains the tallest edge

#### Scenario: The band never crushes its contents
- **WHEN** the border is set very small, or the caption text or brand mark very large
- **THEN** the bottom band is still tall enough to contain the caption lines and the mark

#### Scenario: Each setting moves only its own element
- **WHEN** the user changes the caption text size
- **THEN** the brand mark height and the border thickness are unchanged

#### Scenario: Classic is unaffected
- **WHEN** the `classic` style is used
- **THEN** it sizes its mat and caption as a proportion of the photo, and the millimetre settings have no effect on it

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

### Requirement: Gallery caption brand mark and divider

The `gallery` caption SHALL draw a brand mark immediately before the right-hand text group, separated from it by a thin vertical divider rule. The mark SHALL be determined by the manufacturer recorded in the source image's metadata — a photo taken on an Apple device gets the Apple mark, one taken on a Samsung device gets the Samsung mark, and so on. The user SHALL NOT be able to choose which brand's mark appears.

Manufacturer matching SHALL tolerate how manufacturers actually write themselves into metadata, so that spelling, case and corporate suffixes do not defeat recognition. Where a manufacturer ships sub-brands that record the parent company as the manufacturer, the device model SHALL be consulted so the sub-brand's own mark is used. The mark SHALL be rendered from a vector source so that it stays sharp at full export resolution.

#### Scenario: Recognised manufacturer
- **WHEN** a photo whose metadata identifies a manufacturer the app ships a mark for is rendered in the `gallery` style
- **THEN** that manufacturer's mark is drawn before the right-hand text group with its vertical divider

#### Scenario: Manufacturer written with case or suffix variation
- **WHEN** the metadata records the manufacturer with different case or with a corporate suffix, such as a camera body writing its maker's name in capitals followed by "CORPORATION"
- **THEN** it resolves to the same mark as the plain manufacturer name

#### Scenario: Sub-brand recorded under its parent manufacturer
- **WHEN** a photo records the parent company as its manufacturer but names a known sub-brand in its model
- **THEN** the sub-brand's own mark is drawn rather than the parent's

#### Scenario: No manufacturer in metadata
- **WHEN** the source image's metadata carries no manufacturer information
- **THEN** neither a mark nor the vertical divider is drawn
- **AND** the right-hand text group remains aligned to the right edge of the caption band

#### Scenario: Manufacturer the app ships no mark for
- **WHEN** the metadata names a manufacturer the app has no mark for
- **THEN** neither a mark nor the vertical divider is drawn
- **AND** the caption renders normally in every other respect

#### Scenario: Mark renders sharply at export resolution
- **WHEN** a photo is exported at its full resolution with a mark resolved
- **THEN** the mark's edges are sharp, showing no resampling softness or visible pixel stepping

#### Scenario: Mark is vertically centred against the text group
- **WHEN** a mark is drawn
- **THEN** its vertical centre aligns with the vertical centre of the two-line right-hand text group

### Requirement: Brand mark colour variant

Where a resolved brand ships both a colour and a monochrome mark, the user SHALL be able to choose between them. Where a brand ships only one, that one SHALL be used and the choice SHALL NOT be offered. When monochrome is in effect, the system SHALL draw whichever monochrome rendition contrasts with the mat; the user SHALL NOT choose between light and dark monochrome. The choice SHALL apply to whichever brand is resolved, not to one specific brand.

#### Scenario: Both variants available
- **WHEN** the resolved brand ships a colour and a monochrome mark
- **THEN** the user can switch between them
- **AND** the selected variant is the one drawn

#### Scenario: Only one variant available
- **WHEN** the resolved brand ships only one mark
- **THEN** that mark is drawn regardless of the user's variant preference
- **AND** no variant choice is offered for it

#### Scenario: Monochrome contrasts with the mat
- **WHEN** monochrome is in effect on a light mat
- **THEN** the dark monochrome rendition is drawn, so the mark is legible against the mat

#### Scenario: Preference persists across photos
- **WHEN** the user has chosen a variant and then frames a photo from a different manufacturer that also ships both variants
- **THEN** the same variant preference applies to that brand's mark

### Requirement: Optional keyline

The system SHALL offer a black keyline stroked between the edge of the photo and the surrounding mat. The keyline SHALL be available to every frame style, not only `gallery`, and SHALL be enabled by default. Its thickness SHALL be a proportion of the mat, so that it stays legible against the border it separates rather than thinning away on a small image.

#### Scenario: Keyline enabled
- **WHEN** the keyline is enabled
- **THEN** a continuous black stroke is drawn around all four edges of the photo, between the photo and the mat
- **AND** the stroke covers no more of the photo than its own thickness

#### Scenario: Keyline available in every style
- **WHEN** the keyline is enabled and the style is switched between `classic` and `gallery`
- **THEN** the keyline is drawn in both styles

#### Scenario: Keyline turned off
- **WHEN** the user turns the keyline off in any style that offers it, `classic` included
- **THEN** no stroke is drawn, and the mat runs unbroken up to the edge of the photo

#### Scenario: Keyline enabled by default
- **WHEN** a frame is enabled without the user touching the keyline option
- **THEN** the keyline is drawn, as it is in the reference layout

#### Scenario: Keyline stays legible as the border changes
- **WHEN** the border is widened
- **THEN** the keyline thickens in proportion, keeping its weight relative to the mat

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

### Requirement: Location caption shows country and flag

Where a frame's caption includes the location field (`CaptionField.gps`, labelled "Location"), its rendered text SHALL be a pin glyph followed by the resolved country's localized name and that country's flag — e.g. "📍 France 🇫🇷" — rather than raw GPS coordinates. This applies wherever the location field is used in a frame caption: `classic`'s caption line and `gallery`'s caption slots alike.

The location field SHALL resolve country, name and flag through the `offline-geolocation` capability, and SHALL therefore share its constraints: no network access and no perceptible delay.

This change SHALL be scoped to the frame caption. The same location token remains available in the free text watermark, which is drawn through a rendering path that cannot reproduce a colour emoji, and that path SHALL continue to render coordinates exactly as it does today.

#### Scenario: Photo with resolvable GPS metadata
- **WHEN** a photo whose GPS metadata resolves to a country is captioned with the location field
- **THEN** the caption text is a pin glyph, that country's localized name, and that country's flag

#### Scenario: Photo with no GPS metadata
- **WHEN** a photo carries no GPS metadata and the location field is included in the caption
- **THEN** the field renders as missing, exactly as any other unavailable metadata field does, and is elided from the caption rather than shown blank or broken

#### Scenario: Photo with unresolvable GPS metadata
- **WHEN** a photo's GPS metadata does not resolve to any country
- **THEN** the field renders as missing, the same as the no-GPS-metadata case, never as raw coordinates or a placeholder country

#### Scenario: Present in both frame styles
- **WHEN** the location field is selected in `classic`'s caption fields or assigned to a `gallery` caption slot
- **THEN** it renders identically in either place, following the same resolution and fallback rules

#### Scenario: Location token in a free text watermark is unaffected
- **WHEN** a user has placed the location token in a free text watermark rather than in a frame caption
- **THEN** it renders the coordinates it rendered before this change, with no pin glyph and no flag

#### Scenario: Flag renders as a flag
- **WHEN** a frame caption carrying a resolved location is rendered on any supported platform render path
- **THEN** the flag appears as the country's flag in full colour, not as a missing-glyph box or a flat silhouette

### Requirement: Mat fill is flat or graduated

A frame's mat SHALL be either a flat white or a top-to-bottom graduated color. `classic`, `print` and `banner` SHALL always use a flat white mat. `gallery` SHALL offer the user a choice between the two, defaulting to flat white.

Switching `gallery`'s gradient off SHALL change nothing but the fill: the caption content, its layout, the brand mark, the keyline and every measurement SHALL be identical either way. The flat tone SHALL be the same white every other style uses, so that a frame without a gradient is a white frame.

#### Scenario: Gallery without the gradient
- **WHEN** the user turns the gradient off in the `gallery` style
- **THEN** the mat is plain white with no visible gradient anywhere on it, including the side borders
- **AND** the caption, brand mark and layout are unchanged

#### Scenario: Gallery starts white
- **WHEN** a `gallery` frame is used without the user touching the gradient setting
- **THEN** the mat is plain white

#### Scenario: Gallery with the gradient
- **WHEN** the user turns the gradient on
- **THEN** the mat grades from white at the top to a darker tone at the bottom

#### Scenario: The other styles are always flat
- **WHEN** a photo is rendered in `classic`, `print` or `banner`
- **THEN** the mat is plain white wherever it is drawn, and no gradient setting is offered

### Requirement: Print lifts the photo off the mat

The `print` style SHALL cast a drop shadow behind the photo so that it reads as a print resting on, or floating above, the mat. The user SHALL choose where the shadow falls: offset downwards, or evenly on all four sides. The shadow's depth SHALL NOT be user-configurable — it SHALL be derived from the mat's thickness, as the keyline is, so it keeps its proportion at any border setting or resolution.

The shadow SHALL fall only on the mat and SHALL NEVER darken the photograph itself. The mat SHALL leave room for it, and where a caption is also present the two SHALL stack rather than overlap.

`print` SHALL NOT offer the keyline: the shadow already separates the photo from the mat, and both together fight.

The photo's corners SHALL remain square. No corner rounding SHALL be applied by this or any other style unless it is explicitly asked for.

#### Scenario: Shadow below the photo
- **WHEN** the shadow is set to fall at the bottom
- **THEN** it is offset downwards, darkening the mat beneath the photo far more than above it

#### Scenario: Shadow on all sides
- **WHEN** the shadow is set to fall on all sides
- **THEN** it is even around all four edges, so the photo reads as floating rather than resting

#### Scenario: The shadow never touches the photo
- **WHEN** a photo is rendered in `print` with either shadow setting
- **THEN** no part of the photograph is darkened by the shadow

#### Scenario: Room for the shadow and the caption
- **WHEN** a `print` frame carries both a shadow and a caption
- **THEN** the mat is tall enough for both, and the caption is not printed over the shadow

#### Scenario: Corners stay square
- **WHEN** a photo is rendered in any style
- **THEN** its corners are square, with no rounding and no mat encroaching on them

#### Scenario: Print's caption
- **WHEN** the `print` style is used
- **THEN** it shows the device credit and metadata caption described below, every field optional
- **AND** its caption is set larger, and its band given more room, than `classic`'s

### Requirement: Print caption — device credit and shooting details

The `print` style's caption SHALL be two centred lines. The first line SHALL read "Shot on" followed by the device model rendered with visual emphasis — a heavier weight than the surrounding text — e.g. "Shot on **iPhone 15 Pro Max**". This first line SHALL NOT be user-configurable, mirroring how `classic`'s single line is not slot-configurable.

The second line SHALL begin with the resolved manufacturer's name, followed by the user's selected metadata fields, using the same field-selection mechanism `classic` already offers, joined with plain spacing rather than `classic`'s "·" separator.

The user SHALL be able to add their own text before the device credit, after it, or both, on that same first line. Each SHALL be empty by default and omitted entirely when empty, like every other part of every caption, and SHALL substitute `{token}` patterns as the other free-text captions do. The device model SHALL remain the only emphasised run on the line, and the caption SHALL stay two lines.

Where a photo names no device, the user's own text SHALL still be drawn on its own, so a source with no metadata can still be signed.

The manufacturer name SHALL be resolved from the source image's metadata using the same manufacturer recognition the system already applies to select `gallery`'s brand mark, and SHALL NOT be user-chosen. It sits on the second line rather than trailing the model on the first because read back as one line the credit trails awkwardly — "Shot on iPhone 15 Pro Max Apple", "Shot on ILCE-7M4 Sony" — and for Apple devices the model already carries the brand.

Where the first line already names the device, the camera field SHALL be omitted from the second line rather than printing the same device twice.

`print` SHALL NOT offer the free-text caption prefix that `classic` offers, because its fixed first line already occupies that role and offering both would let the same lead-in appear twice. A prefix the user has previously set SHALL be preserved rather than discarded, so returning to a style that does offer it finds it intact.

#### Scenario: Device and manufacturer both resolve
- **WHEN** a photo whose metadata resolves both a device model and a recognized manufacturer is rendered in `print`
- **THEN** the first line reads "Shot on" followed by the device model in emphasized weight
- **AND** the second line begins with the manufacturer's name, ahead of the selected fields

#### Scenario: No manufacturer resolves
- **WHEN** a photo's metadata names no manufacturer the system recognizes
- **THEN** the second line shows the selected fields with no manufacturer name ahead of them — the same "gracefully omit" behavior `gallery` already applies to its brand mark
- **AND** the first line is unaffected, still crediting the device

#### Scenario: No device model at all
- **WHEN** a photo's metadata carries no device model
- **THEN** the first line is omitted entirely rather than reading "Shot on" with nothing after it

#### Scenario: Second line reflects selected fields
- **WHEN** the user selects a set of metadata fields for `print`'s caption
- **THEN** the second line shows exactly those fields, in the system's canonical field order, separated by plain spacing

#### Scenario: The user's own credit
- **WHEN** the user types their own credit for `print`
- **THEN** it is drawn on the same line as the device credit, before it, after it, or both according to which they filled in
- **AND** the caption is still two lines, and the device model is still the only emphasised text on that line

#### Scenario: No credit typed
- **WHEN** both credit fields are left empty
- **THEN** the line reads exactly as it did before, and nothing is reserved for them

#### Scenario: Nothing but the user's credit
- **WHEN** a photo resolves no device and no shooting details, but the user has typed a credit
- **THEN** that credit is the caption, since each part is dropped on its own

#### Scenario: The device is not credited twice
- **WHEN** the user selects the camera field while the first line already credits the device
- **THEN** the device model appears only on the first line, and the second line carries the remaining fields

#### Scenario: No caption prefix is offered
- **WHEN** the user selects `print` and opens its caption settings
- **THEN** the free-text caption prefix offered by `classic` is not shown, and only the field selection is

#### Scenario: A previously typed prefix survives the round trip
- **WHEN** the user types a caption prefix in `classic`, switches to `print`, then switches back to `classic`
- **THEN** the prefix they typed is still there

#### Scenario: Second line fields all missing
- **WHEN** every field selected for the second line is unavailable in the photo's metadata
- **THEN** the second line is omitted, and if the first line is also empty the caption band collapses to the same width as the other mat edges, consistent with how an empty caption behaves in other styles

### Requirement: Banner — a full-bleed photo over a caption bar

The `banner` style SHALL place the photograph against the top and both side edges of the export with no mat around it, and SHALL set its caption in a bar beneath. The bar's height SHALL be measured from the border setting exactly as `gallery`'s band is, so widening the border deepens the bar.

The bar SHALL carry two blocks, each hugging the end of the bar it sits at:

- At the left, the maker's brand mark followed by a fixed lead-in over the maker's name. The name SHALL be resolved from the photo's metadata by the same recognition that selects the mark, so the two can never disagree, and SHALL NOT be user-chosen.
- At the right, the shooting values on the first line and the equipment — the device model and its lens — on the second.

Both lines of both blocks SHALL be set in capitals with added letter spacing.

The bar's content SHALL be driven by the user's selected metadata fields: the equipment fields SHALL appear on the second right-hand line and every other selected field on the first, so no value is printed twice. Where the lens string repeats the device's own name, the repetition SHALL be dropped, the same way `gallery` already drops it.

Each part SHALL be omitted on its own when it cannot be resolved, and where nothing at all can be resolved the bar SHALL NOT be drawn: the export SHALL be the photograph alone rather than a photograph with a blank stripe under it.

`banner` SHALL NOT offer the keyline. It has no mat to stroke one in, so a keyline could only fall on the photograph or off the canvas.

#### Scenario: The photo bleeds to three edges
- **WHEN** a photo is rendered in `banner`
- **THEN** the export is the same width as the source, and the photo touches the top, left and right edges
- **AND** the export is taller than the source by the height of the caption bar

#### Scenario: The bar tracks the border setting
- **WHEN** the user widens the border in `banner`
- **THEN** the caption bar deepens in proportion

#### Scenario: Maker credited at the left
- **WHEN** a photo's metadata names a manufacturer the system recognizes
- **THEN** its mark is drawn at the far left of the bar, with the fixed lead-in above the maker's name beside it

#### Scenario: No manufacturer resolves
- **WHEN** a photo's metadata names no manufacturer the system recognizes
- **THEN** the left block is omitted entirely, mark and credit together, and the right block is unaffected

#### Scenario: The device is not named twice
- **WHEN** the selected fields include both the camera and the lens, and the lens string begins with the device's own name
- **THEN** the second right-hand line names the device once, followed by the lens with that repetition removed

#### Scenario: Equipment fields unticked
- **WHEN** the user unticks both the camera and the lens fields
- **THEN** the second right-hand line is omitted, and the shooting values remain

#### Scenario: Nothing to put in the bar
- **WHEN** a photo carries no metadata the selected fields can resolve and no recognizable manufacturer
- **THEN** no bar is drawn at all, and the export is the photograph unchanged in size

#### Scenario: No keyline in the bar style
- **WHEN** the user selects `banner`
- **THEN** the keyline setting is not offered, and no keyline is drawn regardless of the stored preference

### Requirement: Choosing a style by preview

When exactly one still image is loaded, the editor SHALL show that image rendered in every frame style, in place of the batch strip, and selecting one SHALL make it the frame's style. Each preview SHALL be rendered with the user's own settings rather than factory defaults, and SHALL show the whole framed image rather than a crop, since a frame cropped at the edges shows nothing of the frame.

These previews SHALL NOT offer the editing affordances the batch strip has — no reordering, no removal, no per-item adjustment — because they are four views of one photo rather than four photos.

With more than one image loaded, the strip SHALL keep its existing behaviour: one frame, every image.

#### Scenario: A single image
- **WHEN** one still image is loaded and the frame is enabled
- **THEN** the strip shows that image once per frame style, with the current style marked as selected
- **AND** each preview is shaped like the framed image itself, portrait for a portrait photo and wide for a wide one, rather than fitted inside a square

#### Scenario: Selecting a style from the strip
- **WHEN** the user selects one of the style previews
- **THEN** the frame switches to that style, and the settings of the style being left are kept

#### Scenario: A batch
- **WHEN** more than one image is loaded
- **THEN** the strip shows every image in the current frame, exactly as before, with its reorder, adjust and remove affordances intact

#### Scenario: Previews follow the user's settings
- **WHEN** the user changes a frame setting
- **THEN** the affected previews re-render, so what the strip shows is always the frame that would be exported

### Requirement: Settings are kept per style

Each frame style SHALL keep its own settings. Changing a setting SHALL apply to the style on screen only, and switching style SHALL restore whatever the style being returned to was last set to.

A style the user has not yet visited SHALL inherit the settings currently on screen rather than starting from factory defaults, except that a caption still at its style's default size SHALL take the new style's default instead, because the same millimetre value reads very differently in a border and in a band three times as thick.

The system SHALL offer a single control, at the top of the frame settings, that makes every subsequent edit apply to all styles at once. It SHALL default to off.

Whether the frame is drawn at all SHALL NOT be kept per style: it is one switch for the feature, so turning the frame off and then changing style SHALL NOT turn it back on.

#### Scenario: Two styles, two borders
- **WHEN** the user sets one border width in one style and a different one in another
- **THEN** each style keeps its own, and switching between them shows each as it was left

#### Scenario: Applying an edit to every style
- **WHEN** the apply-to-all control is on and the user changes a setting
- **THEN** every style takes that setting, each keeping its own identity

#### Scenario: An unvisited style
- **WHEN** the user has set a border width and then looks at a style they have never selected
- **THEN** that style shows their border width, not the factory default

#### Scenario: The frame's own switch
- **WHEN** the user turns the frame off and then changes style
- **THEN** the frame stays off

### Requirement: Sizes follow the mat

The caption text and the brand mark SHALL be measured as a proportion of the mat's thickness, so that widening the mat widens them with it and the frame keeps its proportions at any border setting.

A caption line too long for the width it is given SHALL be broken onto another line at the gaps between its readings, never splitting a reading, and SHALL be reduced in size only when the band has no room left to break into. Text scaled down to fit a fixed width does not grow when the frame does, which would defeat the rule above.

A size the user sets by hand SHALL be kept as given, and SHALL then be carried by later changes to the mat in the same proportion — a size chosen for a narrow mat is a size for that mat, and setting it again is what re-fixes the proportion. The control for either size SHALL keep the current value within its own span, so a size the mat has grown never reads as pinned to the end of its slider.

#### Scenario: Widening the mat
- **WHEN** the user increases the border width without having set the text size
- **THEN** the caption text and the brand mark grow in the same proportion

#### Scenario: A detail line that outgrows its column
- **WHEN** the mat is widened until the shooting details no longer fit across their half of the caption
- **THEN** they are set at the caption's full size and run onto a second line, rather than being shrunk to stay on one

#### Scenario: A size the user chose
- **WHEN** the user sets the text size and then widens the border
- **THEN** the text they chose grows in the same proportion as the mat, and setting the size again fixes it at the new number

#### Scenario: A frame saved before sizes followed
- **WHEN** a template saved by an earlier version, which always recorded a size, is opened
- **THEN** a size still at its default is read as untouched and follows the style it is switched to, while a size that differs from it is kept as the user's own

### Requirement: One list of what a caption may say

The system SHALL offer a single list of entries — the camera, the shooting details, the date, the dimensions, the format and where the photo was taken — that the user ticks to say what a frame's caption may include. That list SHALL apply to every style.

Every ticked entry SHALL be drawn. Where a style also chooses *placement*, as `gallery` does with its four caption lines, placement SHALL decide only where the entries it names are set: a ticked entry that no line names SHALL still be drawn, run on after the detail line of the column its subject belongs to. The columns SHALL divide by subject — what the photograph is (the device, when, and where) on one side, what the camera was doing (the lens, the exposure, the file) on the other. An entry that is unticked SHALL NOT be drawn, whatever line it has been assigned to.

No entry SHALL repeat what another entry already says. In particular the lens, which a phone writes as a spec carrying the device name, the focal length and the aperture, SHALL be reduced to the equipment's own name whenever those entries are printed beside it — in every style. A lens whose name is a *product* name SHALL be left intact, since its measurements are part of what it is called.

Free text the user has typed SHALL NOT be filtered by the list, since it is nobody's entry.

#### Scenario: Unticking an entry assigned to a line
- **WHEN** the user assigns an entry to one of `gallery`'s caption lines and then unticks that entry in the list
- **THEN** the line draws nothing, and the assignment is remembered for when it is ticked again

#### Scenario: The lens beside the readings it contains
- **WHEN** a caption includes the lens together with the camera, the focal length and the aperture
- **THEN** the lens is drawn as the equipment's name alone, with the device name, the millimetres and the f-number left to the entries whose job they are

#### Scenario: Ticking an entry no line names
- **WHEN** the user ticks an entry in a style whose caption lines are all assigned to something else
- **THEN** it is drawn on the appropriate detail line rather than nowhere, so a ticked entry is never invisible

#### Scenario: Unticking the camera in a style that credits it
- **WHEN** the user unticks the camera entry in `print`
- **THEN** the device credit is not drawn either, so the list means the same thing in every style

#### Scenario: Typed text is not an entry
- **WHEN** the user types their own text into a caption line and unticks every entry in the list
- **THEN** their text is still drawn
