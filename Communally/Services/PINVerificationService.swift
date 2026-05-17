//
//  PINVerificationService.swift
//  Communally
//
//  PIN verification system for job authentication (synced via Firestore)
//

import Foundation
import SwiftUI
import FirebaseFirestore
import FirebaseCore

// MARK: - PIN Verification Types

enum PINVerificationType: String, Codable {
    case jobStart = "Job Start"
    case jobCompletion = "Job Completion"
    case payment = "Payment Confirmation"
    
    var icon: String {
        switch self {
        case .jobStart: return "play.circle.fill"
        case .jobCompletion: return "checkmark.circle.fill"
        case .payment: return "dollarsign.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .jobStart: return .green
        case .jobCompletion: return .blue
        case .payment: return .orange
        }
    }
    
    var firestoreKey: String {
        switch self {
        case .jobStart: return "jobStart"
        case .jobCompletion: return "jobCompletion"
        case .payment: return "payment"
        }
    }
}

enum PINStatus: String, Codable {
    case pending = "Pending"
    case verified = "Verified"
    case failed = "Failed"
    case expired = "Expired"
}

// MARK: - PIN Model

struct JobPIN: Identifiable, Codable {
    let id: String
    let jobId: String
    let pin: String
    let type: PINVerificationType
    let hirerId: String
    let workerId: String
    let createdAt: Date
    let expiresAt: Date
    var status: PINStatus
    var verifiedAt: Date?
    var attempts: Int
    
    var isExpired: Bool {
        return Date() > expiresAt
    }
    
    var remainingTime: TimeInterval {
        return expiresAt.timeIntervalSince(Date())
    }
    
    var formattedRemainingTime: String {
        let minutes = Int(remainingTime) / 60
        let seconds = Int(remainingTime) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var firestoreDocId: String {
        return "\(jobId)_\(type.firestoreKey)"
    }
    
    func toFirestoreData() -> [String: Any] {
        var data: [String: Any] = [
            "id": id,
            "jobId": jobId,
            "pin": pin,
            "type": type.rawValue,
            "hirerId": hirerId,
            "workerId": workerId,
            "createdAt": Timestamp(date: createdAt),
            "expiresAt": Timestamp(date: expiresAt),
            "status": status.rawValue,
            "attempts": attempts
        ]
        if let verifiedAt = verifiedAt {
            data["verifiedAt"] = Timestamp(date: verifiedAt)
        }
        return data
    }
    
    static func from(firestoreData data: [String: Any]) -> JobPIN? {
        guard let id = data["id"] as? String,
              let jobId = data["jobId"] as? String,
              let pin = data["pin"] as? String,
              let typeStr = data["type"] as? String,
              let type = PINVerificationType(rawValue: typeStr),
              let hirerId = data["hirerId"] as? String,
              let workerId = data["workerId"] as? String,
              let createdTs = data["createdAt"] as? Timestamp,
              let expiresTs = data["expiresAt"] as? Timestamp,
              let statusStr = data["status"] as? String,
              let status = PINStatus(rawValue: statusStr),
              let attempts = data["attempts"] as? Int else {
            return nil
        }
        
        let verifiedAt = (data["verifiedAt"] as? Timestamp)?.dateValue()
        
        return JobPIN(
            id: id,
            jobId: jobId,
            pin: pin,
            type: type,
            hirerId: hirerId,
            workerId: workerId,
            createdAt: createdTs.dateValue(),
            expiresAt: expiresTs.dateValue(),
            status: status,
            verifiedAt: verifiedAt,
            attempts: attempts
        )
    }
}

// MARK: - PIN Verification Service

class PINVerificationService: ObservableObject {
    static let shared = PINVerificationService()
    
    @Published var activePINs: [JobPIN] = []
    @Published var verificationInProgress = false
    
    private let pinLength = 4
    private let pinExpirationTime: TimeInterval = 600 // 10 minutes
    private let maxAttempts = 3
    private var listeners: [String: ListenerRegistration] = [:]
    
    private var db: Firestore? {
        guard FirebaseApp.app() != nil else {
            return nil
        }
        return Firestore.firestore()
    }
    
    private init() {
        loadLocalPINs()
        startExpirationTimer()
    }
    
    // MARK: - Firestore collection
    private var pinsCollection: CollectionReference {
        guard let db else {
            fatalError("Firestore accessed before Firebase configuration")
        }
        return db.collection("pins")
    }
    
    // MARK: - PIN Generation (saves to Firestore + local)
    
