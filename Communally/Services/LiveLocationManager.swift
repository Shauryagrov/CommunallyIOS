//
//  LiveLocationManager.swift
//  Communally
//
//  Manages real-time location sharing between seeker and hirer during an active job.
//

import Foundation
import CoreLocation
import FirebaseCore
import FirebaseFirestore

enum SeekerJourneyStatus: String, Codable {
    case notStarted = "not_started"
    case onTheWay   = "on_the_way"
    case arrived    = "arrived"

    var displayText: String {
        switch self {
        case .notStarted: return "Getting ready"
        case .onTheWay:   return "On the way"
        case .arrived:    return "Job Start"
        }
    }

    var icon: String {
        switch self {
        case .notStarted: return "clock"
        case .onTheWay:   return "car.fill"
        case .arrived:    return "checkmark.circle.fill"
        }
    }
}

struct LiveLocationSnapshot {
    let coordinate: CLLocationCoordinate2D
    let updatedAt: Date
    let journeyStatus: SeekerJourneyStatus
}

class LiveLocationManager: NSObject, ObservableObject {
    static let shared = LiveLocationManager()

    @Published var seekerSnapshot: LiveLocationSnapshot?
    /// Mirror of the seeker's `journeyStatus` field independent of whether
    /// lat/lon are available. Hirer's "Mark as Complete" gate reads this so
    /// it works even if the seeker tapped Job Start before LocationManager
    /// had a recent fix (otherwise the snapshot would be nil and the gate
    /// would never open).
    @Published var seekerJourneyStatus: SeekerJourneyStatus?

    private var db: Firestore? { FirebaseApp.app() != nil ? Firestore.firestore() : nil }
    private var sharingTimer: Timer?
    private var seekerListener: ListenerRegistration?
    private var currentUserId: String?
    /// IDs the seeker has explicitly allowed to read their live coordinates
    /// (typically just the hirer of the current accepted job). Persisted on
    /// every write as `allowedViewers: [String]` so the Firestore rule on
    /// `liveLocations/{userId}` can deny reads from anyone outside this list.
    /// Empty array = visible only to the seeker themselves.
    private var allowedViewerIds: [String] = []

    private override init() { super.init() }

    // MARK: - Seeker: start broadcasting location
    func startSharing(userId: String, status: SeekerJourneyStatus = .onTheWay, allowedViewerId: String? = nil) {
        stopSharing()
        currentUserId = userId
        if let viewerId = allowedViewerId, !viewerId.isEmpty {
            allowedViewerIds = [viewerId]
        }
        writeLocation(userId: userId, status: status)
        sharingTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.writeLocation(userId: userId, status: status)
        }
    }

    func updateJourneyStatus(_ status: SeekerJourneyStatus, userId: String, allowedViewerId: String? = nil) {
        guard let db = db else { return }
        // Persist (or refresh) the allow-list of hirer IDs that may read this
        // seeker's live location doc. Even if the seeker calls this without
        // an `allowedViewerId` (e.g., from a code path that doesn't have it
        // handy), we keep whatever was set previously rather than wiping it,
        // so the hirer's existing listener doesn't suddenly start failing on
        // the next status flip.
        if let viewerId = allowedViewerId, !viewerId.isEmpty, !allowedViewerIds.contains(viewerId) {
            allowedViewerIds.append(viewerId)
        }

        // setData(merge: true) instead of updateData so we create the doc if
        // it doesn't exist yet — previously this silently failed when the
        // seeker tapped Job Start without ever having tapped "On the way"
        // first (we removed the "On the way" button, so startSharing was
        // never called → no doc → updateData no-op → hirer's listener got
        // nil → "Mark as Complete" stayed disabled forever on the hirer).
        var payload: [String: Any] = [
            "journeyStatus": status.rawValue,
            "updatedAt": Timestamp(date: Date()),
            "allowedViewers": allowedViewerIds
        ]
        if let location = LocationManager.shared.location {
            payload["latitude"] = location.coordinate.latitude
            payload["longitude"] = location.coordinate.longitude
        }
        db.collection("liveLocations").document(userId).setData(payload, merge: true)
        currentUserId = userId
        if status == .arrived {
            // Stop frequent updates once arrived — no need to broadcast while working
            sharingTimer?.invalidate()
            sharingTimer = nil
        }
    }

    func stopSharing() {
        sharingTimer?.invalidate()
        sharingTimer = nil
        if let uid = currentUserId {
            db?.collection("liveLocations").document(uid).delete()
        }
        currentUserId = nil
        allowedViewerIds = []
    }

    // MARK: - Hirer: listen to seeker's location
    func startListening(seekerId: String) {
        stopListening()
        seekerListener = db?.collection("liveLocations").document(seekerId)
            .addSnapshotListener { [weak self] snap, _ in
                guard let data = snap?.data() else {
                    DispatchQueue.main.async {
                        self?.seekerSnapshot = nil
                        self?.seekerJourneyStatus = nil
                    }
                    return
                }
                let status = SeekerJourneyStatus(rawValue: data["journeyStatus"] as? String ?? "")
                let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? Date()

                // Always publish the journey status (used for the Mark as
                // Complete gate). Only publish a `seekerSnapshot` when we
                // also have valid coordinates — map / distance / ETA UI
                // depends on those.
                DispatchQueue.main.async {
                    self?.seekerJourneyStatus = status
                    if let lat = data["latitude"] as? Double,
                       let lon = data["longitude"] as? Double {
                        self?.seekerSnapshot = LiveLocationSnapshot(
                            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                            updatedAt: updatedAt,
                            journeyStatus: status ?? .onTheWay
                        )
                    } else {
                        self?.seekerSnapshot = nil
                    }
                }
            }
    }

    func stopListening() {
        seekerListener?.remove()
        seekerListener = nil
        seekerSnapshot = nil
        seekerJourneyStatus = nil
    }

    /// One-shot read of the caller's own `liveLocations/{userId}` doc — used
    /// by the seeker's `ActiveJobView.onAppear` to rehydrate `journeyStatus`
    /// after a sheet re-mount (their local @State otherwise forgets that
    /// they've already tapped Job Start, and the button reappears live).
    func fetchOwnJourneyStatus(userId: String, completion: @escaping (SeekerJourneyStatus?) -> Void) {
        guard let db = db else { completion(nil); return }
        db.collection("liveLocations").document(userId).getDocument { snap, _ in
            let raw = snap?.data()?["journeyStatus"] as? String
            let status = raw.flatMap(SeekerJourneyStatus.init(rawValue:))
            DispatchQueue.main.async { completion(status) }
        }
    }

    // MARK: - Private
    private func writeLocation(userId: String, status: SeekerJourneyStatus) {
        guard let location = LocationManager.shared.location, let db = db else { return }
        db.collection("liveLocations").document(userId).setData([
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "updatedAt": Timestamp(date: Date()),
            "journeyStatus": status.rawValue,
            "allowedViewers": allowedViewerIds
        ]) { error in
            if let error = error {
                print("❌ writeLocation failed for \(userId): \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Helpers

extension CLLocationCoordinate2D {
    func distanceMiles(to other: CLLocationCoordinate2D) -> Double {
        let from = CLLocation(latitude: latitude, longitude: longitude)
        let to   = CLLocation(latitude: other.latitude, longitude: other.longitude)
        return from.distance(from: to) / 1609.34
    }

    /// Rough driving ETA in minutes (assumes 25 mph avg for local gigs).
    func etaMinutes(to other: CLLocationCoordinate2D) -> Int {
        let miles = distanceMiles(to: other)
        return max(1, Int(miles / 25.0 * 60))
    }
}
