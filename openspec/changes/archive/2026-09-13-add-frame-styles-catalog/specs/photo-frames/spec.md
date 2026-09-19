## MODIFIED Requirements

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

## ADDED Requirements

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
