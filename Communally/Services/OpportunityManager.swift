//
//  OpportunityManager.swift
//  Communally
//
//  Manages job opportunities with Firebase Firestore
//

import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore

// Import status enum from ApplicationManager
enum OpportunityStatus: String, Codable {
    case open = "open"
    case inProgress = "in_progress"
    case completed = "completed"
    case cancelled = "cancelled"
}

class OpportunityManager: ObservableObject {
    static let shared = OpportunityManager()
    
    @Published var opportunities: [Opportunity] = []
    
    private var db: Firestore? {
        guard FirebaseApp.app() != nil else {
            return nil
        }
        return Firestore.firestore()
    }
    private var listener: ListenerRegistration?
    private var authHandle: AuthStateDidChangeListenerHandle?

    private init() {
        // Defer attaching the snapshot listener until Firebase Auth has a user.
        // Firestore rules require `isSignedIn()`; attaching pre-auth puts the
        // listener in a permission-denied state that doesn't recover, which
        // showed up as hirers not seeing their own posted jobs.
    }

    deinit {
        listener?.remove()
        if let handle = authHandle { Auth.auth().removeStateDidChangeListener(handle) }
    }

    // MARK: - Firestore Methods

    /// Wires up an auth state observer that attaches/detaches the opportunities
    /// snapshot listener as the user signs in/out. Idempotent — calling twice
    /// is a no-op after the first time.
    func initialize() {
        guard authHandle == nil else { return }
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self = self else { return }
            if user != nil {
                self.startListening()
            } else {
                self.listener?.remove()
                self.listener = nil
                DispatchQueue.main.async { self.opportunities = [] }
            }
        }
    }

    /// Wipes the in-memory snapshot + tears down the listener. Used after
    /// account deletion so the next sign-in starts from a clean slate
    /// instead of flashing stale data.
    func clearLocalState() {
        listener?.remove()
        listener = nil
        DispatchQueue.main.async {
            self.opportunities = []
        }
    }
    
    /// Start listening for real-time updates from Firestore
    private func startListening() {
        guard let db = db else {
            print("⚠️ OpportunityManager: Firebase not configured, skipping listener")
            return
        }

        // Tear down any previous listener before re-attaching so we don't
        // stack snapshots after sign-out → sign-in.
        listener?.remove()

        print("🔥 Starting Firestore listener for opportunities")

        listener = db.collection("opportunities")
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] querySnapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ Error fetching opportunities: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = querySnapshot?.documents else {
                    print("ℹ️ No opportunities found in Firestore")
                    return
                }
                
                self.opportunities = documents.compactMap { document -> Opportunity? in
                    do {
                        let opportunity = try document.data(as: Opportunity.self)
                        return opportunity
                    } catch {
                        print("❌ Error decoding opportunity: \(error.localizedDescription)")
                        return nil
                    }
                }
                
                print("✅ Loaded \(self.opportunities.count) opportunities from Firestore")
                self.expireOldOpportunities()
                self.deleteStaleInProgressOpportunities()
                self.closeOpportunitiesWithCompletedApplications()
            }
    }

    /// Self-heal: when the seeker presses "Mark as Complete" their write to
    /// the application succeeds (rules allow applicantId), but their write to
    /// the opportunity is denied (rules require hirerId). The opportunity gets
    /// stranded as `.inProgress` and the hirer's `ActiveJobBannerCard` keeps
    /// pointing at it. Detect that mismatch from the hirer side (where we DO
    /// have rule permission) and flip the opportunity to `.completed`.
    /// Triggered both from the opportunity snapshot listener and from
    /// `ApplicationManager.refreshMergedApplications`, since either side can
    /// arrive first after launch.
    func closeOpportunitiesWithCompletedApplications() {
        guard let currentUserId = AuthenticationManager.shared.currentUser?.id else { return }
        let myStrandedOpps = opportunities.filter { opp in
            opp.hirerId == currentUserId && opp.status == .inProgress
        }
        guard !myStrandedOpps.isEmpty else { return }

        let completedApps = ApplicationManager.shared.applications.filter { $0.status == .completed }
        let completedOppIds = Set(completedApps.map(\.opportunityId))

        for opp in myStrandedOpps where completedOppIds.contains(opp.safeId) {
            print("🩹 Auto-closing stranded opportunity \(opp.safeId) — accepted seeker already marked it complete")
            updateOpportunityStatus(
                opportunityId: opp.safeId,
                status: .completed,
                acceptedApplicantId: nil
            )
        }
    }
    
    /// Fetch opportunities once (useful for initial load or refresh)
    func fetchOpportunities() async {
        guard let db = db else {
            print("⚠️ OpportunityManager: Firebase not configured")
            return
        }
        
        do {
            let snapshot = try await db.collection("opportunities")
                .order(by: "createdAt", descending: true)
                .getDocuments()
            
            let fetchedOpportunities = snapshot.documents.compactMap { document -> Opportunity? in
                try? document.data(as: Opportunity.self)
            }
            
            await MainActor.run {
                self.opportunities = fetchedOpportunities
                print("✅ Fetched \(fetchedOpportunities.count) opportunities")
            }
        } catch {
            print("❌ Error fetching opportunities: \(error.localizedDescription)")
        }
    }
    
    func postOpportunity(
        title: String,
        description: String,
        location: Location,
        locationName: String,
        isVolunteer: Bool,
        payAmount: String?,
        jobType: String,
        hirerId: String,
        hirerName: String,
        hirerImageData: Data?,
        scheduledDate: Date?,
        scheduledTime: String?,
        scheduledEndTime: String? = nil,
        payIsHourly: Bool? = nil,
        completion: ((Error?) -> Void)? = nil
    ) {
        // Hard pre-check: Firestore rules require Firebase Auth uid == hirerId.
        // In Release builds the custom-token mint sometimes silently fails,
        // leaving Auth.currentUser nil. Without this check the local cache
        // accepts the write while the server rejects it — the new job
        // appears for a moment, then disappears on the next snapshot.
        let firebaseUid = Auth.auth().currentUser?.uid
        guard let firebaseUid, firebaseUid == hirerId else {
            let detail = firebaseUid == nil
                ? "Your secure session expired. Sign out and sign back in, then try again."
                : "Your account didn't match the secure session. Sign out and sign back in, then try again."
            let err = NSError(
                domain: "OpportunityManager",
                code: -1001,
                userInfo: [NSLocalizedDescriptionKey: detail]
            )
            print("❌ postOpportunity blocked: Auth uid (\(firebaseUid ?? "nil")) != hirerId (\(hirerId))")
            DispatchQueue.main.async { completion?(err) }
            return
        }

        let opportunityId = UUID().uuidString
        let opportunity = Opportunity(
            id: opportunityId,
            title: title,
            description: description,
            hirerId: hirerId,
            hirerName: hirerName,
            hirerImageData: hirerImageData,
            location: location,
            locationName: locationName,
            isVolunteer: isVolunteer,
            payAmount: payAmount,
            jobType: jobType,
            createdAt: Date(),
            isActive: true,
            applicantCount: 0,
            status: .open,
            acceptedApplicantId: nil,
            scheduledDate: scheduledDate,
            scheduledTime: scheduledTime,
            scheduledEndTime: scheduledEndTime,
            payIsHourly: payIsHourly
        )

        guard let db = db else {
            let err = NSError(
                domain: "OpportunityManager",
                code: -1002,
                userInfo: [NSLocalizedDescriptionKey: "Firebase isn't ready. Restart the app and try again."]
            )
            print("⚠️ OpportunityManager: Firebase not configured")
            DispatchQueue.main.async { completion?(err) }
            return
        }

        // Use the completion-handler form so we surface server-side rejections
        // (e.g. rules denial) to the user — `setData(from:)` without a callback
        // accepts the local cache write and lets server errors disappear.
        do {
            try db.collection("opportunities").document(opportunityId).setData(from: opportunity) { error in
                if let error = error {
                    print("❌ Error posting opportunity to server: \(error.localizedDescription)")
                    DispatchQueue.main.async { completion?(error) }
                    return
                }
                print("✅ Posted opportunity to Firestore: \(title)")
                print("🔍 Opportunity ID: \(opportunityId)")
                print("👤 Hirer: \(hirerName) (\(hirerId))")
                NotificationManager.shared.sendNewOpportunityNotification(opportunity: opportunity)
                DispatchQueue.main.async { completion?(nil) }
            }
        } catch {
            print("❌ Error encoding opportunity: \(error.localizedDescription)")
            DispatchQueue.main.async { completion?(error) }
        }
    }
    
    func getUserOpportunities(userId: String) -> [Opportunity] {
        return opportunities.filter { $0.hirerId == userId }
    }
    
    func getAllActiveOpportunities() -> [Opportunity] {
        return opportunities.filter { opp in
            guard opp.isActive && opp.status == .open else { return false }
            let base = opp.scheduledDate ?? opp.createdAt
            return base.addingTimeInterval(86400) > Date()
        }
    }

    /// Expire open posts whose scheduled date (or creation date) + 24h has passed.
    func expireOldOpportunities() {
        guard let db = db else { return }
        guard let currentUserId = AuthenticationManager.shared.currentUser?.id else { return }
        let now = Date()
        let stale = opportunities.filter { opp in
            guard opp.status == .open && opp.isActive && opp.hirerId == currentUserId else { return false }
            let base = opp.scheduledDate ?? opp.createdAt
            return base.addingTimeInterval(86400) <= now
        }
        for opp in stale {
            db.collection("opportunities").document(opp.safeId).updateData([
                "isActive": false,
                "status": OpportunityStatus.cancelled.rawValue
            ]) { error in
                if error == nil {
                    print("⏰ Expired opportunity: \(opp.title)")
                }
            }
        }
    }

    /// Delete in-progress jobs that have been running for over 100 hours.
    func deleteStaleInProgressOpportunities() {
        guard let db = db else { return }
        guard let currentUserId = AuthenticationManager.shared.currentUser?.id else { return }
        let cutoff = Date().addingTimeInterval(-100 * 3600)
        let stale = opportunities.filter { opp in
            guard opp.status == .inProgress, let startedAt = opp.inProgressAt else { return false }
            guard opp.hirerId == currentUserId else { return false }
            return startedAt <= cutoff
        }
        for opp in stale {
            db.collection("opportunities").document(opp.safeId).delete { error in
                if error == nil {
                    print("🗑️ Deleted stale in-progress opportunity: \(opp.title)")
                }
            }
        }
    }
    
    func deleteOpportunity(id: String) {
        guard let db = db else {
            print("⚠️ OpportunityManager: Firebase not configured")
            return
        }

        db.collection("opportunities").document(id).delete { error in
            if let error = error {
                print("❌ Error deleting opportunity: \(error.localizedDescription)")
            } else {
                print("✅ Deleted opportunity: \(id)")
            }
        }
        // The listener will automatically update the local array
    }

    /// Update the schedule on an existing opportunity. Used by the
    /// past-start-time banner so a hirer can bump the date/time forward
    /// without deleting and reposting (which would lose applicants).
    /// Times are passed as the same "9:00 AM" / "11:00 AM" strings the
    /// composer writes — they parse cleanly back into `scheduledStartDateTime`.
    func rescheduleOpportunity(
        id: String,
        newDate: Date,
        newStartTime: String,
        newEndTime: String,
        completion: ((Bool) -> Void)? = nil
    ) {
        guard let db = db else {
            print("⚠️ OpportunityManager: Firebase not configured")
            completion?(false)
            return
        }

        db.collection("opportunities").document(id).updateData([
            "scheduledDate": Timestamp(date: newDate),
            "scheduledTime": newStartTime,
            "scheduledEndTime": newEndTime
        ]) { error in
            if let error = error {
                print("❌ Error rescheduling opportunity: \(error.localizedDescription)")
                completion?(false)
            } else {
                print("✅ Rescheduled opportunity: \(id)")
                completion?(true)
            }
        }
    }
    
    // MARK: - Profile Sync
    
    func updateHirerProfile(userId: String, name: String, imageData: Data?) async {
        guard let db = db else {
            print("⚠️ OpportunityManager: Firebase not configured")
            return
        }
        
        print("🔄 Updating hirer profile in opportunities for user: \(userId)")
        
        // Get all opportunities for this hirer
        let userOpportunities = opportunities.filter { $0.hirerId == userId }
        
        for opportunity in userOpportunities {
            var updateData: [String: Any] = [
                "hirerName": name
            ]
            
            if let imageData = imageData {
                updateData["hirerImageData"] = imageData
            }
            
            do {
                try await db.collection("opportunities").document(opportunity.safeId).updateData(updateData)
                print("✅ Updated opportunity \(opportunity.safeId) with new hirer profile")
            } catch {
                print("❌ Error updating opportunity \(opportunity.safeId): \(error.localizedDescription)")
            }
        }
        
        print("✅ Updated \(userOpportunities.count) opportunities with new profile")
    }
    
    func toggleOpportunityStatus(id: String) {
        guard let opportunity = opportunities.first(where: { $0.safeId == id }) else { return }
        
        guard let db = db else {
            print("⚠️ OpportunityManager: Firebase not configured")
            return
        }
        
        db.collection("opportunities").document(id).updateData([
            "isActive": !opportunity.isActive
        ]) { error in
            if let error = error {
                print("❌ Error toggling opportunity status: \(error.localizedDescription)")
            } else {
                print("✅ Toggled opportunity status: \(id)")
            }
        }
    }
    
    func incrementApplicantCount(opportunityId: String) {
        guard let db = db else {
            print("⚠️ OpportunityManager: Firebase not configured")
            return
        }
        
        db.collection("opportunities").document(opportunityId).updateData([
            "applicantCount": FieldValue.increment(Int64(1))
        ]) { error in
            if let error = error {
                print("❌ Error incrementing applicant count: \(error.localizedDescription)")
            } else {
                print("✅ Incremented applicant count for: \(opportunityId)")
            }
        }
    }
    
    /// Sets `applicantCount` to the number of `applications` docs for this opportunity (fixes drift after deletes).
    func recalculateApplicantCount(opportunityId: String, completion: ((Error?) -> Void)? = nil) {
        guard let db = db else {
            completion?(NSError(domain: "OpportunityManager", code: 0, userInfo: [NSLocalizedDescriptionKey: "Firebase not configured"]))
            return
        }
        
        Task {
            do {
                let oppRef = db.collection("opportunities").document(opportunityId)
                let oppDoc = try await oppRef.getDocument()
                guard oppDoc.exists else {
                    await MainActor.run { completion?(nil) }
                    return
                }
                let apps = try await db.collection("applications")
                    .whereField("opportunityId", isEqualTo: opportunityId)
                    .getDocuments()
                let count = apps.documents.count
                try await oppRef.updateData(["applicantCount": count])
                await MainActor.run { completion?(nil) }
            } catch {
                print("❌ recalculateApplicantCount: \(error.localizedDescription)")
                await MainActor.run { completion?(error) }
            }
        }
    }
    
    func updateOpportunityStatus(opportunityId: String, status: OpportunityStatus, acceptedApplicantId: String?) {
        var updateData: [String: Any] = [
            "status": status.rawValue
        ]
        
        if let acceptedApplicantId = acceptedApplicantId {
            updateData["acceptedApplicantId"] = acceptedApplicantId
        }
        
        // Close to new applications when in progress or completed
        if status == .inProgress || status == .completed {
            updateData["isActive"] = false
        }

        if status == .inProgress {
            updateData["inProgressAt"] = Timestamp(date: Date())
        }
        
        guard let db = db else {
            print("⚠️ OpportunityManager: Firebase not configured")
            return
        }
        
        db.collection("opportunities").document(opportunityId).updateData(updateData) { error in
            if let error = error {
                print("❌ Error updating opportunity status: \(error.localizedDescription)")
            } else {
                print("✅ Updated opportunity status: \(opportunityId)")
            }
        }
    }
    
    // MARK: - Data Management
    
    /// Delete all opportunities from Firestore (for testing/reset purposes)
    func deleteAllOpportunities() async {
        guard let db = db else {
            print("⚠️ OpportunityManager: Firebase not configured")
            return
        }
        
        print("🗑️ Starting to delete all opportunities...")
        
        do {
            let snapshot = try await db.collection("opportunities").getDocuments()
            
            print("📋 Found \(snapshot.documents.count) opportunities to delete")
            
            // Delete in batches for better performance
            let batch = db.batch()
            for document in snapshot.documents {
                batch.deleteDocument(document.reference)
            }
            
            try await batch.commit()
            
            await MainActor.run {
                self.opportunities = []
            }
            
            print("✅ Successfully deleted all opportunities from Firestore")
        } catch {
            print("❌ Error deleting all opportunities: \(error.localizedDescription)")
        }
    }
    
    /// Delete all opportunities for a specific user (for account deletion)
    func deleteAllOpportunities(for userId: String) async {
        guard let db = db else {
            print("⚠️ OpportunityManager: Firebase not configured")
            return
        }
        
        print("🗑️ Deleting all opportunities for user: \(userId)")
        
        do {
            let snapshot = try await db.collection("opportunities")
                .whereField("hirerId", isEqualTo: userId)
                .getDocuments()
            
            print("📋 Found \(snapshot.documents.count) opportunities to delete for user")
            
            // Delete in batches
            let batch = db.batch()
            for document in snapshot.documents {
                batch.deleteDocument(document.reference)
            }
            
            try await batch.commit()
            
            print("✅ Successfully deleted user's opportunities from Firestore")
        } catch {
            print("❌ Error deleting user's opportunities: \(error.localizedDescription)")
        }
    }
}

