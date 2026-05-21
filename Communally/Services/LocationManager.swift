//
//  LocationManager.swift
//  Communally
//
//  Created by Madhur Grover on 10/2/25.
//

import Foundation
import CoreLocation
import MapKit

/// A pickable city used by the manual-location browse fallback. These are
/// hardcoded coordinates of major US metros — good enough for v1, where the
/// app is US-only and the city set serves "I'm visiting / curious / haven't
/// turned on location" users. Coordinates are city centers (not centroids,
/// not airports) so radius filtering produces sensible results.
struct ManualBrowseCity: Identifiable, Hashable {
    let id: String
    let displayName: String
    let latitude: Double
    let longitude: Double

    static let popularUSCities: [ManualBrowseCity] = [
        .init(id: "nyc",    displayName: "New York, NY",       latitude: 40.7128,  longitude: -74.0060),
        .init(id: "la",     displayName: "Los Angeles, CA",    latitude: 34.0522,  longitude: -118.2437),
        .init(id: "chi",    displayName: "Chicago, IL",        latitude: 41.8781,  longitude: -87.6298),
        .init(id: "hou",    displayName: "Houston, TX",        latitude: 29.7604,  longitude: -95.3698),
        .init(id: "phx",    displayName: "Phoenix, AZ",        latitude: 33.4484,  longitude: -112.0740),
        .init(id: "phl",    displayName: "Philadelphia, PA",   latitude: 39.9526,  longitude: -75.1652),
        .init(id: "sa",     displayName: "San Antonio, TX",    latitude: 29.4241,  longitude: -98.4936),
        .init(id: "sd",     displayName: "San Diego, CA",      latitude: 32.7157,  longitude: -117.1611),
        .init(id: "dal",    displayName: "Dallas, TX",         latitude: 32.7767,  longitude: -96.7970),
        .init(id: "sj",     displayName: "San Jose, CA",       latitude: 37.3382,  longitude: -121.8863),
        .init(id: "aus",    displayName: "Austin, TX",         latitude: 30.2672,  longitude: -97.7431),
        .init(id: "jax",    displayName: "Jacksonville, FL",   latitude: 30.3322,  longitude: -81.6557),
        .init(id: "ftw",    displayName: "Fort Worth, TX",     latitude: 32.7555,  longitude: -97.3308),
        .init(id: "col",    displayName: "Columbus, OH",       latitude: 39.9612,  longitude: -82.9988),
        .init(id: "ind",    displayName: "Indianapolis, IN",   latitude: 39.7684,  longitude: -86.1581),
        .init(id: "char",   displayName: "Charlotte, NC",      latitude: 35.2271,  longitude: -80.8431),
        .init(id: "sf",     displayName: "San Francisco, CA",  latitude: 37.7749,  longitude: -122.4194),
        .init(id: "sea",    displayName: "Seattle, WA",        latitude: 47.6062,  longitude: -122.3321),
        .init(id: "den",    displayName: "Denver, CO",         latitude: 39.7392,  longitude: -104.9903),
        .init(id: "dc",     displayName: "Washington, DC",     latitude: 38.9072,  longitude: -77.0369),
        .init(id: "bos",    displayName: "Boston, MA",         latitude: 42.3601,  longitude: -71.0589),
        .init(id: "nash",   displayName: "Nashville, TN",      latitude: 36.1627,  longitude: -86.7816),
        .init(id: "okc",    displayName: "Oklahoma City, OK",  latitude: 35.4676,  longitude: -97.5164),
        .init(id: "lv",     displayName: "Las Vegas, NV",      latitude: 36.1699,  longitude: -115.1398),
        .init(id: "por",    displayName: "Portland, OR",       latitude: 45.5152,  longitude: -122.6784),
        .init(id: "mem",    displayName: "Memphis, TN",        latitude: 35.1495,  longitude: -90.0490),
        .init(id: "lou",    displayName: "Louisville, KY",     latitude: 38.2527,  longitude: -85.7585),
        .init(id: "bal",    displayName: "Baltimore, MD",      latitude: 39.2904,  longitude: -76.6122),
        .init(id: "mil",    displayName: "Milwaukee, WI",      latitude: 43.0389,  longitude: -87.9065),
        .init(id: "abq",    displayName: "Albuquerque, NM",    latitude: 35.0844,  longitude: -106.6504),
        .init(id: "tuc",    displayName: "Tucson, AZ",         latitude: 32.2226,  longitude: -110.9747),
        .init(id: "fres",   displayName: "Fresno, CA",         latitude: 36.7378,  longitude: -119.7871),
        .init(id: "sac",    displayName: "Sacramento, CA",     latitude: 38.5816,  longitude: -121.4944),
        .init(id: "atl",    displayName: "Atlanta, GA",        latitude: 33.7490,  longitude: -84.3880),
        .init(id: "mia",    displayName: "Miami, FL",          latitude: 25.7617,  longitude: -80.1918),
        .init(id: "min",    displayName: "Minneapolis, MN",    latitude: 44.9778,  longitude: -93.2650),
        .init(id: "tul",    displayName: "Tulsa, OK",          latitude: 36.1540,  longitude: -95.9928),
        .init(id: "cle",    displayName: "Cleveland, OH",      latitude: 41.4993,  longitude: -81.6944),
        .init(id: "kc",     displayName: "Kansas City, MO",    latitude: 39.0997,  longitude: -94.5786),
        .init(id: "rale",   displayName: "Raleigh, NC",        latitude: 35.7796,  longitude: -78.6382),
    ]
}

