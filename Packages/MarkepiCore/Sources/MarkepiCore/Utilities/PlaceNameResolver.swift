import CoreLocation
import Foundation

/// City and landmark names for the caption's Landmark and City fields.
///
/// The country is resolved offline (`CountryResolver`); anything finer needs
/// Apple's reverse geocoder, so this runs only when the user ticked Landmark or
/// City. The names ride in the *caption* metadata under `landmarkKey` and
/// `cityKey` — never in the exported file's metadata — and the caption falls
/// back to the country whenever they are missing.
///
/// The landmark wording is TripPhotoShare's `PlaceNames.format`: the area of
/// interest the photo sits in, else its neighbourhood, else the placemark name.
public actor PlaceNameResolver {
    public static let shared = PlaceNameResolver()

    /// Caption-metadata keys the resolved names are stored under.
    public static let landmarkKey = "_PlaceLandmark"
    public static let cityKey = "_PlaceCity"

    public struct Names: Sendable, Equatable {
        public var landmark: String?
        public var city: String?

        /// Writes the names into caption metadata.
        public func write(into metadata: inout [String: Any]) {
            metadata[PlaceNameResolver.landmarkKey] = landmark
            metadata[PlaceNameResolver.cityKey] = city
        }
    }

    private var names: [String: Names] = [:]
    private var failures: [String: Date] = [:]

    /// The names `frame` asks for at the caption metadata's coordinate, or nil
    /// when it ticks neither Landmark nor City, or the lookup fails.
    ///
    /// Takes the coordinate, not the metadata dictionary, so actor callers do
    /// not send a non-Sendable dictionary across the await.
    static func names(for frame: WhiteFrameConfig?,
                      at coordinate: (latitude: Double, longitude: Double)?) async -> Names? {
        guard let frame, frame.isEnabled, frame.metadataTextEnabled,
              frame.captionFields.contains(.landmark) || frame.captionFields.contains(.city),
              let coordinate else { return nil }
        return await shared.names(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    /// The cached names for a ~100 m cell, else one geocoder lookup.
    ///
    /// ponytail: in-memory cache with a 30 s retry after a failure; persist it
    /// if repeat lookups across launches ever matter.
    func names(latitude: Double, longitude: Double) async -> Names? {
        let key = String(format: "%.3f,%.3f", latitude, longitude)
        if let cached = names[key] { return cached }
        if let failed = failures[key], Date().timeIntervalSince(failed) < 30 { return nil }
        guard let found = await Self.lookup(CLLocation(latitude: latitude, longitude: longitude)) else {
            failures[key] = Date()
            return nil
        }
        names[key] = found
        return found
    }

    /// One reverse-geocode, abandoned after four seconds so a slow network
    /// never stalls a preview or an export.
    private static func lookup(_ location: CLLocation) async -> Names? {
        let geocoder = CLGeocoder()
        nonisolated(unsafe) let cancellable = geocoder
        let timeout = Task {
            try await Task.sleep(for: .seconds(4))
            cancellable.cancelGeocode()
        }
        defer { timeout.cancel() }
        guard let placemark = try? await geocoder.reverseGeocodeLocation(location).first else { return nil }
        return names(from: placemark)
    }

    static func names(from placemark: CLPlacemark) -> Names {
        let city = placemark.locality ?? placemark.subAdministrativeArea ?? placemark.administrativeArea
        let landmark = placemark.areasOfInterest?.first ?? placemark.subLocality ?? placemark.name
        return Names(landmark: landmark == city ? nil : landmark, city: city)
    }
}
