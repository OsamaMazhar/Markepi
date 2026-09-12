## ADDED Requirements

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
