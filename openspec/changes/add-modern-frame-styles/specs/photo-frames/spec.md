## MODIFIED Requirements

### Requirement: Frame style selection

A frame SHALL have a style, and the style SHALL determine the mat geometry and the caption layout. The system SHALL offer sixteen styles. There are four white-mat styles: `classic`, the uniform border with a single centred caption; `gallery`, the two-column caption bar with a brand mark; `print`, which lifts the photo off a plain mat with a drop shadow and credits the device above the shooting details; and `banner`, which sets a full-bleed photo over a caption bar. The other twelve are modern styles: `float`, `tone`, `swatch`, `spine`, `noir`, `readout`, `ambient`, `aura`, `blend`, `emboss`, `sunlight` and `glow`. `classic` SHALL be the default.

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
- **THEN** all sixteen styles are offered
- **AND** each style shows only the controls it actually reads

## ADDED Requirements

### Requirement: Modern styles never alter the photo

No modern style SHALL change the photo's pixels. The photo SHALL be composited unchanged into its place in the frame, with no warp, blur, colour or tone change. A style with rounded corners MAY hide the photo's corner pixels behind the frame, the way a rounded print's corners are cut, but SHALL NOT alter any pixel it shows. Effects such as light, shadow, blur and glow SHALL be confined to the frame around the photo.

#### Scenario: Photo pixels are preserved
- **WHEN** a photo is exported in any modern style
- **THEN** every photo pixel inside the photo's area, apart from corners hidden by rounding, is identical to the unframed export

#### Scenario: Sunlight stays off the photo
- **WHEN** a photo is exported in `sunlight`
- **THEN** the light-stripe pattern appears on the frame surround only and never across the photo

### Requirement: The photo stays dominant

Every modern style SHALL size its borders in proportion to the photo, using the same millimetre and resolution rules as the existing styles, so the photo remains the largest element in every export. No modern style SHALL impose a fixed output aspect ratio that adds border on one axis to reach it.

#### Scenario: Landscape photo
- **WHEN** a landscape photo is exported in `ambient` or `aura`
- **THEN** the border on each side is proportional to the photo's short edge, as it is for a portrait photo, and the export is not padded out to a portrait ratio

### Requirement: Modern style looks

Each modern style SHALL render the look approved in the change's reference renders:

- `float`: warm off-white card, rounded photo lifted by a soft shadow, caption in a deeper bottom band.
- `tone`: the border is a deep, muted version of the photo's darkest dominant colour; caption and mark are a pale tint of the same hue.
- `swatch`: white border; the photo's five dominant colours drawn as dots, ordered dark to light, beside the caption.
- `spine`: a narrow border on three sides and a wider rail on the right holding the caption, rotated to read bottom-to-top, with the mark upright at the top of the rail.
- `noir`: near-black border, photo corners slightly rounded, light caption.
- `readout`: white border with a single caption line set in capitals with monospaced digits; the aperture value is highlighted in camera yellow.
- `ambient`: the surround is the photo itself, heavily blurred and darkened; rounded photo with a soft shadow; light caption.
- `aura`: the surround is a soft blurred gradient mixed from the photo's deep and warm colours; rounded photo with a shadow tinted by the deep colour; light caption.
- `blend`: the border grades vertically from the photo's top-edge colour, slightly lightened, to its bottom-edge colour, darkened; rounded photo; light caption.
- `emboss`: pale cool-grey surface; the rounded photo is pressed in by a dark shade below-right and a light shade above-left; the caption is debossed (a light copy offset beneath a darker one).
- `sunlight`: warm wall tone with soft diagonal window-blind light stripes; the photo casts a long soft shadow away from the light.
- `glow`: near-black ground with the photo's own colours spread as a subdued halo around it; rounded photo; light caption.

#### Scenario: Each style renders its look
- **WHEN** the reference photo is exported in each modern style
- **THEN** the result matches that style's reference render in layout, surround, corner treatment and caption placement

### Requirement: Photo-derived colour and backdrop

`tone`, `swatch`, `aura` and `blend` SHALL derive their colours from the photo being framed. `ambient` and `glow` SHALL derive their surround from the photo's own pixels. For a video, these SHALL be derived from one representative frame of the video, and the surround SHALL stay fixed for the whole export. When no photo sample is available, each of these styles SHALL fall back to a neutral surround instead of failing.

#### Scenario: Different photos, different colours
- **WHEN** two photos with different dominant colours are exported in `tone`
- **THEN** their borders differ in colour, each following its own photo

#### Scenario: Video in a photo-derived style
- **WHEN** a video is exported in `ambient`, `aura`, `tone`, `swatch`, `blend` or `glow`
- **THEN** the surround is derived from one frame of that video and the export completes with the source metadata preserved

#### Scenario: Sample unavailable
- **WHEN** a photo-derived style is rendered without a photo sample
- **THEN** it renders a neutral surround with its caption, and does not fail

### Requirement: Modern style caption

Every modern style except `readout` SHALL use one shared two-column caption: the maker mark, the device model and the date and time on the left; the shooting values and the place on the right. `readout` sets the mark and model on the left and the shooting values on the right, on one line. Which entries appear SHALL follow the existing Include list, and the mark SHALL follow the existing logo switch and the maker detected from the photo's metadata. No modern style SHALL print text that is not the user's own or read from the photo's metadata. Entries with no value SHALL be dropped, and a caption with nothing to show SHALL leave no empty band.

#### Scenario: Include list controls the caption
- **WHEN** the user unticks the location in the Include list
- **THEN** no modern style shows the place

#### Scenario: Mark follows the photo's maker
- **WHEN** a photo from a recognised maker is exported in a modern style with the logo on
- **THEN** that maker's mark appears in the caption, in a tone that contrasts with the surround

#### Scenario: No metadata
- **WHEN** a photo with no readable metadata and no typed caption is exported in a modern style
- **THEN** no caption band is drawn and no placeholder text appears
