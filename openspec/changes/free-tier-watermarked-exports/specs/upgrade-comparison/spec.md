## Purpose

Defines the Free vs Pro comparison a free user sees when exporting: what it shows for photos and videos, the choices it offers, and how the export continues after each choice.

## ADDED Requirements

### Requirement: Free users see a comparison before exporting

When a free user starts an export (single photo, Live Photo, video or batch), the system SHALL show a comparison sheet before rendering the export — on every export, every time. The sheet SHALL NOT offer "Don't show again" or any other way to suppress it, and SHALL NOT be rate-limited or skipped after repeated free exports. Pro users SHALL NOT see it and SHALL export directly.

#### Scenario: Free user taps Export
- **WHEN** a free user taps Export on a photo
- **THEN** the comparison sheet appears

#### Scenario: Repeated free exports
- **WHEN** a free user taps "Export free", then exports again (the same or another photo)
- **THEN** the comparison sheet appears again, and it has no option to stop showing it

#### Scenario: Pro user taps Export
- **WHEN** a Pro user taps Export
- **THEN** the export starts with no comparison sheet

### Requirement: The comparison shows the user's own edit in both tiers

The sheet SHALL show two cards built from the user's current edit: a **Pro** card with the image as Pro exports it (no Markepi mark, HDR shown where the source has it), and a **Free** card with the image as Free exports it (with the Markepi mark in the slot the export will use, SDR). Each card SHALL list its specs:

- Pro: full resolution (e.g. "4032×3024 · 12 MP"), "HDR" when the source is HDR, "No watermark".
- Free: reduced resolution (e.g. "2048×1536 · 3.1 MP"), "SDR", "Markepi mark".

For a video the cards SHALL show a frame of the video and video specs: Pro source resolution and HDR; Free "1080p", "SDR", "Markepi mark". For a batch the cards SHALL show the first item and state the item count.

The Pro card SHALL be visually emphasised (gold accent) as the recommended option. The layout SHALL stack the cards in portrait and place them side by side in landscape, and SHALL fit without scrolling on every supported iPhone and iPad.

#### Scenario: HDR photo comparison
- **WHEN** a free user exports a 12 MP HDR photo with a text layer at bottom-right
- **THEN** the Pro card shows 4032×3024 · 12 MP and HDR with no mark
- **AND** the Free card shows 2048×1536, SDR and the Markepi mark at bottom-left

#### Scenario: Video comparison
- **WHEN** a free user exports a 4K HDR video
- **THEN** the Pro card says 4K and HDR, and the Free card says 1080p and SDR with the mark

### Requirement: The comparison offers three outcomes

The sheet SHALL offer:

- **Unlock full quality** (primary, also triggered by tapping the Pro card): opens the Markepi Pro paywall.
- **Export free** (also triggered by tapping the Free card): closes the sheet and exports in the Free tier, continuing to the share sheet (or the Content Credentials receipt when signing).
- Dismissing the sheet (swipe down or close): cancels the export; nothing is rendered.

#### Scenario: Export free
- **WHEN** the user taps "Export free"
- **THEN** a Free-tier file is rendered and the share sheet opens

#### Scenario: Dismiss
- **WHEN** the user swipes the sheet away
- **THEN** no file is rendered and the editor is unchanged

### Requirement: The export resumes after a purchase

If the user opens the paywall from the comparison and completes a purchase or restore, the original export SHALL continue automatically in the Pro tier without the user tapping Export again. If the user closes the paywall without buying, the comparison sheet SHALL come back so they can still export free or cancel.

#### Scenario: Buys Pro from the comparison
- **WHEN** the user taps "Unlock full quality" and buys the lifetime unlock
- **THEN** the paywall closes and the full-quality export renders and opens the share sheet

#### Scenario: Backs out of the paywall
- **WHEN** the user opens the paywall from the comparison and closes it without buying
- **THEN** the comparison sheet is shown again

### Requirement: The paywall sells full quality, not export count

The Markepi Pro paywall SHALL describe Pro as full-resolution exports, HDR photos and videos, and no Markepi watermark. It SHALL NOT mention a daily export limit, because none exists.

#### Scenario: Free user opens the paywall from the crown
- **WHEN** a free user taps the crown in the editor
- **THEN** the paywall's headline and benefits describe full resolution, HDR and no watermark, and nothing mentions daily limits