class LocationManager: NSObject, ObservableObject {
    static let shared = LocationManager()
    
    private let locationManager = CLLocationManager()
    @Published var location: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isLocationEnabled = false

    /// User-picked fallback "browse from this city" location, used when
    /// CoreLocation permission isn't granted. Apple Guideline 5.1.5 requires
    /// the app to be functional without location services — this is how we
    /// honor that without crippling the experience: if the user chose
    /// "Browse San Francisco" from the city picker, we treat that as the
    /// effective center for map zoom + radius filtering. Persists in
    /// UserDefaults so the choice survives app relaunches.
    @Published var manualLocation: CLLocation?

    /// Human-readable label for `manualLocation`, e.g. "San Francisco, CA".
    /// Shown in the map header pill as "Searching near: San Francisco, CA"
    /// so the user knows the radius is centered on their picked city, not
    /// their real position.
    @Published var manualLocationLabel: String?

    /// The location everything-on-screen should treat as "where you are."
    /// Prefers a real CoreLocation fix; falls back to the user-picked
    /// manual city if permission was denied or never granted.
    var effectiveLocation: CLLocation? { location ?? manualLocation }

    /// Same idea but exposing the label for header chrome.
    var effectiveLocationLabel: String? {
        // Real GPS doesn't carry a label, so only return a label when the
        // user explicitly picked a city. Real-GPS UI uses reverse-geocode
        // results elsewhere (the SeekerLocationSubtitleModel).
        if location != nil { return nil }
        return manualLocationLabel
    }

    /// True when permission is denied/restricted/notDetermined AND the user
    /// hasn't picked a manual city yet. This is the empty-state where we
    /// want to show "Turn on location or pick a city to browse" CTAs.
    var needsLocationOrManualPick: Bool {
        let granted = authorizationStatus == .authorizedWhenInUse
                   || authorizationStatus == .authorizedAlways
        return !granted && manualLocation == nil
    }

    private var permissionCompletion: ((Bool) -> Void)?
    private var isInitialized = false

    /// Keys for persisting the manual city pick across app launches.
    private enum DefaultsKey {
        static let manualLat = "communally.manualLocation.lat"
        static let manualLon = "communally.manualLocation.lon"
        static let manualLabel = "communally.manualLocation.label"
    }

    override init() {
        super.init()
        setupLocationManager()
        restoreManualLocationIfAny()
    }
    
