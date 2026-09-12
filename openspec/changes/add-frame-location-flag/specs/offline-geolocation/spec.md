## Purpose

Resolves a GPS coordinate to the country it falls within, and derives that country's localized name and flag, entirely on-device with no network access and negligible compute cost.

## ADDED Requirements

### Requirement: Offline coordinate-to-country resolution

Given a latitude and longitude, the system SHALL determine the ISO 3166-1 alpha-2 country code that coordinate falls within, without making any network request and without perceptibly delaying the operation it supports (export/preview). The lookup SHALL function identically with the device in airplane mode or with no cellular/Wi-Fi connectivity at all.

Resolution SHALL be best-effort by nature: a coordinate very close to a land border, or over open water far from any coastline, MAY resolve to no country, or to a neighboring country rather than the exact one, without that being treated as a defect. A coordinate the system cannot confidently place SHALL return "no country" rather than a guess presented as certain.

#### Scenario: Coordinate resolves to a country
- **WHEN** a coordinate clearly within a country's territory is resolved
- **THEN** the system returns that country's ISO 3166-1 alpha-2 code

#### Scenario: No network available
- **WHEN** the device has no network connectivity of any kind
- **THEN** resolution still succeeds for a resolvable coordinate, with no difference in behavior from having a network connection

#### Scenario: Coordinate cannot be placed
- **WHEN** a coordinate falls in open ocean or another location the system has no confident answer for
- **THEN** the system returns "no country" rather than an error, a crash, or a fabricated default

#### Scenario: Near a border
- **WHEN** a coordinate falls very close to the boundary between two countries
- **THEN** the system returns one of the two plausible countries rather than failing, and this is an accepted limitation, not a defect

### Requirement: Country name and flag derivation

Given a resolved ISO 3166-1 alpha-2 country code, the system SHALL derive a flag and a display name for that country using only on-device data, with no additional bundled per-country lookup table beyond what coordinate resolution itself requires, and no network access.

#### Scenario: Flag matches the country
- **WHEN** a country code is resolved
- **THEN** the derived flag is the standard flag emoji for that country

#### Scenario: Name is localized
- **WHEN** a country code is resolved on a device set to a given language
- **THEN** the derived country name is presented in that language where the platform provides a localized name, and in a reasonable fallback otherwise
