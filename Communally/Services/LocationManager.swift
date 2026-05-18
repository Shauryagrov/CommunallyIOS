//
//  LocationManager.swift
//  Communally
//
//  Created by Madhur Grover on 10/2/25.
//

import Foundation
import CoreLocation
import MapKit

class LocationManager: NSObject, ObservableObject {
    static let shared = LocationManager()
    
    private let locationManager = CLLocationManager()
    @Published var location: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isLocationEnabled = false
    
    private var permissionCompletion: ((Bool) -> Void)?
    private var isInitialized = false
    
    override init() {
        super.init()
        setupLocationManager()
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