    func generatePIN(
        jobId: String,
        type: PINVerificationType,
        hirerId: String,
        workerId: String
    ) -> JobPIN {
        let pin = generateRandomPIN()
        
        let jobPIN = JobPIN(
            id: UUID().uuidString,
            jobId: jobId,
            pin: pin,
            type: type,
            hirerId: hirerId,
            workerId: workerId,
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(pinExpirationTime),
            status: .pending,
            verifiedAt: nil,
            attempts: 0
        )
        
        // Remove any old PIN for this job+type
        activePINs.removeAll { $0.jobId == jobId && $0.type == type }
        activePINs.append(jobPIN)
        saveLocalPINs()
        
        // Save to Firestore so the other device can see it
        pinsCollection.document(jobPIN.firestoreDocId).setData(jobPIN.toFirestoreData()) { error in
            if let error = error {
                print("❌ Failed to save PIN to Firestore: \(error.localizedDescription)")
            } else {
                print("☁️ PIN saved to Firestore for job \(jobId)")
            }
        }
        
        print("🔐 Generated \(type.rawValue) PIN for job \(jobId): \(pin)")
        return jobPIN
    }
    
    private func generateRandomPIN() -> String {
        var pin = ""
        for _ in 0..<pinLength {
            pin += String(Int.random(in: 0...9))
        }
        return pin
    }
    
    // MARK: - PIN Verification (fetches from Firestore first)
    
