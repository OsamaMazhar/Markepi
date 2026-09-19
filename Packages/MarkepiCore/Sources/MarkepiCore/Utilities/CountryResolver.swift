import Foundation

/// Resolves a GPS coordinate to the country it falls in, entirely on-device.
///
/// No network, by requirement: `CLGeocoder` and MapKit both need a round trip
/// to Apple's geocoding service and have no offline mode, so this carries its
/// own simplified boundary set instead (`Resources/Geo/countries.bin`, built by
/// `tools/geo/build-country-boundaries.py`).
///
/// Best-effort by nature. The boundaries are simplified, so a coordinate within
/// a few kilometres of a land border may resolve to the neighbour.
///
/// ponytail: simplified boundaries from Natural Earth 1:10m. If border
/// complaints ever appear, the upgrade path is rebuilding the resource at a
/// tighter tolerance — the format and this code do not change.
public enum CountryResolver {

    // MARK: - Public API

    /// The ISO 3166-1 alpha-2 code for a coordinate, or nil when it falls in no
    /// country — open ocean, or a territory the dataset does not carry.
    ///
    /// - Parameters:
    ///   - latitude: signed degrees, positive north.
    ///   - longitude: signed degrees, positive east.
    ///
    /// The coordinates must already be signed. EXIF stores unsigned magnitudes
    /// with a separate hemisphere reference, and handing those straight in is
    /// silent and total: Sydney resolves to open Pacific and São Paulo to
    /// central Asia, with nothing to warn you. `EXIFTokenParser` applies the
    /// refs before calling here.
    public static func countryCode(latitude: Double, longitude: Double) -> String? {
        guard latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            return nil
        }
        return boundaries.country(latitude: latitude, longitude: longitude)
    }

    /// The flag emoji for an ISO 3166-1 alpha-2 code.
    ///
    /// Built from the two letters rather than from bundled artwork: a country
    /// code maps to a pair of Unicode Regional Indicator Symbols, which every
    /// emoji-capable font composes into that country's flag.
    public static func flag(for countryCode: String) -> String? {
        let letters = countryCode.uppercased()
        guard letters.count == 2 else { return nil }
        var flag = ""
        for character in letters.unicodeScalars {
            guard ("A"..."Z").contains(character),
                  let indicator = Unicode.Scalar(character.value + 0x1F1E6 - 0x41) else {
                return nil
            }
            flag.unicodeScalars.append(indicator)
        }
        return flag
    }

    /// The country's name in the viewer's language.
    ///
    /// Falls back to the code itself where the platform has no localized name,
    /// so a caption shows *something* rather than silently losing its location.
    public static func localizedName(for countryCode: String) -> String {
        // The code has to be checked against the platform's own region list
        // first. `localizedString(forRegionCode:)` does not return nil for a
        // code it does not know — it returns a *localized* "Unknown Region",
        // which would have gone straight into the caption, and which no amount
        // of string matching can reliably catch across languages.
        let code = countryCode.uppercased()
        // "ZZ" is the standard code for an unknown or invalid region, and the
        // platform does consider it a valid ISO region — it names it "Unknown
        // Region". That is never a caption anyone wants, so it is rejected
        // ahead of the general check.
        let region = Locale.Region(code)
        guard code != "ZZ", region.isISORegion,
              // An instance method on Locale, not a static one, and it does
              // return an optional for other reasons.
              let name = Locale.current.localizedString(forRegionCode: region.identifier),
              !name.isEmpty else {
            return countryCode
        }
        return name
    }

    /// The finished caption fragment for a coordinate — pin, country, flag —
    /// or nil when the coordinate resolves to no country.
    public static func placeDescription(latitude: Double, longitude: Double) -> String? {
        guard let code = countryCode(latitude: latitude, longitude: longitude) else { return nil }
        let name = localizedName(for: code)
        guard let flag = flag(for: code) else { return "📍 \(name)" }
        return "📍 \(name) \(flag)"
    }

    // MARK: - Boundary data

    /// Parsed once, on first use, and kept for the life of the process.
    ///
    /// Only the index — 239 codes and bounding boxes — is parsed up front. The
    /// ring points stay in the loaded `Data` and are decoded only for the
    /// handful of countries whose bounding box actually contains the point,
    /// which is both less memory and less work than inflating 75,000 points
    /// nobody will look at.
    static let boundaries = Boundaries()

    struct Boundaries: Sendable {
        /// One country's bounding box and where its rings live in `data`.
        struct Entry: Sendable {
            let code: String
            let minLat, minLon, maxLat, maxLon: Double
            let ringCount: Int
            let offset: Int
        }

        private let data: [UInt8]
        private let entries: [Entry]

        private static let bboxScale = 1_000_000.0
        private static let pointMax = 65_535.0

        init(bundle: Bundle? = nil) {
            guard let url = (bundle ?? .module).url(
                    forResource: "countries", withExtension: "bin", subdirectory: "Geo"),
                  let loaded = try? Data(contentsOf: url),
                  loaded.count > 12,
                  loaded.prefix(8).elementsEqual("MKGEO2\0\0".utf8) else {
                // A missing or unreadable resource means every lookup returns
                // nil, and the caption elides its location field — the same
                // path a photo with no GPS already takes.
                self.data = []
                self.entries = []
                return
            }

            let bytes = [UInt8](loaded)
            var cursor = 8
            let count = Int(Self.readUInt32(bytes, cursor)); cursor += 4

            var parsed: [Entry] = []
            parsed.reserveCapacity(count)
            for _ in 0..<count {
                guard cursor + 22 <= bytes.count else { break }
                let code = String(decoding: bytes[cursor..<(cursor + 2)], as: UTF8.self)
                cursor += 2
                let ringCount = Int(Self.readUInt16(bytes, cursor)); cursor += 2
                let minLat = Double(Self.readInt32(bytes, cursor)) / Self.bboxScale
                let minLon = Double(Self.readInt32(bytes, cursor + 4)) / Self.bboxScale
                let maxLat = Double(Self.readInt32(bytes, cursor + 8)) / Self.bboxScale
                let maxLon = Double(Self.readInt32(bytes, cursor + 12)) / Self.bboxScale
                cursor += 16

                parsed.append(Entry(code: code, minLat: minLat, minLon: minLon,
                                    maxLat: maxLat, maxLon: maxLon,
                                    ringCount: ringCount, offset: cursor))

                // Skip the rings themselves; they are decoded on demand.
                for _ in 0..<ringCount {
                    guard cursor + 4 <= bytes.count else { break }
                    let points = Int(Self.readUInt32(bytes, cursor))
                    cursor += 4 + points * 4
                }
            }
            self.data = bytes
            self.entries = parsed
        }

        var countryCodes: [String] { entries.map(\.code) }

        /// The country containing a point, or nil.
        func country(latitude: Double, longitude: Double) -> String? {
            // The bounding-box compare rejects almost every country for the
            // cost of four comparisons, so the ray cast only ever runs on the
            // few whose box the point is actually inside.
            var fallback: String?
            for entry in entries where entry.contains(latitude: latitude, longitude: longitude) {
                if containsPoint(entry, latitude: latitude, longitude: longitude) {
                    // A territory whose box sits inside a larger country's box
                    // should win over that country, and being smaller it is the
                    // more specific answer.
                    if let current = fallback, area(of: entry) >= areaOfCode(current) {
                        continue
                    }
                    fallback = entry.code
                }
            }
            return fallback
        }

        private func area(of entry: Entry) -> Double {
            (entry.maxLat - entry.minLat) * (entry.maxLon - entry.minLon)
        }

        private func areaOfCode(_ code: String) -> Double {
            entries.first { $0.code == code }.map(area(of:)) ?? .greatestFiniteMagnitude
        }

        /// Even-odd ray casting across every ring of one country.
        ///
        /// Multipolygon by construction: an archipelago or an exclave is just
        /// more rings, and a point inside any of them is inside the country.
        private func containsPoint(_ entry: Entry, latitude: Double, longitude: Double) -> Bool {
            let latSpan = max(entry.maxLat - entry.minLat, 1e-9)
            let lonSpan = max(entry.maxLon - entry.minLon, 1e-9)
            var cursor = entry.offset
            var inside = false

            for _ in 0..<entry.ringCount {
                guard cursor + 4 <= data.count else { break }
                let pointCount = Int(Self.readUInt32(data, cursor))
                cursor += 4
                guard pointCount >= 3, cursor + pointCount * 4 <= data.count else {
                    cursor += pointCount * 4
                    continue
                }

                func point(_ index: Int) -> (lat: Double, lon: Double) {
                    let at = cursor + index * 4
                    let fx = Double(Self.readUInt16(data, at))
                    let fy = Double(Self.readUInt16(data, at + 2))
                    return (entry.minLat + fx / Self.pointMax * latSpan,
                            entry.minLon + fy / Self.pointMax * lonSpan)
                }

                var j = pointCount - 1
                for i in 0..<pointCount {
                    let a = point(i), b = point(j)
                    if (a.lat > latitude) != (b.lat > latitude) {
                        let slope = (b.lon - a.lon) / (b.lat - a.lat)
                        if longitude < a.lon + (latitude - a.lat) * slope {
                            inside.toggle()
                        }
                    }
                    j = i
                }
                cursor += pointCount * 4
            }
            return inside
        }

        // MARK: Little-endian readers

        private static func readUInt16(_ bytes: [UInt8], _ at: Int) -> UInt16 {
            UInt16(bytes[at]) | UInt16(bytes[at + 1]) << 8
        }

        private static func readUInt32(_ bytes: [UInt8], _ at: Int) -> UInt32 {
            UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8
            | UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24
        }

        private static func readInt32(_ bytes: [UInt8], _ at: Int) -> Int32 {
            Int32(bitPattern: readUInt32(bytes, at))
        }
    }
}

extension CountryResolver.Boundaries.Entry {
    func contains(latitude: Double, longitude: Double) -> Bool {
        latitude >= minLat && latitude <= maxLat && longitude >= minLon && longitude <= maxLon
    }
}
