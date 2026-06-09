//
//  MapPresenceService.swift
//  Communally
//
//  Coordinates the "show me on the map" feature end-to-end:
//
//    1. Computing the smart default for `appearOnMap` based on age +
//       parental approval (Apple-safe).
//    2. Recomputing the user's blurred map coordinate when they opt
//       in or when the 24h refresh window expires.
//    3. Persisting `appearOnMap`, `mapLatitude`, `mapLongitude`,
//       `mapLocationUpdatedAt` to Firestore + the local cache.
//    4. Fetching nearby opted-in users for the map view.
//
//  Real coordinate lookup priority:
//    a) Hirers → `verifiedHomeLatitude/Longitude` (the verified home
//       they entered during onboarding).
//    b) Seekers → `location` (the optional onboarding spot) OR a live
//       `LocationManager` reading.
//    c) Nothing usable → user can't appear, toggle stays off.
//

import Foundation
import CoreLocation
import FirebaseCore
import FirebaseFirestore

@MainActor
final class MapPresenceService: ObservableObject {
    static let shared = MapPresenceService()
    private init() {}

    private var db: Firestore? {
        guard FirebaseApp.app() != nil else { return nil }
        return Firestore.firestore()
    }

    // MARK: - Defaults

    /// Apple-safe default for `appearOnMap` on a new account.
    ///   - 18+ adults                    → ON  (discoverable by default)
    ///   - 13-17 teens (no parent yet)   → OFF (privacy-first)
    ///   - 13-17 teens with parent flag  → ON
    ///
    /// This is read by AuthenticationManager when bootstrapping a new
    /// User doc and by UserProfileView when explaining the toggle copy.
    static func defaultAppearOnMap(for user: User) -> Bool {
        let age = user.resolvedAge
        if age >= 18 { return true }
        if age >= 13, user.isParentalApproved == true { return true }
        return false
    }

    // MARK: - Real coordinate lookup

    /// The privacy-internal "real" coordinate to blur. Never leaves
    /// the device unencrypted; only its blurred derivative is uploaded.
    func realCoordinate(for user: User) -> CLLocationCoordinate2D? {
        if let lat = user.verifiedHomeLatitude, let lon = user.verifiedHomeLongitude {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        if let loc = user.location {
            return CLLocationCoordinate2D(latitude: loc.latitude, longitude: loc.longitude)
        }
        if let live = LocationManager.shared.location?.coordinate {
            return live
        }
        return nil
    }

    // MARK: - Opt in / out

    /// Flips the user's `appearOnMap` flag and (if on) recomputes the
    /// blurred coordinate. Writes both fields to Firestore in one go.
    func setAppearOnMap(
        _ appear: Bool,
        for user: User,
        completion: ((Bool) -> Void)? = nil
    ) {
        guard let db = db else { completion?(false); return }

        if appear {
            // Need a real coord to blur; if missing, hand back false.
            guard let real = realCoordinate(for: user) else {
                completion?(false)
                return
            }
            let blurred = LocationBlurring.blur(
                realLatitude: real.latitude,
                realLongitude: real.longitude,
                seed: user.id + "-" + LocationBlurring.currentDayBucket()
            )
            let now = Date()
            let payload: [String: Any] = [
                "appearOnMap": true,
                "mapLatitude": blurred.latitude,
                "mapLongitude": blurred.longitude,
                "mapLocationUpdatedAt": Timestamp(date: now)
            ]
            db.collection("users").document(user.id).setData(payload, merge: true) { err in
                Task { @MainActor in completion?(err == nil) }
            }
        } else {
            // Turning off — strip the published coordinate so other
            // users immediately stop seeing this pin.
            let payload: [String: Any] = [
                "appearOnMap": false,
                "mapLatitude": FieldValue.delete(),
                "mapLongitude": FieldValue.delete(),
                "mapLocationUpdatedAt": FieldValue.delete()
            ]
            db.collection("users").document(user.id).setData(payload, merge: true) { err in
                Task { @MainActor in completion?(err == nil) }
            }
        }
    }

    /// Recomputes the blurred coordinate if the 24h window expired.
    /// Safe to call on every dashboard appearance.
    func refreshIfStale(for user: User) {
        guard user.appearOnMap == true,
              LocationBlurring.needsRefresh(user.mapLocationUpdatedAt)
        else { return }
        setAppearOnMap(true, for: user, completion: nil)
    }

    /// Called once after login/signup. If the user has never made a
    /// choice on the map toggle (`appearOnMap == nil`), apply the
    /// Apple-safe default:
    ///   - 18+ adult            → ON (publishes coord if available now).
    ///   - 13-17 teen no parent → OFF (privacy-first; toggle stays off
    ///                            until parent approves).
    /// Idempotent — no-op once the user has made an explicit choice.
    func ensureInitialAppearOnMap(for user: User) {
        guard user.appearOnMap == nil else { return }
        let shouldAppear = Self.defaultAppearOnMap(for: user)
        setAppearOnMap(shouldAppear, for: user, completion: nil)
    }

    // MARK: - Fetch nearby pins

    /// One-shot query of opted-in users within `radiusMeters` of
    /// `center`. Excludes the current user. Filtering is done
    /// client-side because Firestore can't do native geo range
    /// queries — fine at marketplace scale because we cap at 200.
    func fetchNearbyPins(
        center: CLLocationCoordinate2D,
        radiusMeters: Double,
        excludingUserId: String,
        completion: @escaping ([MapPin]) -> Void
    ) {
        guard let db = db else { completion([]); return }
        db.collection("users")
            .whereField("appearOnMap", isEqualTo: true)
            .limit(to: 200)
            .getDocuments { snap, _ in
                let centerLoc = CLLocation(latitude: center.latitude, longitude: center.longitude)
                let pins: [MapPin] = (snap?.documents ?? []).compactMap { doc in
                    let data = doc.data()
                    guard
                        let lat = data["mapLatitude"] as? Double,
                        let lon = data["mapLongitude"] as? Double,
                        doc.documentID != excludingUserId
                    else { return nil }
                    let here = CLLocation(latitude: lat, longitude: lon)
                    guard centerLoc.distance(from: here) <= radiusMeters else { return nil }
                    let roleRaw = (data["userType"] as? String) ?? "jobSeeker"
                    let name = (data["firstName"] as? String) ?? "Neighbor"
                    return MapPin(
                        userId: doc.documentID,
                        latitude: lat,
                        longitude: lon,
                        displayName: name,
                        role: roleRaw == "jobHirer" ? .hirer : .seeker
                    )
                }
                Task { @MainActor in completion(pins) }
            }
    }
}

/// Lightweight payload for one map pin. Doesn't carry the full User —
/// just enough to render the pin and route a tap to UserProfileView.
struct MapPin: Identifiable, Hashable {
    enum Role { case seeker, hirer }
    let userId: String
    let latitude: Double
    let longitude: Double
    let displayName: String
    let role: Role
    var id: String { userId }
}
