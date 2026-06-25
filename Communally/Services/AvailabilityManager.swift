//
//  AvailabilityManager.swift
//  Communally
//
//  Manages seeker-posted availabilities — the marketplace mirror of
//  OpportunityManager. Same auth-driven listener pattern: attach the
//  Firestore snapshot only after Firebase Auth confirms a user, detach
//  on sign-out, clear on account deletion.
//

import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore

class AvailabilityManager: ObservableObject {
    static let shared = AvailabilityManager()

    @Published var availabilities: [Availability] = []

    private var db: Firestore? {
        guard FirebaseApp.app() != nil else { return nil }
        return Firestore.firestore()
    }
    private var listener: ListenerRegistration?
    private var authHandle: AuthStateDidChangeListenerHandle?

    private init() {}

    deinit {
        listener?.remove()
        if let handle = authHandle { Auth.auth().removeStateDidChangeListener(handle) }
    }

    // MARK: - Lifecycle

    func initialize() {
        guard authHandle == nil else { return }
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self = self else { return }
            if user != nil {
                self.startListening()
            } else {
                self.listener?.remove()
                self.listener = nil
                DispatchQueue.main.async { self.availabilities = [] }
            }
        }
    }

    func clearLocalState() {
        listener?.remove()
        listener = nil
        DispatchQueue.main.async { self.availabilities = [] }
    }

    private func startListening() {
        guard let db = db else {
            print("⚠️ AvailabilityManager: Firebase not configured, skipping listener")
            return
        }
        listener?.remove()
        print("🔥 Starting Firestore listener for availabilities")
        listener = db.collection("availabilities")
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                if let error = error {
                    print("❌ Error fetching availabilities: \(error.localizedDescription)")
                    return
                }
                let fetched: [Availability] = snapshot?.documents.compactMap { doc in
                    do {
                        return try doc.data(as: Availability.self)
                    } catch {
                        print("⚠️ Failed to decode availability \(doc.documentID): \(error)")
                        return nil
                    }
                } ?? []
                DispatchQueue.main.async {
                    self.availabilities = fetched
                }
            }
    }

    // MARK: - Post

    func postAvailability(
        seekerId: String,
        seekerName: String,
        seekerImageData: Data?,
        location: Location,
        locationName: String,
        categories: [String],
        hourlyRate: Int,
        scheduledDate: Date,
        scheduledTime: String,
        scheduledEndTime: String,
        note: String?,
        completion: ((Error?) -> Void)? = nil
    ) {
        // Mirror the OpportunityManager guard: Firestore rules require
        // Auth.currentUser.uid == seekerId. In Release builds the custom
        // token mint occasionally drops; without this check the local cache
        // would accept the write and the next snapshot would silently drop it.
        let firebaseUid = Auth.auth().currentUser?.uid
        guard let firebaseUid, firebaseUid == seekerId else {
            let detail = firebaseUid == nil
                ? "Your secure session expired. Sign out and sign back in, then try again."
                : "Your account didn't match the secure session. Sign out and sign back in, then try again."
            let err = NSError(
                domain: "AvailabilityManager",
                code: -1001,
                userInfo: [NSLocalizedDescriptionKey: detail]
            )
            DispatchQueue.main.async { completion?(err) }
            return
        }

        guard let db = db else {
            let err = NSError(
                domain: "AvailabilityManager",
                code: -1002,
                userInfo: [NSLocalizedDescriptionKey: "Firebase isn't ready. Restart the app and try again."]
            )
            DispatchQueue.main.async { completion?(err) }
            return
        }

        let id = UUID().uuidString
        let availability = Availability(
            id: id,
            seekerId: seekerId,
            seekerName: seekerName,
            seekerImageData: seekerImageData,
            location: location,
            locationName: locationName,
            categories: categories,
            hourlyRate: hourlyRate,
            scheduledDate: scheduledDate,
            scheduledTime: scheduledTime,
            scheduledEndTime: scheduledEndTime,
            note: note,
            createdAt: Date(),
            isActive: true,
            status: .open
        )

        do {
            try db.collection("availabilities").document(id).setData(from: availability) { error in
                if let error = error {
                    print("❌ Error posting availability: \(error.localizedDescription)")
                    DispatchQueue.main.async { completion?(error) }
                    return
                }
                print("✅ Posted availability: \(categories.joined(separator: ","))")
                DispatchQueue.main.async { completion?(nil) }
            }
        } catch {
            DispatchQueue.main.async { completion?(error) }
        }
    }

    // MARK: - Cancel

    func cancelAvailability(_ id: String, completion: ((Error?) -> Void)? = nil) {
        guard let db = db else { completion?(nil); return }
        db.collection("availabilities").document(id).updateData([
            "status": AvailabilityStatus.cancelled.rawValue,
            "isActive": false
        ]) { error in
            DispatchQueue.main.async { completion?(error) }
        }
    }
}
