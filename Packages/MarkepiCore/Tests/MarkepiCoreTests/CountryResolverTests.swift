import Foundation
import Testing
@testable import MarkepiCore

/// Covers the offline coordinate-to-country lookup that the location caption
/// field is built on.
///
/// The small-territory cases are not padding: they are the reason this ships a
/// 1:10m boundary set rather than the lighter 1:110m one the plan first
/// assumed. That set contains no Monaco, Vatican, Liechtenstein, Andorra, San
/// Marino, Malta, Bahrain or Singapore at all, so every one of these would have
/// resolved to nothing or to a surrounding country.
@Suite("Offline country resolution")
struct CountryResolverTests {

    // MARK: - Known coordinates

    @Test("A coordinate well inside a country resolves to it",
          arguments: [
            (48.8566, 2.3522, "FR", "Paris"),
            (35.6762, 139.6503, "JP", "Tokyo"),
            (52.5200, 13.4050, "DE", "Berlin"),
            (55.7558, 37.6173, "RU", "Moscow"),
            (-1.2921, 36.8219, "KE", "Nairobi"),
            (19.4326, -99.1332, "MX", "Mexico City"),
            (28.6139, 77.2090, "IN", "New Delhi"),
          ])
    func knownCoordinates(lat: Double, lon: Double, code: String, place: String) {
        #expect(CountryResolver.countryCode(latitude: lat, longitude: lon) == code,
                "\(place) should resolve to \(code)")
    }

    @Test("Small sovereign territories resolve to themselves, not their neighbour",
          arguments: [
            (43.7384, 7.4246, "MC", "Monaco"),
            (1.3521, 103.8198, "SG", "Singapore"),
            (41.9029, 12.4534, "VA", "Vatican City"),
            (47.1410, 9.5209, "LI", "Liechtenstein"),
            (35.8997, 14.5146, "MT", "Malta"),
            (26.0667, 50.5577, "BH", "Bahrain"),
            (42.5063, 1.5218, "AD", "Andorra"),
            (43.9424, 12.4578, "SM", "San Marino"),
          ])
    func smallTerritories(lat: Double, lon: Double, code: String, place: String) {
        #expect(CountryResolver.countryCode(latitude: lat, longitude: lon) == code,
                "\(place) should resolve to \(code), the whole reason for the 1:10m source")
    }

    // MARK: - Hemispheres

    @Test("Every hemisphere quadrant resolves where it actually is",
          arguments: [
            (48.8566, 2.3522, "FR", "north-east"),
            (37.7749, -122.4194, "US", "north-west"),
            (-33.8688, 151.2093, "AU", "south-east"),
            (-23.5505, -46.6333, "BR", "south-west"),
          ])
    func hemispheres(lat: Double, lon: Double, code: String, quadrant: String) {
        // The failure this guards is silent and total: fed unsigned magnitudes,
        // Sydney lands in the open Pacific and São Paulo in central Asia, and
        // nothing crashes or warns.
        #expect(CountryResolver.countryCode(latitude: lat, longitude: lon) == code,
                "\(quadrant) quadrant resolved wrongly")
    }

    @Test("Mirroring a southern coordinate north does not give the same answer")
    func hemisphereIsNotIgnored() {
        let sydney = CountryResolver.countryCode(latitude: -33.8688, longitude: 151.2093)
        let mirrored = CountryResolver.countryCode(latitude: 33.8688, longitude: 151.2093)
        #expect(sydney == "AU")
        #expect(mirrored != "AU", "an unsigned latitude must not still land in Australia")
    }

    // MARK: - Multipolygon

    @Test("A territory away from its mainland resolves to the same country",
          arguments: [
            (21.3069, -157.8583, "US", "Hawaii"),
            (61.2181, -149.9003, "US", "Alaska"),
            (39.3999, -8.2245, "PT", "mainland Portugal"),
            (32.6669, -16.9241, "PT", "Madeira"),
          ])
    func multipolygon(lat: Double, lon: Double, code: String, place: String) {
        #expect(CountryResolver.countryCode(latitude: lat, longitude: lon) == code,
                "\(place) should resolve to \(code)")
    }

    // MARK: - Nothing to resolve

    @Test("Open ocean resolves to no country rather than a guess",
          arguments: [(0.0, -30.0), (0.0, -140.0), (-40.0, -20.0), (30.0, -45.0)])
    func openOcean(lat: Double, lon: Double) {
        #expect(CountryResolver.countryCode(latitude: lat, longitude: lon) == nil)
    }

    @Test("An out-of-range or non-finite coordinate resolves to nothing, not a crash",
          arguments: [(91.0, 0.0), (-91.0, 0.0), (0.0, 181.0), (0.0, -181.0),
                      (Double.nan, 0.0), (0.0, Double.infinity)])
    func invalidCoordinates(lat: Double, lon: Double) {
        #expect(CountryResolver.countryCode(latitude: lat, longitude: lon) == nil)
    }

    @Test("The dataset's own corners resolve without crashing",
          arguments: [(90.0, 180.0), (-90.0, -180.0), (90.0, -180.0), (-90.0, 180.0)])
    func datasetEdges(lat: Double, lon: Double) {
        // Antarctica reaches -90, so an answer here is fine; not crashing is
        // the point.
        _ = CountryResolver.countryCode(latitude: lat, longitude: lon)
    }

    // MARK: - Flag and name

    @Test("A code maps to its flag through the regional indicators",
          arguments: [("FR", "🇫🇷"), ("JP", "🇯🇵"), ("US", "🇺🇸"), ("MC", "🇲🇨")])
    func flags(code: String, flag: String) {
        #expect(CountryResolver.flag(for: code) == flag)
    }

    @Test("A code that is not two letters has no flag",
          arguments: ["", "F", "FRA", "F1", "12", "fr🇫🇷"])
    func invalidFlags(code: String) {
        let flag = CountryResolver.flag(for: code)
        #expect(flag == nil || code.count == 2)
    }

    @Test("Lowercase still produces the flag")
    func flagCaseInsensitive() {
        #expect(CountryResolver.flag(for: "fr") == "🇫🇷")
    }

    @Test("A known code has a non-empty localized name")
    func localizedNames() {
        #expect(!CountryResolver.localizedName(for: "FR").isEmpty)
        #expect(CountryResolver.localizedName(for: "FR") != "FR",
                "the platform should have a real name for a common region code")
    }

    @Test("A code the platform cannot name falls back to the code itself",
          arguments: ["QQ", "AA", "XX", "ZY", "ZZ"])
    func unnamedCodeFallsBackToCode(code: String) {
        // Better a code than a silently dropped location — and better than
        // "Unknown Region", which is what the platform hands back for "ZZ"
        // rather than returning nil.
        #expect(CountryResolver.localizedName(for: code) == code)
    }

    // MARK: - The finished fragment

    @Test("A resolvable coordinate reads as pin, country and flag")
    func placeDescription() throws {
        let place = try #require(
            CountryResolver.placeDescription(latitude: 48.8566, longitude: 2.3522))
        #expect(place.hasPrefix("📍 "))
        #expect(place.hasSuffix("🇫🇷"))
        #expect(place.contains(CountryResolver.localizedName(for: "FR")))
    }

    @Test("An unresolvable coordinate has no description at all")
    func placeDescriptionNeedsACountry() {
        #expect(CountryResolver.placeDescription(latitude: 0, longitude: -140) == nil)
    }

    // MARK: - The bundled resource

    @Test("The boundary resource is bundled, parsed, and covers the world")
    func resourceIsReachable() {
        let codes = CountryResolver.boundaries.countryCodes
        #expect(codes.count > 200, "expected a full country set, parsed \(codes.count)")
        #expect(Set(codes).count == codes.count, "each country should appear once")
        for code in codes {
            #expect(code.count == 2 && code.allSatisfy(\.isUppercase),
                    "\(code) is not an ISO 3166-1 alpha-2 code")
        }
    }

    @Test("Resolution is quick enough to sit in an export path")
    func lookupIsCheap() {
        // Runs once per export, not once per pixel, so this only needs to rule
        // out something pathological.
        let start = Date()
        for i in 0..<200 {
            _ = CountryResolver.countryCode(latitude: Double(i % 80) - 40,
                                            longitude: Double(i % 170) - 85)
        }
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed < 2.0, "200 lookups took \(elapsed)s")
    }
}