struct Opportunity: Identifiable, Codable {
    @DocumentID var id: String?
    let title: String
    let description: String
    let hirerId: String
    let hirerName: String
    let hirerImageData: Data?
    let location: Location
    let locationName: String
    let isVolunteer: Bool
    let payAmount: String?
    let jobType: String
    let createdAt: Date
    var isActive: Bool
    var applicantCount: Int
    var status: OpportunityStatus
    var acceptedApplicantId: String?
    let scheduledDate: Date?
    let scheduledTime: String?
    /// Required for new posts: end time string (e.g. "11:30 AM"). Hard-capped
    /// so the job ends by 7 PM on the scheduled date. Nil on legacy jobs.
    var scheduledEndTime: String?
    /// True for jobs posted on/after the per-hour pricing rollout. Nil/false
    /// on legacy jobs whose `payAmount` is a flat total. Drives `displayPay`.
    var payIsHourly: Bool?
    var inProgressAt: Date?

    // Custom coding keys to handle Firestore document ID
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case hirerId
        case hirerName
        case hirerImageData
        case location
        case locationName
        case isVolunteer
        case payAmount
        case jobType
        case createdAt
        case isActive
        case applicantCount
        case status
        case acceptedApplicantId
        case scheduledDate
        case scheduledTime
        case scheduledEndTime
        case payIsHourly
        case inProgressAt
    }

    // Safe id access - returns the id or a fallback
    var safeId: String {
        return id ?? UUID().uuidString
    }

    var displayPay: String {
        if isVolunteer {
            return "Volunteer"
        } else if let amount = payAmount, !amount.isEmpty {
            return payIsHourly == true ? "$\(amount)/hr" : "$\(amount)"
        } else {
            return "Negotiable"
        }
    }

    /// Absolute start-of-job timestamp = `scheduledDate` (day component)
    /// merged with the parsed hour/minute from `scheduledTime`. Returns nil
    /// for legacy jobs without a time string. Used to gate "Job Start" so a
    /// seeker can't clock in at 2 AM the day before the actual job.
    var scheduledStartDateTime: Date? {
        guard let day = scheduledDate,
              let startStr = scheduledTime, !startStr.isEmpty else { return nil }
        let f = DateFormatter()
        f.timeStyle = .short
        guard let parsed = f.date(from: startStr) else { return nil }
        let cal = Calendar.current
        let dayParts = cal.dateComponents([.year, .month, .day], from: day)
        let timeParts = cal.dateComponents([.hour, .minute], from: parsed)
        var merged = DateComponents()
        merged.year = dayParts.year
        merged.month = dayParts.month
        merged.day = dayParts.day
        merged.hour = timeParts.hour
        merged.minute = timeParts.minute
        return cal.date(from: merged)
    }

    /// Absolute end-of-job timestamp = `scheduledDate` (day component) merged
    /// with the parsed hour/minute from `scheduledEndTime`. Used to gate the
    /// "Mark as Complete" button so neither party can short-circuit a job that
    /// was scheduled to run, e.g., 9–11 AM by completing it at 9:05.
    /// Returns nil for legacy jobs without an end time string.
    var scheduledEndDateTime: Date? {
        guard let day = scheduledDate,
              let endStr = scheduledEndTime, !endStr.isEmpty else { return nil }
        let f = DateFormatter()
        f.timeStyle = .short
        guard let parsed = f.date(from: endStr) else { return nil }
        let cal = Calendar.current
        let dayParts = cal.dateComponents([.year, .month, .day], from: day)
        let timeParts = cal.dateComponents([.hour, .minute], from: parsed)
        var merged = DateComponents()
        merged.year = dayParts.year
        merged.month = dayParts.month
        merged.day = dayParts.day
        merged.hour = timeParts.hour
        merged.minute = timeParts.minute
        return cal.date(from: merged)
    }

    /// Implied $/hr derived from total pay ÷ scheduled duration. Returns nil
    /// for legacy jobs missing an end time, volunteer jobs, or jobs already
    /// stored as hourly. Use this on detail views to show seekers the
    /// effective hourly under the headline total.
    var derivedHourlyPay: Int? {
        if isVolunteer { return nil }
        if payIsHourly == true { return nil }
        guard let amount = payAmount, let total = Int(amount), total > 0,
              let startStr = scheduledTime, !startStr.isEmpty,
              let endStr = scheduledEndTime, !endStr.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.timeStyle = .short
        guard let start = formatter.date(from: startStr),
              let end = formatter.date(from: endStr),
              end > start else { return nil }
        let hours = end.timeIntervalSince(start) / 3600
        guard hours > 0 else { return nil }
        return Int((Double(total) / hours).rounded())
    }
    
    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }

    var expiresIn: TimeInterval {
        let base = scheduledDate ?? createdAt
        return base.addingTimeInterval(86400).timeIntervalSinceNow
    }

    var isExpired: Bool { status == .open && expiresIn <= 0 }
    var expiresSoon: Bool { status == .open && expiresIn > 0 && expiresIn < 3600 }

    var expiryLabel: String? {
        guard status == .open else { return nil }
        let hours = Int(expiresIn / 3600)
        let mins  = Int((expiresIn.truncatingRemainder(dividingBy: 3600)) / 60)
        if hours <= 0 && mins <= 0 { return "Expired" }
        if hours < 1 { return "Expires in \(mins)m" }
        if hours < 6 { return "Expires in \(hours)h \(mins)m" }
        return nil
    }
    
    var statusDisplay: String {
        switch status {
        case .open: return "Open"
        case .inProgress: return "In Progress"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        }
    }
    
    var statusColor: Color {
        switch status {
        case .open: return .green
        case .inProgress: return .orange
        case .completed: return .blue
        case .cancelled: return .gray
        }
    }
}