    func verifyPIN(
        jobId: String,
        enteredPIN: String,
        type: PINVerificationType,
        completion: @escaping (Bool, String) -> Void
    ) {
        let docId = "\(jobId)_\(type.firestoreKey)"
        
        // Fetch the PIN from Firestore (the source of truth)
        pinsCollection.document(docId).getDocument { [weak self] snapshot, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Failed to fetch PIN from Firestore: \(error.localizedDescription)")
                    // Fall back to local
                    self.verifyLocally(jobId: jobId, enteredPIN: enteredPIN, type: type, completion: completion)
                    return
                }
                
                guard let data = snapshot?.data(),
                      var pin = JobPIN.from(firestoreData: data) else {
                    completion(false, "No active PIN found for this job")
                    return
                }
                
                if pin.isExpired {
                    self.updatePINStatus(pin: pin, newStatus: .expired)
                    completion(false, "PIN has expired. Ask the hirer for a new one.")
                    return
                }
                
                if pin.status == .verified {
                    completion(false, "This PIN has already been used.")
                    return
                }
                
                if pin.attempts >= self.maxAttempts {
                    self.updatePINStatus(pin: pin, newStatus: .failed)
                    completion(false, "Too many failed attempts. Ask the hirer for a new PIN.")
                    return
                }
                
                pin.attempts += 1
                
                if enteredPIN == pin.pin {
                    pin.status = .verified
                    pin.verifiedAt = Date()
                    self.syncPINToFirestore(pin)
                    self.upsertLocal(pin)
                    
                    print("✅ PIN verified for job \(jobId): \(type.rawValue)")
                    completion(true, "PIN verified successfully!")
                } else {
                    self.syncPINToFirestore(pin)
                    self.upsertLocal(pin)
                    
                    let remaining = self.maxAttempts - pin.attempts
                    print("❌ Incorrect PIN for job \(jobId). Attempts: \(pin.attempts)/\(self.maxAttempts)")
                    completion(false, "Incorrect PIN. \(remaining) attempt(s) remaining.")
                }
            }
        }
    }
    
    private func verifyLocally(
        jobId: String,
        enteredPIN: String,
        type: PINVerificationType,
        completion: @escaping (Bool, String) -> Void
    ) {
        guard let index = activePINs.firstIndex(where: {
            $0.jobId == jobId && $0.type == type && $0.status == .pending
        }) else {
            completion(false, "No active PIN found for this job")
            return
        }
        
        var pin = activePINs[index]
        
        if pin.isExpired {
            pin.status = .expired
            activePINs[index] = pin
            saveLocalPINs()
            completion(false, "PIN has expired. Ask the hirer for a new one.")
            return
        }
        
        if pin.attempts >= maxAttempts {
            pin.status = .failed
            activePINs[index] = pin
            saveLocalPINs()
            completion(false, "Too many failed attempts. Ask the hirer for a new PIN.")
            return
        }
        
        pin.attempts += 1
        
        if enteredPIN == pin.pin {
            pin.status = .verified
            pin.verifiedAt = Date()
            activePINs[index] = pin
            saveLocalPINs()
            syncPINToFirestore(pin)
            completion(true, "PIN verified successfully!")
        } else {
            activePINs[index] = pin
            saveLocalPINs()
            let remaining = maxAttempts - pin.attempts
            completion(false, "Incorrect PIN. \(remaining) attempt(s) remaining.")
        }
    }
    
    // MARK: - Firestore Sync Helpers
    
    private func syncPINToFirestore(_ pin: JobPIN) {
        pinsCollection.document(pin.firestoreDocId).setData(pin.toFirestoreData(), merge: true)
    }
    
    private func updatePINStatus(pin: JobPIN, newStatus: PINStatus) {
        var updated = pin
        updated.status = newStatus
        syncPINToFirestore(updated)
        upsertLocal(updated)
    }
    
    private func upsertLocal(_ pin: JobPIN) {
        // Reassign the whole array so @Published fires reliably on observers
        // (subscript-set on a mutated element doesn't always wake SwiftUI views
        // when the same struct identity is preserved across snapshot updates).
        var updated = activePINs
        if let index = updated.firstIndex(where: { $0.jobId == pin.jobId && $0.type == pin.type }) {
            updated[index] = pin
        } else {
            updated.append(pin)
        }
        objectWillChange.send()
        activePINs = updated
        saveLocalPINs()
    }
    
    /// Fetch a PIN from Firestore (used by the worker's device to load the hirer-generated PIN)
    func fetchPIN(jobId: String, type: PINVerificationType, completion: @escaping (JobPIN?) -> Void) {
        guard db != nil else {
            completion(getPIN(jobId: jobId, type: type))
            return
        }
        let docId = "\(jobId)_\(type.firestoreKey)"
        pinsCollection.document(docId).getDocument { [weak self] snapshot, error in
            DispatchQueue.main.async {
                guard let data = snapshot?.data(),
                      let pin = JobPIN.from(firestoreData: data) else {
                    completion(nil)
                    return
                }
                self?.upsertLocal(pin)
                completion(pin)
            }
        }
    }
    
    func observePIN(jobId: String, type: PINVerificationType) {
        guard db != nil else { return }
        
        let docId = "\(jobId)_\(type.firestoreKey)"
        listeners[docId]?.remove()
        
        listeners[docId] = pinsCollection.document(docId).addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }
            if let error = error {
                print("❌ Error observing PIN \(docId): \(error.localizedDescription)")
                return
            }
            
            guard let data = snapshot?.data(),
                  let pin = JobPIN.from(firestoreData: data) else {
                return
            }
            
            DispatchQueue.main.async {
                self.upsertLocal(pin)
            }
        }
    }
    
    func stopObservingPIN(jobId: String, type: PINVerificationType) {
        let docId = "\(jobId)_\(type.firestoreKey)"
        listeners[docId]?.remove()
        listeners[docId] = nil
    }
    
    // MARK: - PIN Management
    
    func getPIN(jobId: String, type: PINVerificationType) -> JobPIN? {
        return activePINs.first { $0.jobId == jobId && $0.type == type }
    }
    
    func getActivePIN(jobId: String, type: PINVerificationType) -> JobPIN? {
        return activePINs.first {
            $0.jobId == jobId &&
            $0.type == type &&
            $0.status == .pending &&
            !$0.isExpired
        }
    }
    
    func regeneratePIN(jobId: String, type: PINVerificationType) -> JobPIN? {
        guard let oldPIN = getPIN(jobId: jobId, type: type) else { return nil }
        
        activePINs.removeAll { $0.jobId == jobId && $0.type == type }
        saveLocalPINs()
        
        return generatePIN(
            jobId: jobId,
            type: type,
            hirerId: oldPIN.hirerId,
            workerId: oldPIN.workerId
        )
    }
    
    func invalidatePIN(jobId: String, type: PINVerificationType) {
        if let index = activePINs.firstIndex(where: { $0.jobId == jobId && $0.type == type }) {
            activePINs[index].status = .expired
            saveLocalPINs()
            syncPINToFirestore(activePINs[index])
            print("🔒 Invalidated PIN for job \(jobId): \(type.rawValue)")
        }
    }
    
    func clearExpiredPINs() {
        let beforeCount = activePINs.count
        activePINs.removeAll { $0.isExpired && $0.status != .verified }
        
        if activePINs.count < beforeCount {
            saveLocalPINs()
            print("🧹 Cleared \(beforeCount - activePINs.count) expired PINs")
        }
    }
    
    // MARK: - Expiration Timer
    
    private func startExpirationTimer() {
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.clearExpiredPINs()
        }
    }
    
    // MARK: - Local Persistence (cache)
    
    private func saveLocalPINs() {
        if let encoded = try? JSONEncoder().encode(activePINs) {
            UserDefaults.standard.set(encoded, forKey: "job_pins")
        }
    }
    
    private func loadLocalPINs() {
        if let data = UserDefaults.standard.data(forKey: "job_pins"),
           let decoded = try? JSONDecoder().decode([JobPIN].self, from: data) {
            activePINs = decoded
            clearExpiredPINs()
            print("📁 Loaded \(activePINs.count) PINs from cache")
        }
    }
    
    // MARK: - Helper Methods
    
    func isVerified(jobId: String, type: PINVerificationType) -> Bool {
        return activePINs.contains {
            $0.jobId == jobId &&
            $0.type == type &&
            $0.status == .verified
        }
    }
    
    func getPINForDisplay(jobId: String, type: PINVerificationType) -> String? {
        return getActivePIN(jobId: jobId, type: type)?.pin
    }
    
    func getAttemptsRemaining(jobId: String, type: PINVerificationType) -> Int {
        guard let pin = getPIN(jobId: jobId, type: type) else { return maxAttempts }
        return max(0, maxAttempts - pin.attempts)
    }
}

// MARK: - PIN Input Validator

extension String {
    var isPINValid: Bool {
        return self.count == 4 && self.allSatisfy { $0.isNumber }
    }
    
    var formattedAsPIN: String {
        return self.prefix(4).map { String($0) }.joined(separator: " ")
    }
}
