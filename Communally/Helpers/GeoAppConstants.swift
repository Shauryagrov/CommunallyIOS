//
//  GeoAppConstants.swift
//  Communally
//
//  US-only map bounds and 5-mile discovery radius (hirers / seekers).
//

import CoreLocation
import MapKit

/// Minimum ages (aligned with Terms / onboarding).
enum AppAgeRequirements {
    /// COPPA hard floor. US federal law prohibits collecting personal
    /// information from children under 13 without verified parental
    /// consent — which we don't do — so we reject under-13s outright at
    /// signup with an explicit alert + sign-out. Never lower this below 13.
    static let coppaMinimumAge = 13
    /// Job seekers and general account use.
    static let minimumUserAge = 15
    /// Posting paid/volunteer opportunities (hirers).
    static let minimumHirerAge = 18
}

enum GeoAppConstants {
    /// Jobs and discovery use a 5-mile radius from hirer home (posting) or seeker location (map/list).
    static let discoveryMiles: Double = 5
    static var discoveryRadiusMeters: CLLocationDistance { discoveryMiles * 1609.34 }

    // Continental US bounding box (approximate).
    private static let usMinLat = 24.396308
    private static let usMaxLat = 49.384358
    private static let usMinLon = -124.848974
    private static let usMaxLon = -66.885444

    static func isCoordinateInUS(_ c: CLLocationCoordinate2D) -> Bool {
        c.latitude >= usMinLat && c.latitude <= usMaxLat
            && c.longitude >= usMinLon && c.longitude <= usMaxLon
    }

    static func isLocationInUS(latitude: Double, longitude: Double) -> Bool {
        isCoordinateInUS(CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
    }

    static var usMapCenter: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: 39.8283, longitude: -98.5795)
    }

    static var usMapSpan: MKCoordinateSpan {
        MKCoordinateSpan(latitudeDelta: 24, longitudeDelta: 38)
    }

    static func distanceMeters(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: from.latitude, longitude: from.longitude)
            .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
    }
}
