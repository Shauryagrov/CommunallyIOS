//
//  SeekerDiscoverySettings.swift
//  Communally
//
//  Persisted discovery radius for seekers (map + list). Hirer posting still uses GeoAppConstants.
//

import Combine
import CoreLocation
import Foundation

enum SeekerDiscoverySettings {
    fileprivate static let milesKey = "seekerDiscoveryRadiusMiles"
    static let minMiles: Double = 1
    static let maxMiles: Double = 5
    static let defaultMiles: Double = 5

    /// Clamped miles (1…5), default 5 if unset.
    static var radiusMiles: Double {
        get {
            let stored = UserDefaults.standard.object(forKey: milesKey) as? Double
                ?? UserDefaults.standard.double(forKey: milesKey)
            if stored <= 0 { return defaultMiles }
            return min(maxMiles, max(minMiles, stored))
        }
        set {
            UserDefaults.standard.set(min(maxMiles, max(minMiles, newValue)), forKey: milesKey)
        }
    }

    static var radiusMeters: CLLocationDistance {
        radiusMiles * 1609.34
    }
}

/// Shared so the map slider and Opportunities list stay in sync.
final class SeekerDiscoveryRadiusStore: ObservableObject {
    static let shared = SeekerDiscoveryRadiusStore()

    @Published var miles: Double

    private init() {
        miles = SeekerDiscoverySettings.radiusMiles
    }

    var radiusMeters: CLLocationDistance {
        miles * 1609.34
    }

    func setMilesFromSlider(_ value: Double) {
        let clamped = min(SeekerDiscoverySettings.maxMiles, max(SeekerDiscoverySettings.minMiles, value))
        miles = clamped
        SeekerDiscoverySettings.radiusMiles = clamped
    }

    func refreshFromStorage() {
        miles = SeekerDiscoverySettings.radiusMiles
    }
}
