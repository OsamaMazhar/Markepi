## Purpose

Describes the looks a user can apply to a photo before it is framed, watermarked and shared: the catalogue of moods, skin-aware undertones and film emulations, their controls, how they treat people, and the guarantees about quality, metadata, preview fidelity, persistence and free/Pro access that every styled export keeps.

## ADDED Requirements

### Requirement: Style catalogue

The system SHALL offer a photo style chosen from four groups:
- **Original**: no style.
- **Moods**: Vibrant, Natural, Luminous, Dramatic, Quiet, Cozy, Ethereal, Muted B&W, Stark B&W.
- **Undertones**: Neutral, Cool Rose, Rose Gold, Gold, Amber.
- **Film**: Portrait 400, Golden 200, Chrome 100, Velvet 50, Classic Neg, Tungsten 800, Silver 400, Faded.

Original SHALL be the default. Style names SHALL NOT use camera-maker or film-maker trademarks. The feature SHALL NOT be called "Photographic Styles" anywhere in the app or its store copy.

#### Scenario: Default style
- **WHEN** a photo is opened and the user has never chosen a style
- **THEN** the style is Original and the exported photo's pixels are identical to an export made without the style feature

#### Scenario: Browsing the catalogue
- **WHEN** the user opens the Style tool
- **THEN** the Moods, Undertones and Film groups are offered, each showing its looks as thumbnails rendered from the current photo

#### Scenario: Works on any supported iPhone
- **WHEN** the app runs on an iPhone without Apple's latest-generation Photographic Styles (for example iPhone 12–15)
- **THEN** every look in the catalogue is available and renders the same as it does on newer iPhones

### Requirement: Style controls

Every look except Original SHALL expose an Intensity control from 0% to 100%. The default SHALL be 100%, and 0% SHALL equal Original. Every look except Original SHALL expose a Tone/Color pad: Tone runs from darker to brighter, Color from cooler to warmer, and the centre leaves the look unchanged. Film looks SHALL also expose a Grain control from 0% to 100%, defaulting to that film's own amount. Choosing a different look SHALL reset the pad to centre and Intensity and Grain to that look's defaults.

#### Scenario: Zero intensity
- **WHEN** a look is selected with Intensity set to 0%
- **THEN** the rendered photo equals the Original rendering

#### Scenario: Pad centre
- **WHEN** the Tone/Color pad is at its centre
- **THEN** the look renders exactly as its recipe defines, with no extra tone or colour shift

#### Scenario: Warmer color
- **WHEN** the user moves the pad toward warmer
- **THEN** neutral grays in the preview shift toward amber and the preview refreshes while dragging

#### Scenario: Grain only on film
- **WHEN** a Mood or Undertone look is selected
- **THEN** no Grain control is shown and the render contains no grain

### Requirement: Hold to compare

Pressing and holding the photo canvas while a look is active SHALL show the photo without the look, with frames and watermarks still drawn. Releasing SHALL restore the styled preview.

#### Scenario: Compare
- **WHEN** a look is active and the user presses and holds the canvas
- **THEN** the canvas shows the unstyled photo inside the same frame and watermarks until the press ends

### Requirement: Skin-aware undertones

An undertone SHALL shift skin strongly and the rest of the photo lightly. Skin SHALL be identified from the skin matte embedded in the photo when there is one, otherwise by on-device person detection combined with skin-colour detection. When no person is found, the undertone SHALL apply only its light global shift. Mask edges SHALL be soft, so no hard outline appears around people. Skin detection SHALL run entirely on device.

#### Scenario: Portrait-mode photo with embedded skin matte
- **WHEN** an Amber undertone is applied to a Portrait-mode photo that embeds a skin matte
- **THEN** the skin regions shift toward amber noticeably more than the background, following the embedded matte

#### Scenario: Ordinary photo of a person
- **WHEN** a Rose Gold undertone is applied to a photo with a person but no embedded matte
- **THEN** the person's skin shifts more than the background, with no visible hard edge at the person's outline

#### Scenario: Landscape with no people
- **WHEN** an undertone is applied to a photo with no person
- **THEN** only a light global shift is applied and no error is shown

### Requirement: Film character

Film looks SHALL add grain. The grain SHALL be monochrome, strongest in the midtones, and sized relative to the photo's short edge, so it looks the same at any resolution. Grain SHALL be deterministic: rendering the same photo with the same settings twice gives identical pixels. Tungsten 800 SHALL add a soft red-orange halation around bright highlights. Silver 400 SHALL be black-and-white.

#### Scenario: Deterministic grain
- **WHEN** the same photo is exported twice with the same film look and settings
- **THEN** both exports have identical pixels

#### Scenario: Grain scales with resolution
- **WHEN** a film look is previewed at screen size and exported at full resolution
- **THEN** the grain covers the same fraction of the image in both

