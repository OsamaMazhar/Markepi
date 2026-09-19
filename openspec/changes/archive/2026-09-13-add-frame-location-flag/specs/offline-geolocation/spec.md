## Purpose

Resolves a GPS coordinate to the country it falls within, and derives that country's localized name and flag, entirely on-device with no network access and negligible cost per export.

## ADDED Requirements

### Requirement: Offline coordinate-to-country resolution

Given a latitude and longitude, the system SHALL determine the ISO 3166-1 alpha-2 country code that coordinate falls within, without making any network request and without perceptibly delaying the operation it supports (export/preview). The lookup SHALL function identically with the device in airplane mode or with no cellular/Wi-Fi connectivity at all.

Resolution SHALL be best-effort by nature: a coordinate very close to a land border, or over open water far from any coastline, MAY resolve to no country, or to a neighboring country rather than the exact one, without that being treated as a defect. A coordinate the system cannot confidently place SHALL return "no country" rather than a guess presented as certain.

Small sovereign territories — city-states and small island nations — SHALL be resolvable. An approach whose spatial granularity is too coarse to distinguish them does not satisfy this requirement.

#### Scenario: Coordinate resolves to a country
- **WHEN** a coordinate clearly within a country's territory is resolved
- **THEN** the system returns that country's ISO 3166-1 alpha-2 code

#### Scenario: No network available
- **WHEN** the device has no network connectivity of any kind
- **THEN** resolution still succeeds for a resolvable coordinate, with no difference in behavior from having a network connection

#### Scenario: Small territory
- **WHEN** a coordinate within a city-state or small island nation is resolved
- **THEN** the system returns that territory's own code, rather than no country or a surrounding country's code

#### Scenario: Territory away from its mainland
- **WHEN** a coordinate falls on an island or exclave belonging to a country whose main landmass is elsewhere
- **THEN** the system returns that country's code, the same as a coordinate on its mainland would

#### Scenario: Coordinate cannot be placed
- **WHEN** a coordinate falls in open ocean or another location the system has no confident answer for
- **THEN** the system returns "no country" rather than an error, a crash, or a fabricated default

#### Scenario: Near a border
- **WHEN** a coordinate falls very close to the boundary between two countries
- **THEN** the system returns one of the two plausible countries rather than failing, and this is an accepted limitation, not a defect

### Requirement: Coordinates are interpreted with their hemisphere

Resolution SHALL interpret a coordinate's hemisphere correctly regardless of how the source recorded it. Where image metadata stores latitude and longitude as unsigned magnitudes alongside a separate hemisphere reference, as the EXIF GPS dictionary does, the reference SHALL be applied before the coordinate is placed. A coordinate SHALL NOT be resolved as though every location were north of the equator and east of the prime meridian.

#### Scenario: Southern hemisphere
- **WHEN** a photo taken south of the equator is resolved
- **THEN** it resolves to the country it was actually taken in, not to the mirrored location at the same latitude north

#### Scenario: Western hemisphere
- **WHEN** a photo taken west of the prime meridian is resolved
- **THEN** it resolves to the country it was actually taken in, not to the mirrored location at the same longitude east

#### Scenario: Hemisphere reference absent
- **WHEN** metadata carries a coordinate with no hemisphere reference alongside it
- **THEN** the coordinate's own sign is used, and resolution proceeds rather than failing

### Requirement: Country name and flag derivation

Given a resolved ISO 3166-1 alpha-2 country code, the system SHALL derive a flag and a display name for that country using only on-device data, with no additional bundled per-country lookup table beyond what coordinate resolution itself requires, and no network access.

#### Scenario: Flag matches the country
- **WHEN** a country code is resolved
- **THEN** the derived flag is the standard flag emoji for that country

#### Scenario: Name is localized
- **WHEN** a country code is resolved on a device set to a given language
- **THEN** the derived country name is presented in that language where the platform provides a localized name

#### Scenario: Platform has no name for the code
- **WHEN** the platform returns no localized name for a resolved code
- **THEN** the country code itself is used as the display name, so the location is still shown rather than silently dropped
