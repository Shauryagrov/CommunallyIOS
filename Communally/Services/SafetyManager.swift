//
//  SafetyManager.swift
//  Communally
//
//  Manages user safety - blocking, reporting, and admin moderation
//

import Foundation
import FirebaseCore
import FirebaseFirestore
import FirebaseAuth

// MARK: - Report Types
enum ReportType: String, Codable, CaseIterable {
    // CRITICAL — triggers immediate account suspension + admin email
    case sexualAssault = "sexual_assault"
    case physicalAssault = "physical_assault"
    // Standard
    case inappropriateBehavior = "inappropriate_behavior"
    case harassment = "harassment"
    case spam = "spam"
    case scam = "scam"
    case fakeProfile = "fake_profile"
    case noShow = "no_show"
    case poorWork = "poor_work"
    case other = "other"

    var displayName: String {
        switch self {
        case .sexualAssault: return "Sexual Assault or Harassment"
        case .physicalAssault: return "Physical Assault or Violence"
        case .inappropriateBehavior: return "Inappropriate Behavior"
        case .harassment: return "Harassment or Bullying"
        case .spam: return "Spam"
        case .scam: return "Scam or Fraud"
        case .fakeProfile: return "Fake Profile"
        case .noShow: return "Didn't Show Up"
        case .poorWork: return "Poor Quality Work"
        case .other: return "Other"
        }
    }