    private func setupLocationManager() {
        guard !isInitialized else { return }

        locationManager.delegate = self
        // "HundredMeters" is plenty for a "jobs near me" map — kBest spams
        // updates from GPS jitter while standing still, which made the map
        // re-render dozens of times a second and look like it was blinking.
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        // Only deliver an update when the user has actually moved 25+ meters.
        locationManager.distanceFilter = 25
        authorizationStatus = locationManager.authorizationStatus
        isInitialized = true

        print("✅ LocationManager initialized")
    }
    
    func requestLocationPermission(completion: @escaping (Bool) -> Void) {
        print("📍 LocationManager: requestLocationPermission called")
        print("📍 LocationManager: Current authorizationStatus: \(authorizationStatus.rawValue)")
        
        permissionCompletion = completion
        
        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            print("📍 LocationManager: Already authorized, calling completion(true)")
            completion(true)
        case .denied, .restricted:
            print("📍 LocationManager: Permission denied/restricted, calling completion(false)")
            completion(false)
        case .notDetermined:
            print("📍 LocationManager: Permission not determined, requesting authorization")
            locationManager.requestWhenInUseAuthorization()
        @unknown default:
            print("📍 LocationManager: Unknown status, calling completion(false)")
            completion(false)
        }
    }
    
    func startLocationUpdates() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            requestLocationPermission { _ in }
            return
        }
        
        locationManager.startUpdatingLocation()
        isLocationEnabled = true
    }
    
    func stopLocationUpdates() {
        locationManager.stopUpdatingLocation()
        isLocationEnabled = false
    }
    
    func getCurrentLocation() -> CLLocation? {
        return location
    }
    
    func requestLocationPermission() {
        requestLocationPermission { _ in }
    }
    
    func requestLocationPermissionWithoutCompletion() {
        print("📍 LocationManager: requestLocationPermissionWithoutCompletion called - current status: \(authorizationStatus.rawValue)")
        switch authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            print("📍 LocationManager: Already authorized, requesting location")
            locationManager.requestLocation()
        case .denied, .restricted:
            print("📍 LocationManager: Permission denied/restricted")
            break
        case .notDetermined:
            print("📍 LocationManager: Requesting authorization")
            locationManager.requestWhenInUseAuthorization()
        @unknown default:
            print("📍 LocationManager: Unknown status")
            break
        }
    }
    
    func requestLocation() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            requestLocationPermission { granted in
                if granted {
                    self.locationManager.requestLocation()
                }
            }
            return
        }
        locationManager.requestLocation()
    }
    
    // MARK: - Manual location override (no-GPS fallback)

    /// Pick a city to browse from when CoreLocation permission isn't
    /// granted. Updating `manualLocation` triggers @Published republish,
    /// which causes `mapOpportunities` / `visibleOpportunities` to re-run
    /// their radius filter centered on the new coordinate.
    func setManualLocation(city: ManualBrowseCity) {
        let coord = CLLocation(latitude: city.latitude, longitude: city.longitude)
        manualLocation = coord
        manualLocationLabel = city.displayName
        UserDefaults.standard.set(city.latitude, forKey: DefaultsKey.manualLat)
        UserDefaults.standard.set(city.longitude, forKey: DefaultsKey.manualLon)
        UserDefaults.standard.set(city.displayName, forKey: DefaultsKey.manualLabel)
        Log.debug("📍 Manual location set to: \(city.displayName)")
    }

    /// Drop the manual override (e.g., user turned on real location, or
    /// hit "Reset" in the city picker). Real CLLocationManager updates
    /// take over from here.
    func clearManualLocation() {
        manualLocation = nil
        manualLocationLabel = nil
        UserDefaults.standard.removeObject(forKey: DefaultsKey.manualLat)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.manualLon)
        UserDefaults.standard.removeObject(forKey: DefaultsKey.manualLabel)
        Log.debug("📍 Manual location cleared")
    }

    private func restoreManualLocationIfAny() {
        let lat = UserDefaults.standard.double(forKey: DefaultsKey.manualLat)
        let lon = UserDefaults.standard.double(forKey: DefaultsKey.manualLon)
        let label = UserDefaults.standard.string(forKey: DefaultsKey.manualLabel)
        // `double(forKey:)` returns 0.0 when absent, which is a valid
        // coordinate (Null Island) — so require BOTH the label and a
        // non-zero coord to consider this a real saved pick.
        guard let label, lat != 0, lon != 0 else { return }
        manualLocation = CLLocation(latitude: lat, longitude: lon)
        manualLocationLabel = label
        Log.debug("📍 Restored manual location: \(label)")
    }

    func searchNearbyOpportunities(within radius: CLLocationDistance = 5000) -> [JobOpportunity] {
        guard let currentLocation = location else { return [] }
        
        // This would typically make an API call to your backend
        // For now, we'll return mock data based on proximity
        let mockOpportunities = [
            JobOpportunity(
                id: "1",
                title: "Retail Assistant",
                description: "Help customers and maintain store appearance",
                hirerId: "hirer1",
                location: Location(latitude: currentLocation.coordinate.latitude + 0.001, longitude: currentLocation.coordinate.longitude + 0.001, address: "Nearby Store"),
                isVolunteer: false,
                skillsRequired: ["Customer Service", "Retail"],
                createdAt: Date(),
                isActive: true
            ),
            JobOpportunity(
                id: "2",
                title: "Community Garden Volunteer",
                description: "Help maintain our community garden",
                hirerId: "hirer2",
                location: Location(latitude: currentLocation.coordinate.latitude - 0.002, longitude: currentLocation.coordinate.longitude + 0.001, address: "Community Center"),
                isVolunteer: true,
                skillsRequired: ["Gardening"],
                createdAt: Date(),
                isActive: true
            ),
            JobOpportunity(
                id: "3",
                title: "Pet Walker",
                description: "Walk dogs for busy pet owners",
                hirerId: "hirer3",
                location: Location(latitude: currentLocation.coordinate.latitude + 0.003, longitude: currentLocation.coordinate.longitude - 0.001, address: "Pet Services"),
                isVolunteer: false,
                skillsRequired: ["Pet Care"],
                createdAt: Date(),
                isActive: true
            )
        ]
        
        return mockOpportunities.filter { opportunity in
            let opportunityLocation = CLLocation(
                latitude: opportunity.location.latitude,
                longitude: opportunity.location.longitude
            )
            return currentLocation.distance(from: opportunityLocation) <= radius
        }
    }
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let newLocation = locations.last else {
            print("📍 LocationManager: No valid location in update")
            return
        }
        // Belt-and-suspenders against GPS jitter: even with distanceFilter set
        // on the manager, paranoia helps. Drop updates that move <15m from the
        // last published one so SwiftUI views aren't redrawn pointlessly.
        if let previous = self.location,
           previous.distance(from: newLocation) < 15 {
            return
        }
        Log.debug("📍 LocationManager: Received location update - lat: \(newLocation.coordinate.latitude), lon: \(newLocation.coordinate.longitude)")
        self.location = newLocation
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        print("📍 LocationManager: didChangeAuthorization - status: \(status.rawValue)")
        authorizationStatus = status
        
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            print("📍 LocationManager: Permission granted, starting location updates")
            startLocationUpdates()
            // Also request a one-time location update
            manager.requestLocation()
            permissionCompletion?(true)
        case .denied, .restricted:
            print("📍 LocationManager: Permission denied/restricted")
            isLocationEnabled = false
            permissionCompletion?(false)
        case .notDetermined:
            print("📍 LocationManager: Permission still not determined")
            // Don't call completion here, wait for user decision
            break
        @unknown default:
            print("📍 LocationManager: Unknown authorization status")
            permissionCompletion?(false)
        }
        
        permissionCompletion = nil
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location manager failed with error: \(error.localizedDescription)")
    }
}
