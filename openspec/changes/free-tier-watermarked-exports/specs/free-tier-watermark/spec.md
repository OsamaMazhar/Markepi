## Purpose

Defines the automatic "Markepi" mark added to free exports: when it appears, how it looks, and how it is placed on the photo so it never covers the user's own text, logo, signature or date stamp.

## ADDED Requirements

### Requirement: Free exports carry a Markepi mark

Every Free export (photo, Live Photo still and motion clip, video, every batch item) SHALL carry the word "Markepi" as a visible watermark burned into the image or every video frame. Pro exports SHALL NOT carry it. The mark SHALL NOT appear in the editor preview, in layer lists, in templates, or in the user's saved configuration; it SHALL be added only when the export file is rendered.

#### Scenario: Free photo export
- **WHEN** a free user exports a photo
- **THEN** the exported file shows "Markepi" on the photo

#### Scenario: Preview stays clean
- **WHEN** a free user is editing and looking at the live preview
- **THEN** no "Markepi" mark is visible and the Layers panel lists only the user's own layers

#### Scenario: Pro export
- **WHEN** a Pro user exports the same edit
- **THEN** the file carries no "Markepi" mark

### Requirement: The mark sits on the photo, not the frame

The mark SHALL be placed inside the photo's own area. When a frame (border, mat, caption bar, blurred backdrop) surrounds the photo, the mark SHALL NOT be placed on the frame.

#### Scenario: Framed photo
- **WHEN** a free user exports a photo with the Noir frame
- **THEN** the mark lies entirely inside the photo rectangle, inset from its edges

### Requirement: The mark avoids the user's elements

The system SHALL treat every visible user element drawn on the photo — text layers, logo layers, signature layers and the date stamp — as occupied space, using where each actually renders (including freely dragged positions). The mark SHALL be placed in the first candidate slot whose area does not overlap any occupied space, trying slots in this order:

1. the four corners: bottom-right, bottom-left, top-right, top-left;
2. the centre;
3. bottom-middle, then top-middle.

The middle of the left edge and the middle of the right edge SHALL never be used. When every candidate overlaps something, the mark SHALL go in the candidate slot with the smallest overlap (ties resolved in the order above). Hidden layers SHALL NOT count as occupied.

#### Scenario: Nothing on the photo
- **WHEN** a free user exports a photo with no layers
- **THEN** the mark is in the bottom-right corner

#### Scenario: User text bottom-right
- **WHEN** the user's text layer is at bottom-right
- **THEN** the mark is in the bottom-left corner

#### Scenario: All four corners used
- **WHEN** the user has elements in all four corners
- **THEN** the mark is in the centre

#### Scenario: Corners and centre used
- **WHEN** the user has elements in all four corners and the centre
- **THEN** the mark is at bottom-middle, or at top-middle if bottom-middle is also occupied
- **AND** it is never at middle-left or middle-right

#### Scenario: Dragged element
- **WHEN** the user has dragged a logo so it covers the bottom-right corner area
- **THEN** the mark does not use bottom-right

#### Scenario: Hidden layer
- **WHEN** a text layer at bottom-right is switched off
- **THEN** the mark may use bottom-right

### Requirement: The mark is readable but unobtrusive

The mark SHALL be white "Markepi" text with a soft dark shadow so it reads on light and dark photos, at partial opacity, sized relative to the photo's shorter side so it is the same visual size on photos and videos of any resolution, with an inset from the photo edges consistent with the user's own layer padding.

#### Scenario: Bright sky behind the mark
- **WHEN** the mark lands on a near-white area
- **THEN** it remains legible because of its shadow

#### Scenario: Same edit, photo and video
- **WHEN** the same configuration is exported as a free photo and a free 1080p video
- **THEN** the mark occupies the same fraction of the shorter side in both

### Requirement: Video marks are placed once for the whole clip

For a video, the slot SHALL be chosen once from the user's elements and SHALL stay fixed for the whole clip.

#### Scenario: Free video
- **WHEN** a free user exports a video with a logo at bottom-right
- **THEN** the mark is in the bottom-left corner on every frame