    var icon: String {
        switch self {
        case .sexualAssault: return "exclamationmark.shield.fill"
        case .physicalAssault: return "figure.fall"
        case .inappropriateBehavior: return "exclamationmark.triangle.fill"
        case .harassment: return "hand.raised.fill"
        case .spam: return "envelope.badge.fill"
        case .scam: return "shield.slash.fill"
        case .fakeProfile: return "person.crop.circle.badge.exclamationmark"
        case .noShow: return "calendar.badge.exclamationmark"
        case .poorWork: return "star.slash.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }

    /// Critical reports trigger immediate account suspension and admin email alert.
    var isCritical: Bool {
        return self == .sexualAssault || self == .physicalAssault
    }
}

// MARK: - Report Status
enum ReportStatus: String, Codable {
    case pending = "pending"
    case reviewing = "reviewing"
    case resolved = "resolved"
    case dismissed = "dismissed"
}

// MARK: - Models
struct UserReport: Identifiable, Codable {
    @DocumentID var id: String?
    let reporterId: String
    let reporterName: String
    let reportedUserId: String
    let reportedUserName: String
    let type: ReportType
    let description: String
    let relatedJobId: String?
    let relatedJobTitle: String?
    var status: ReportStatus
    let createdAt: Date
    var reviewedAt: Date?
    var adminNotes: String?
    var isCritical: Bool?

    var safeId: String {
        id ?? UUID().uuidString
    }
}

struct BlockedUser: Identifiable, Codable {
    @DocumentID var id: String?
    let blockerId: String
    let blockedUserId: String
    let blockedUserName: String
    let createdAt: Date
    let reason: String?
    
    var safeId: String {
        id ?? UUID().uuidString
    }
}

// MARK: - Safety Manager
class SafetyManager: ObservableObject {
    static let shared = SafetyManager()
    
    @Published var blockedUsers: [BlockedUser] = []
    @Published var reports: [UserReport] = []
    
    private var db: Firestore? {
        guard FirebaseApp.app() != nil else {
            return nil
        }
        return Firestore.firestore()
    }
    
    private var blockListener: ListenerRegistration?
    private var reportListener: ListenerRegistration?
    
    private init() {}

    deinit {
        blockListener?.remove()
        reportListener?.remove()
    }

    /// Wipes in-memory state + listeners. Used after account deletion.
    func clearLocalState() {
        blockListener?.remove()
        reportListener?.remove()
        blockListener = nil
        reportListener = nil
        DispatchQueue.main.async {
            self.blockedUsers = []
            self.reports = []
        }
    }
    
    // MARK: - Start Listening
    
    func startListening(for userId: String) {
        listenToBlockedUsers(userId: userId)
    }
    
    private func listenToBlockedUsers(userId: String) {
        guard let db = db else { return }
        
        blockListener?.remove()
        
        blockListener = db.collection("blockedUsers")
            .whereField("blockerId", isEqualTo: userId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ Error fetching blocked users: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = snapshot?.documents else { return }
                
                self.blockedUsers = documents.compactMap { doc -> BlockedUser? in
                    try? doc.data(as: BlockedUser.self)
                }
                
                print("✅ Loaded \(self.blockedUsers.count) blocked users")
            }
    }
    
    // MARK: - Block User
    
    func blockUser(userId: String, userName: String, reason: String?, completion: @escaping (Bool) -> Void) {
        guard let currentUser = AuthenticationManager.shared.currentUser else {
            completion(false)
            return
        }
        
        guard let db = db else {
            print("⚠️ SafetyManager: Firebase not configured")
            completion(false)
            return
        }
        
        // Check if already blocked
        if isBlocked(userId: userId) {
            print("⚠️ User already blocked")
            completion(false)
            return
        }
        
        let blockedUser = BlockedUser(
            id: nil,
            blockerId: currentUser.id,
            blockedUserId: userId,
            blockedUserName: userName,
            createdAt: Date(),
            reason: reason
        )
        
        do {
            try db.collection("blockedUsers").addDocument(from: blockedUser) { error in
                if let error = error {
                    print("❌ Error blocking user: \(error.localizedDescription)")
                    completion(false)
                    return
                }
                
                print("✅ User blocked successfully")
                completion(true)
            }
        } catch {
            print("❌ Error encoding blocked user: \(error.localizedDescription)")
            completion(false)
        }
    }
    
    // MARK: - Unblock User
    
    func unblockUser(userId: String, completion: @escaping (Bool) -> Void) {
        guard let db = db else {
            completion(false)
            return
        }
        
        guard let blocked = blockedUsers.first(where: { $0.blockedUserId == userId }),
              let documentId = blocked.id else {
            completion(false)
            return
        }
        
        db.collection("blockedUsers").document(documentId).delete { error in
            if let error = error {
                print("❌ Error unblocking user: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            print("✅ User unblocked successfully")
            completion(true)
        }
    }
    
    // MARK: - Report User
    
    func reportUser(
        reportedUserId: String,
        reportedUserName: String,
        type: ReportType,
        description: String,
        relatedJobId: String? = nil,
        relatedJobTitle: String? = nil,
        completion: @escaping (Bool, String?) -> Void
    ) {
        guard let currentUser = AuthenticationManager.shared.currentUser else {
            completion(false, "You need to be signed in to submit a report.")
            return
        }
        
        guard let db = db else {
            print("⚠️ SafetyManager: Firebase not configured")
            completion(false, "Firebase isn’t configured on this device.")
            return
        }
        
        let report = UserReport(
            id: nil,
            reporterId: currentUser.id,
            reporterName: currentUser.fullName,
            reportedUserId: reportedUserId,
            reportedUserName: reportedUserName,
            type: type,
            description: description,
            relatedJobId: relatedJobId,
            relatedJobTitle: relatedJobTitle,
            status: .pending,
            createdAt: Date(),
            reviewedAt: nil,
            adminNotes: nil
        )
        
        Task { @MainActor in
            let outcome = await FirebaseAuthSessionSync.ensureFirebaseAuthForStorage(userId: currentUser.id)
            guard case .ready = outcome else {
                let detail: String
                if case .blocked(let d) = outcome, let d, !d.isEmpty {
                    detail = d
                } else {
                    detail = "Couldn’t verify your session for reporting. Sign out, sign in again, then try once more."
                }
                completion(false, detail)
                return
            }
            
            do {
                try db.collection("reports").addDocument(from: report) { error in
                    DispatchQueue.main.async {
                        if let error = error {
                            print("❌ Error submitting report: \(error.localizedDescription)")
                            completion(false, error.localizedDescription)
                            return
                        }
                        print("✅ Report submitted successfully")
                        completion(true, nil)
                    }
                }
            } catch {
                print("❌ Error encoding report: \(error.localizedDescription)")
                completion(false, error.localizedDescription)
            }
        }
    }
    
    // MARK: - Critical Safety Report (assault / violence)
    //
    // Routes through the `submitCriticalSafetyReport` Cloud Function so all
    // privileged side effects (admin email, auto-suspension of accused user,
    // rate-limit enforcement) happen server-side with proper auth. The old
    // implementation tried to write the suspension flag directly to the
    // accused user's doc — which silently failed because Firestore rules
    // only allow self-writes on /users/{userId}. The backend uses admin
    // SDK which bypasses those rules.
    func submitCriticalSafetyReport(
        reportedUserId: String,
        reportedUserName: String,
        type: ReportType,
        description: String,
        relatedJobId: String? = nil,
        relatedJobTitle: String? = nil,
        completion: @escaping (Bool, String?) -> Void
    ) {
        guard let currentUser = AuthenticationManager.shared.currentUser else {
            completion(false, "You must be signed in to submit a report.")
            return
        }
        guard let firUser = Auth.auth().currentUser else {
            completion(false, "Session error — please sign out and back in, then try again.")
            return
        }

        firUser.getIDToken { [weak self] idToken, tokenErr in
            guard let self = self else { return }
            if let tokenErr = tokenErr {
                DispatchQueue.main.async {
                    completion(false, tokenErr.localizedDescription)
                }
                return
            }
            guard let idToken = idToken else {
                DispatchQueue.main.async {
                    completion(false, "Couldn't authenticate. Try again.")
                }
                return
            }

            let url = "\(StripeConfig.backendURL)/submitCriticalSafetyReport"
            guard let requestURL = URL(string: url) else {
                DispatchQueue.main.async { completion(false, "Bad server URL.") }
                return
            }

            var request = URLRequest(url: requestURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            var body: [String: Any] = [
                "reporterId": currentUser.id,
                "reporterName": currentUser.fullName,
                "reportedUserId": reportedUserId,
                "reportedUserName": reportedUserName,
                "type": type.rawValue,
                "description": description,
                "idToken": idToken
            ]
            if let relatedJobId { body["relatedJobId"] = relatedJobId }
            if let relatedJobTitle { body["relatedJobTitle"] = relatedJobTitle }

            guard let payload = try? JSONSerialization.data(withJSONObject: body) else {
                DispatchQueue.main.async { completion(false, "Couldn't build report payload.") }
                return
            }
            request.httpBody = payload

            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    DispatchQueue.main.async { completion(false, error.localizedDescription) }
                    return
                }
                let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 0
                let json = (try? JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any]) ?? [:]
                if !(200...299).contains(httpStatus) {
                    let msg = (json["error"] as? String)
                        ?? "Couldn't submit report (\(httpStatus)). Try again or contact support."
                    DispatchQueue.main.async { completion(false, msg) }
                    return
                }
                // Also block locally so the reporter never sees the
                // accused again, regardless of whether the backend
                // auto-suspended them.
                self.blockUser(userId: reportedUserId, userName: reportedUserName, reason: "critical safety report") { _ in }
                DispatchQueue.main.async { completion(true, nil) }
            }.resume()
        }
    }

    // MARK: - Check Blocked

    func isBlocked(userId: String) -> Bool {
        return blockedUsers.contains { $0.blockedUserId == userId }
    }
    
    // MARK: - Get Blocked Users
    
    func getBlockedUserIds() -> [String] {
        return blockedUsers.map { $0.blockedUserId }
    }
}