#### Scenario: Halation
- **WHEN** Tungsten 800 is applied to a photo with a bright point light on a dark background
- **THEN** a soft red-orange glow surrounds the light, and dark areas away from the light are not tinted

### Requirement: Rendering order

A style SHALL apply to the photo only, before the frame and before any watermark, signature, logo, date stamp or free-tier mark. Frame styles that take colour or blur from the photo SHALL read the styled photo. Watermark layers, signatures, logos, the date stamp and the frame mat SHALL NOT be altered by the style.

#### Scenario: Watermark keeps its colour
- **WHEN** a white text watermark is placed on a photo with Stark B&W applied
- **THEN** the watermark renders in its own colour, unaffected by the look

#### Scenario: Photo-derived frame follows the style
- **WHEN** a frame style that samples the photo's colours is used with a Film look
- **THEN** the frame's colours come from the styled photo

### Requirement: Quality and metadata preservation

A styled export SHALL keep everything an unstyled export keeps: all source metadata (EXIF, GPS, dates, device, XMP, IPTC), the colour profile, the HDR gain map when the export tier keeps HDR, alpha handling, and Content Credentials behaviour. A B&W look SHALL produce an RGB image in the source's colour space, never a grayscale file. Styling SHALL NOT save anything to the photo library.

#### Scenario: Metadata survives
- **WHEN** a Pro user exports an HDR HEIC photo with GPS and the Cozy look
- **THEN** the exported file keeps the original GPS, capture date, device model and colour profile, and still carries an HDR gain map

#### Scenario: B&W stays RGB
- **WHEN** a photo is exported with Muted B&W and a coloured logo watermark
- **THEN** the export is an RGB image in which the logo keeps its colour

### Requirement: Preview matches export

The live preview, the style thumbnails and the export SHALL render the same look for the same settings, including skin masking and grain scale. Changing any style setting SHALL refresh the live preview.

#### Scenario: Preview refresh
- **WHEN** the user changes the look, Intensity, the pad or Grain
- **THEN** the live preview re-renders with the new setting and no other interaction is needed

#### Scenario: Same skin mask in preview and export
- **WHEN** an undertone is previewed and then exported
- **THEN** the skin regions shifted in the export match those shifted in the preview

### Requirement: Persistence

The chosen look and its settings SHALL persist with the editor configuration and in saved templates. They SHALL apply to every photo of a batch, and each photo's skin mask SHALL be detected from that photo. A configuration or template saved before styles existed SHALL load as Original. A look this build does not know SHALL load as Original without failing.

#### Scenario: Old template
- **WHEN** a template saved before styles existed is loaded
- **THEN** it loads without error with the style set to Original

#### Scenario: Unknown look
- **WHEN** a configuration names a look newer than the running build understands
- **THEN** it loads with the style set to Original

#### Scenario: Batch
- **WHEN** a batch of three photos is exported with the Gold undertone
- **THEN** all three exports are styled and each uses skin detected in its own photo

### Requirement: Free and Pro access

Free users SHALL be able to export with Original, Vibrant, Natural and the Neutral undertone at default settings. Every other look, and Intensity, the Tone/Color pad and Grain, SHALL require Pro. Free users SHALL be able to select and preview Pro looks, which are marked as Pro. When a free user exports while a Pro look or a Pro control is in effect, the Free vs Pro comparison sheet SHALL show the Pro version with the look and the Free version without it. A free export SHALL then be rendered without the Pro look or Pro control setting. Pro users SHALL never see a style-related prompt.

#### Scenario: Free user previews a Pro look
- **WHEN** a free user taps Chrome 100
- **THEN** the preview shows Chrome 100 and the thumbnail carries a Pro marker

#### Scenario: Free export with a Pro look
- **WHEN** a free user exports with Chrome 100 selected and chooses to export free
- **THEN** the exported photo is rendered with Original, and the comparison sheet showed the styled Pro version beside the unstyled Free version

#### Scenario: Free look
- **WHEN** a free user exports with Vibrant at default settings
- **THEN** the export is styled with Vibrant, within the free tier's usual resolution, compression and mark rules

### Requirement: Media scope

Styles SHALL apply to still photos and to the still of a Live Photo. When a look other than Original is active on a Live Photo, the export SHALL be a still photo, and the Style tool SHALL say so before export. Styles SHALL NOT be offered for video items in this version. The Style tool SHALL be disabled for a video and show a short explanation.

#### Scenario: Live Photo with a look
- **WHEN** a Live Photo is exported with Velvet 50 applied
- **THEN** a styled still photo is shared without its motion, and the Style tool stated beforehand that the export would be a still

#### Scenario: Live Photo with Original
- **WHEN** a Live Photo is exported with Original
- **THEN** it exports as a Live Photo exactly as it does today

#### Scenario: Video
- **WHEN** the current item is a video
- **THEN** the Style tool is disabled with a short explanation, and the video export is unchanged
