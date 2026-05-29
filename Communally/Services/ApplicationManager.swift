//
//  ApplicationManager.swift
//  Communally
//
//  Manages job applications and workflow
//

import Foundation
import SwiftUI
import FirebaseCore
import FirebaseFirestore

class ApplicationManager: ObservableObject {
    static let shared = ApplicationManager()
    
    @Published var applications: [JobApplication] = []
    
    private var db: Firestore? {
        guard FirebaseApp.app() != nil else {
            return nil
        }
        return Firestore.firestore()
    }
    private var applicantListener: ListenerRegistration?
    private var hirerListener: ListenerRegistration?
    private var applicantDocsById: [String: QueryDocumentSnapshot] = [:]
    private var hirerDocsById: [String: QueryDocumentSnapshot] = [:]
    
    private init() {}

    deinit {
        applicantListener?.remove()
        hirerListener?.remove()
    }

    /// Wipes in-memory state + listeners. Used after account deletion.
    func clearLocalState() {
        applicantListener?.remove()
        hirerListener?.remove()
        applicantListener = nil
        hirerListener = nil
        applicantDocsById = [:]
        hirerDocsById = [:]
        DispatchQueue.main.async { self.applications = [] }
    }
    
    /// Initialize and start listening for real-time updates from Firestore
    func initialize() {
        guard let userId = AuthenticationManager.shared.currentUser?.id else { return }
        startListening(for: userId)
    }
    
    // Real-time sync with Firebase
    func startListening(for userId: String) {
        guard let db = db else {
            print("⚠️ ApplicationManager: Firebase not configured")
            return
        }
        
        applicantListener?.remove()
        hirerListener?.remove()
        applicantDocsById = [:]
        hirerDocsById = [:]

        applicantListener = db.collection("applications")
            .whereField("applicantId", isEqualTo: userId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ Error listening to applications: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    return
                }
                self.applicantDocsById = Dictionary(uniqueKeysWithValues: documents.map { ($0.documentID, $0) })
                self.refreshMergedApplications()
            }

        hirerListener = db.collection("applications")
            .whereField("hirerIdSnapshot", isEqualTo: userId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }

                if let error = error {
                    print("❌ Error listening to hirer applications: \(error.localizedDescription)")
                    return
                }

                guard let documents = snapshot?.documents else {
                    return
                }

                self.hirerDocsById = Dictionary(uniqueKeysWithValues: documents.map { ($0.documentID, $0) })
                self.refreshMergedApplications()
            }
    }

    private func refreshMergedApplications() {
        let merged = applicantDocsById.merging(hirerDocsById) { current, _ in current }
        self.applications = merged.values.compactMap(decodeApplication(from:))
        print("✅ Synced \(self.applications.count) applications from Firebase")
        // Either side's listener can arrive first; nudge the opp self-heal
        // here too so a stranded `.inProgress` opportunity gets cleared as
        // soon as the matching `.completed` application lands.
        OpportunityManager.shared.closeOpportunitiesWithCompletedApplications()
    }

    private func decodeApplication(from doc: QueryDocumentSnapshot) -> JobApplication? {
        let data = doc.data()

        guard let opportunityId = data["opportunityId"] as? String,
              let applicantId = data["applicantId"] as? String,
              let applicantName = data["applicantName"] as? String,
              let statusString = data["status"] as? String,
              let status = ApplicationStatus(rawValue: statusString),
              let appliedAtTimestamp = data["appliedAt"] as? Timestamp else {
            return nil
        }

        let applicantImageDataString = data["applicantImageData"] as? String
        let applicantImageData = applicantImageDataString.flatMap { Data(base64Encoded: $0) }

        let acceptedAtTimestamp = data["acceptedAt"] as? Timestamp
        let completedAtTimestamp = data["completedAt"] as? Timestamp
        let hirerConfirmedAtTimestamp = data["hirerConfirmedCompletionAt"] as? Timestamp
        let workerConfirmedAtTimestamp = data["workerConfirmedCompletionAt"] as? Timestamp
        let message = data["message"] as? String
        let paymentId = data["paymentId"] as? String
        let isPaid = data["isPaid"] as? Bool
        let paidAtTimestamp = data["paidAt"] as? Timestamp
        let opportunityTitleSnapshot = data["opportunityTitleSnapshot"] as? String
        let opportunityJobTypeSnapshot = data["opportunityJobTypeSnapshot"] as? String
        let opportunityLocationNameSnapshot = data["opportunityLocationNameSnapshot"] as? String
        let opportunityLocationLatitudeSnapshot = data["opportunityLocationLatitudeSnapshot"] as? Double
        let opportunityLocationLongitudeSnapshot = data["opportunityLocationLongitudeSnapshot"] as? Double
        let hirerIdSnapshot = data["hirerIdSnapshot"] as? String
        let hirerNameSnapshot = data["hirerNameSnapshot"] as? String

        return JobApplication(
            id: doc.documentID,
            opportunityId: opportunityId,
            applicantId: applicantId,
            applicantName: applicantName,
            applicantImageData: applicantImageData,
            status: status,
            appliedAt: appliedAtTimestamp.dateValue(),
            acceptedAt: acceptedAtTimestamp?.dateValue(),
            completedAt: completedAtTimestamp?.dateValue(),
            hirerConfirmedCompletionAt: hirerConfirmedAtTimestamp?.dateValue(),
            workerConfirmedCompletionAt: workerConfirmedAtTimestamp?.dateValue(),
            message: message,
            paymentId: paymentId,
            isPaid: isPaid,
            paidAt: paidAtTimestamp?.dateValue(),
            opportunityTitleSnapshot: opportunityTitleSnapshot,
            opportunityJobTypeSnapshot: opportunityJobTypeSnapshot,
            opportunityLocationNameSnapshot: opportunityLocationNameSnapshot,
            opportunityLocationLatitudeSnapshot: opportunityLocationLatitudeSnapshot,
            opportunityLocationLongitudeSnapshot: opportunityLocationLongitudeSnapshot,
            hirerIdSnapshot: hirerIdSnapshot,
            hirerNameSnapshot: hirerNameSnapshot
        )
    }
    
    // Submit application
    func applyToOpportunity(opportunityId: String, applicantId: String, applicantName: String, applicantImageData: Data?) {
        // Check if already applied
        if hasApplied(opportunityId: opportunityId, applicantId: applicantId) {
            print("⚠️ User already applied to this opportunity")
            return
        }
        
        let opportunity = OpportunityManager.shared.opportunities.first(where: { $0.safeId == opportunityId })
        // Auth check stays — only the signed-in user can apply on their own
        // behalf. Payout-readiness is NO LONGER a gate: seekers can apply to
        // paid jobs without a Stripe Connect account; the worker's earnings
        // accrue in their Communally balance via the backend `releasePayment`
        // → `payable` path, and they cash out later via `claimEarnings`.
        guard AuthenticationManager.shared.currentUser?.id == applicantId else {
            print("⚠️ Application blocked: must be signed in as the applicant")
            return
        }
        
        let applicationId = UUID().uuidString
        
        // Convert image data to base64 for Firebase
        let imageDataString = applicantImageData?.base64EncodedString()
        
        let applicationData: [String: Any] = [
            "opportunityId": opportunityId,
            "applicantId": applicantId,
            "applicantName": applicantName,
            "applicantImageData": imageDataString as Any,
            "status": ApplicationStatus.pending.rawValue,
            "appliedAt": Timestamp(date: Date()),
            "message": NSNull(),
            "opportunityTitleSnapshot": opportunity?.title as Any,
            "opportunityJobTypeSnapshot": opportunity?.jobType as Any,
            "opportunityLocationNameSnapshot": opportunity?.locationName as Any,
            "opportunityLocationLatitudeSnapshot": opportunity?.location.latitude as Any,
            "opportunityLocationLongitudeSnapshot": opportunity?.location.longitude as Any,
            "hirerIdSnapshot": opportunity?.hirerId as Any,
            "hirerNameSnapshot": opportunity?.hirerName as Any
        ]
        
        guard let db = db else {
            print("⚠️ ApplicationManager: Firebase not configured")
            return
        }
        
        // Save to Firebase
        db.collection("applications").document(applicationId).setData(applicationData) { error in
            if let error = error {
                print("❌ Error submitting application: \(error.localizedDescription)")
            } else {
                print("✅ Application submitted by \(applicantName)")
                
                // Update opportunity applicant count
                OpportunityManager.shared.incrementApplicantCount(opportunityId: opportunityId)
                
                // Get the opportunity to send notification to hirer
                if let opportunity {
                    // Create temporary application for notification
                    let tempApplication = JobApplication(
                        id: applicationId,
                        opportunityId: opportunityId,
                        applicantId: applicantId,
                        applicantName: applicantName,
                        applicantImageData: applicantImageData,
                        status: .pending,
                        appliedAt: Date(),
                        acceptedAt: nil,
                        completedAt: nil,
                        message: nil,
                        paymentId: nil,
                        isPaid: nil,
                        paidAt: nil,
                        opportunityTitleSnapshot: opportunity.title,
                        opportunityJobTypeSnapshot: opportunity.jobType,
                        opportunityLocationNameSnapshot: opportunity.locationName,
                        opportunityLocationLatitudeSnapshot: opportunity.location.latitude,
                        opportunityLocationLongitudeSnapshot: opportunity.location.longitude,
                        hirerIdSnapshot: opportunity.hirerId,
                        hirerNameSnapshot: opportunity.hirerName
                    )
                    
                    // Send notification to hirer
                    NotificationManager.shared.sendNewApplicationNotification(
                        application: tempApplication,
                        hirerId: opportunity.hirerId,
                        applicantName: applicantName,
                        opportunityTitle: opportunity.title
                    )
                }
            }
        }
    }
    
    // Check if user already applied
    func hasApplied(opportunityId: String, applicantId: String) -> Bool {
        return applications.contains { 
            $0.opportunityId == opportunityId && $0.applicantId == applicantId
        }
    }
    
    // Get applications for specific opportunity
    func getApplications(forOpportunity opportunityId: String) -> [JobApplication] {
        return applications.filter { $0.opportunityId == opportunityId }
    }
    
    // Get pending applications for opportunity
    func getPendingApplications(forOpportunity opportunityId: String) -> [JobApplication] {
        return applications.filter { 
            $0.opportunityId == opportunityId && $0.status == .pending 
        }
    }
    
    // Get applications by user
    func getApplications(byUser userId: String) -> [JobApplication] {
        return applications.filter { $0.applicantId == userId }
    }
    
    /// Soft cap on simultaneously-accepted jobs per seeker. Prevents
    /// obvious overcommitting (accepting 8 jobs on Saturday and ghosting
    /// 7) without being so strict that repeat hirers can't re-book the
    /// same person on different days.
    static let maxActiveAcceptedJobs = 3

    /// Why a candidate accept/apply is being blocked. Lets the UI show
    /// a different message for "you already have something that day"
    /// vs "you've hit the active-job limit."
    enum AcceptConflict {
        case sameDay(existing: JobApplication)
        case overCap
    }

    /// LEGACY — kept for callers that just want "do they have ANY
    /// active accepted job." New code should prefer
    /// `acceptConflict(for:candidateOpportunity:)` since the old one
    /// fires false-positives across different days.
    func activeAcceptedApplication(for applicantId: String, excludingOpportunityId: String? = nil) -> JobApplication? {
        applications.first {
            $0.applicantId == applicantId &&
            $0.status == .accepted &&
            $0.opportunityId != excludingOpportunityId
        }
    }

    /// Schedule-aware check used by both the seeker apply gate and the
    /// hirer accept gate. Returns:
    ///   • .sameDay(existing) — the seeker already has an accepted job
    ///     on the SAME calendar day as `candidate`, and physical
    ///     simultaneity is impossible. Block.
    ///   • .overCap — the seeker would exceed `maxActiveAcceptedJobs`
    ///     across all days. Soft brake on overcommitting.
    ///   • nil — all clear, accept/apply proceeds.
    ///
    /// "Anytime" candidate (scheduledDate == nil) and "anytime" existing
    /// jobs are treated as non-conflicting since flex jobs are flexible
    /// by design — the worker can choose when to slot them.
    func acceptConflict(
        for applicantId: String,
        candidateOpportunity: Opportunity
    ) -> AcceptConflict? {
        let othersAccepted = applications.filter {
            $0.applicantId == applicantId &&
            $0.status == .accepted &&
            $0.opportunityId != candidateOpportunity.safeId
        }

        // Soft cap first — catches users who'd hold 4+ active jobs at once.
        if othersAccepted.count >= Self.maxActiveAcceptedJobs {
            return .overCap
        }

        // Day-collision check — only triggers when BOTH the candidate
        // and the existing accepted job have a scheduledDate AND fall
        // on the same calendar day.
        guard let candidateDate = candidateOpportunity.scheduledDate else { return nil }
        let cal = Calendar.current
        let allOpps = OpportunityManager.shared.opportunities
        if let dayConflict = othersAccepted.first(where: { app in
            guard let appOppDate = allOpps.first(where: { $0.safeId == app.opportunityId })?.scheduledDate else {
                return false
            }
            return cal.isDate(appOppDate, inSameDayAs: candidateDate)
        }) {
            return .sameDay(existing: dayConflict)
        }
        return nil
    }

    func canApplicantBeAccepted(_ applicantId: String, for opportunityId: String) -> Bool {
        guard let opp = OpportunityManager.shared.opportunities.first(where: { $0.safeId == opportunityId }) else {
            // Couldn't resolve the candidate — fall back to the
            // conservative legacy check.
            return activeAcceptedApplication(for: applicantId, excludingOpportunityId: opportunityId) == nil
        }
        return acceptConflict(for: applicantId, candidateOpportunity: opp) == nil
    }
    
    // Accept application (hirer chooses someone)
    func acceptApplication(applicationId: String, completion: ((Bool, String?) -> Void)? = nil) {
        guard let application = applications.first(where: { $0.id == applicationId }) else {
            print("❌ Application not found")
            completion?(false, "Application not found.")
            return
        }
        
        let opportunityId = application.opportunityId

        // Schedule-aware conflict check — only blocks for SAME-DAY
        // overlaps or when the seeker would exceed the active-job cap.
        // Sequential bookings on different days proceed normally.
        if let candidate = OpportunityManager.shared.opportunities.first(where: { $0.safeId == opportunityId }),
           let conflict = acceptConflict(for: application.applicantId, candidateOpportunity: candidate) {
            switch conflict {
            case .sameDay(let existing):
                let jobTitle = existing.opportunityTitleSnapshot ?? "another job"
                print("⚠️ Applicant already has a same-day accepted job: \(jobTitle)")
                completion?(false, "\(application.applicantName) is already booked for \(jobTitle) that day. They can only work one job per day.")
                return
            case .overCap:
                print("⚠️ Applicant has reached the active-job cap")
                completion?(false, "\(application.applicantName) already has \(Self.maxActiveAcceptedJobs) active jobs and can't take on another until one finishes.")
                return
            }
        }
        
        guard let db = db else {
            print("⚠️ ApplicationManager: Firebase not configured")
            completion?(false, "Firebase is not configured yet.")
            return
        }
        
        // Update this application to accepted in Firebase
        db.collection("applications").document(applicationId).updateData([
            "status": ApplicationStatus.accepted.rawValue,
            "acceptedAt": Timestamp(date: Date())
        ]) { [weak self] error in
            if let error = error {
                print("❌ Error accepting application: \(error.localizedDescription)")
                completion?(false, error.localizedDescription)
                return
            }
            
            print("✅ Application accepted for opportunity \(opportunityId)")
            
            // Update opportunity status to in progress
            OpportunityManager.shared.updateOpportunityStatus(
                opportunityId: opportunityId,
                status: .inProgress,
                acceptedApplicantId: application.applicantId
            )
            
            // Send notifications
            if let opportunity = OpportunityManager.shared.opportunities.first(where: { $0.safeId == opportunityId }) {
                // Notify job seeker that their application was accepted
                NotificationManager.shared.sendApplicationAcceptedNotification(
                    application: application,
                    opportunityTitle: opportunity.title
                )
                
                // Notify hirer that they accepted the applicant
                NotificationManager.shared.sendHirerAcceptedNotification(
                    hirerId: opportunity.hirerId,
                    applicantName: application.applicantName,
                    opportunityId: opportunityId,
                    opportunityTitle: opportunity.title,
                    applicantImageData: application.applicantImageData
                )
            }
            
            // Create conversation for messaging
            Task { [weak self] in
                await self?.createConversationForAcceptedApplication(application)
            }
            
            completion?(true, nil)
        }
        
        // Reject all other pending applications for this opportunity
        let otherApplications = applications.filter {
            $0.opportunityId == opportunityId &&
            $0.id != applicationId &&
            $0.status == .pending
        }
        
        let batch = db.batch()
        for app in otherApplications {
            let docRef = db.collection("applications").document(app.id)
            batch.updateData(["status": ApplicationStatus.rejected.rawValue], forDocument: docRef)
        }
        
        batch.commit { error in
            if let error = error {
                print("❌ Error rejecting other applications: \(error.localizedDescription)")
            } else {
                print("✅ Rejected \(otherApplications.count) other applications")
                
                // Send rejection notifications
                if let opportunity = OpportunityManager.shared.opportunities.first(where: { $0.safeId == opportunityId }) {
                    for app in otherApplications {
                        NotificationManager.shared.sendApplicationRejectedNotification(
                            application: app,
                            opportunityTitle: opportunity.title
                        )
                    }
                }
            }
        }
    }
    
    // Complete job (hirer confirms done)
    /// Complete a job using the known application document ID (preferred — avoids listener gaps).
    func completeJob(opportunityId: String, applicationId: String) {
        OpportunityManager.shared.updateOpportunityStatus(
            opportunityId: opportunityId,
            status: .completed,
            acceptedApplicantId: nil
        )

        // Optimistic local update for the banner / banner card
        if let idx = applications.firstIndex(where: { $0.id == applicationId }) {
            var updated = applications
            updated[idx].status = .completed
            updated[idx].completedAt = Date()
            applications = updated
        }

        guard let db = db else {
            print("⚠️ ApplicationManager: Firebase not configured")
            return
        }

        db.collection("applications").document(applicationId).updateData([
            "status": ApplicationStatus.completed.rawValue,
            "completedAt": Timestamp(date: Date())
        ]) { error in
            if let error = error {
                print("❌ Error completing application: \(error.localizedDescription)")
            } else {
                print("✅ Job completed for opportunity \(opportunityId)")
            }
        }
    }

    /// Legacy overload for callers that don't have an explicit applicationId.
    func completeJob(opportunityId: String) {
        guard let app = applications.first(where: {
            $0.opportunityId == opportunityId && $0.status == .accepted
        }) else {
            OpportunityManager.shared.updateOpportunityStatus(opportunityId: opportunityId, status: .completed, acceptedApplicantId: nil)
            return
        }
        completeJob(opportunityId: opportunityId, applicationId: app.id)
    }

    /// Hirer's half of the dual confirmation. Writes the timestamp; finalize is
    /// triggered separately once both sides have confirmed.
    func markHirerConfirmedCompletion(applicationId: String, completion: @escaping (Bool) -> Void) {
        markConfirmedCompletion(applicationId: applicationId, field: "hirerConfirmedCompletionAt", apply: { app, date in
            var copy = app
            copy.hirerConfirmedCompletionAt = date
            return copy
        }, completion: completion)
    }

    /// Worker's half of the dual confirmation. Writes the timestamp; finalize is
    /// triggered separately once both sides have confirmed.
    func markWorkerConfirmedCompletion(applicationId: String, completion: @escaping (Bool) -> Void) {
        markConfirmedCompletion(applicationId: applicationId, field: "workerConfirmedCompletionAt", apply: { app, date in
            var copy = app
            copy.workerConfirmedCompletionAt = date
            return copy
        }, completion: completion)
    }

    private func markConfirmedCompletion(
        applicationId: String,
        field: String,
        apply: @escaping (JobApplication, Date) -> JobApplication,
        completion: @escaping (Bool) -> Void
    ) {
        let now = Date()

        // Optimistic local update so the current view recomputes immediately.
        if let idx = applications.firstIndex(where: { $0.id == applicationId }) {
            var updated = applications
            updated[idx] = apply(updated[idx], now)
            applications = updated
        }

        guard let db = db else {
            print("⚠️ ApplicationManager: Firebase not configured — confirmation only stored locally")
            DispatchQueue.main.async { completion(true) }
            return
        }

        db.collection("applications").document(applicationId).updateData([
            field: Timestamp(date: now)
        ]) { error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Error writing \(field): \(error.localizedDescription)")
                    completion(false)
                } else {
                    print("✅ \(field) recorded for application \(applicationId)")
                    completion(true)
                }
            }
        }
    }
    
    /// Result returned by `cancelApplication` so callers can surface a precise
    /// error to the user (today the function has no UI caller, but plumbing it
    /// through now prevents a future "tap to cancel" button from silently
    /// triggering the escrow-loophole path the guard below was added to block).
    enum CancelApplicationResult {
        case success
        case workerAlreadyConfirmedCompletion  // dispute required, refund blocked
        case applicationNotFound
        case firebaseUnavailable
        case firestoreError(String)
    }

    // Cancel application
    func cancelApplication(
        applicationId: String,
        completion: @escaping (CancelApplicationResult) -> Void = { _ in }
    ) {
        guard let application = applications.first(where: { $0.id == applicationId }) else {
            print("❌ Application not found for cancellation")
            completion(.applicationNotFound)
            return
        }

        // Escrow safety guard. Previously the hirer could:
        //   1. Wait for the worker to mark the job complete (sets
        //      `workerConfirmedCompletionAt`).
        //   2. Refuse to tap their own "Mark Complete" button.
        //   3. Cancel the application — which hit `autoRefundForCancelledApplication`
        //      below and pulled 100% of the escrow back to the hirer's card.
        // Net effect: free labour. We refuse the cancel once the worker has
        // confirmed, forcing the hirer down a dispute path (manual review or
        // confirm-and-release) instead of an automatic refund.
        if application.workerConfirmedCompletionAt != nil {
            print("⛔️ Refusing to cancel \(applicationId): worker has already confirmed completion. Use dispute flow.")
            completion(.workerAlreadyConfirmedCompletion)
            return
        }

        guard let db = db else {
            print("⚠️ ApplicationManager: Firebase not configured")
            completion(.firebaseUnavailable)
            return
        }

        db.collection("applications").document(applicationId).updateData([
            "status": ApplicationStatus.cancelled.rawValue
        ]) { error in
            if let error = error {
                print("❌ Error cancelling application: \(error.localizedDescription)")
                completion(.firestoreError(error.localizedDescription))
            } else {
                print("✅ Application cancelled")

                // If escrow was already held, refund automatically. Safe to do
                // because we've already gated this branch on the worker NOT
                // having confirmed completion above.
                PaymentManager.shared.autoRefundForCancelledApplication(
                    applicationId: application.id,
                    reason: "Job cancelled"
                )

                // Mark local payment fields on application.
                db.collection("applications").document(applicationId).updateData([
                    "isPaid": false,
                    "paidAt": NSNull()
                ]) { error in
                    if let error = error {
                        print("❌ Failed to clear isPaid after refund: \(error.localizedDescription)")
                    }
                }

                completion(.success)
            }
        }
    }
    
    // MARK: - Create Conversation
    
    private func createConversationForAcceptedApplication(_ application: JobApplication) async {
        let opportunity = OpportunityManager.shared.opportunities.first { $0.safeId == application.opportunityId }

        // Fall back to snapshots stored on the application if the opportunity
        // hasn't loaded yet or has already expired from the local array.
        let hirerId = opportunity?.hirerId ?? application.hirerIdSnapshot ?? ""
        let hirerName = opportunity?.hirerName ?? application.hirerNameSnapshot ?? "Hirer"
        let hirerImageData = opportunity?.hirerImageData

        guard !hirerId.isEmpty else {
            print("⚠️ Cannot create conversation: hirer ID unknown for application \(application.id)")
            return
        }

        let conversationId = await MessageManager.shared.createConversation(
            opportunityId: application.opportunityId,
            hirerId: hirerId,
            hirerName: hirerName,
            hirerImageData: hirerImageData,
            applicantId: application.applicantId,
            applicantName: application.applicantName,
            applicantImageData: application.applicantImageData
        )

        if conversationId != nil {
            print("✅ Conversation created for accepted application")
        }
    }
    
    // MARK: - Developer Tools
    
    /// Delete all applications from Firebase (for testing)
    func deleteAllApplications() async {
        guard let db = db else {
            print("⚠️ ApplicationManager: Firebase not configured")
            return
        }
        
        let collectionRef = db.collection("applications")
        let querySnapshot = try? await collectionRef.getDocuments()
        
        guard let documents = querySnapshot?.documents else {
            print("ℹ️ No applications to delete.")
            return
        }
        
        let batch = db.batch()
        for document in documents {
            batch.deleteDocument(document.reference)
        }
        
        do {
            try await batch.commit()
            print("✅ All applications deleted from Firestore.")
        } catch {
            print("❌ Error deleting all applications: \(error.localizedDescription)")
        }
    }
    
    /// Delete all applications for a specific user (for account deletion)
    func deleteAllApplications(for userId: String) async {
        guard let db = db else {
            print("⚠️ ApplicationManager: Firebase not configured")
            return
        }
        
        print("🗑️ Deleting all applications for user: \(userId)")
        
        do {
            // Delete applications where user is the applicant
            let applicantSnapshot = try await db.collection("applications")
                .whereField("applicantId", isEqualTo: userId)
                .getDocuments()
            
            // Delete applications where user is the hirer (via opportunityHirerId)
            let hirerSnapshot = try await db.collection("applications")
                .whereField("opportunityHirerId", isEqualTo: userId)
                .getDocuments()
            
            let totalCount = applicantSnapshot.documents.count + hirerSnapshot.documents.count
            print("📋 Found \(totalCount) applications to delete for user")
            
            var affectedOpportunityIds = Set<String>()
            for document in applicantSnapshot.documents {
                if let oid = document.data()["opportunityId"] as? String { affectedOpportunityIds.insert(oid) }
            }
            for document in hirerSnapshot.documents {
                if let oid = document.data()["opportunityId"] as? String { affectedOpportunityIds.insert(oid) }
            }
            
            // Delete in batches
            let batch = db.batch()
            for document in applicantSnapshot.documents {
                batch.deleteDocument(document.reference)
            }
            for document in hirerSnapshot.documents {
                batch.deleteDocument(document.reference)
            }
            
            try await batch.commit()
            
            for oid in affectedOpportunityIds {
                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    OpportunityManager.shared.recalculateApplicantCount(opportunityId: oid) { _ in
                        cont.resume()
                    }
                }
            }
            
            print("✅ Successfully deleted user's applications from Firestore")
        } catch {
            print("❌ Error deleting user's applications: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Job Completion
    
    /// Mark application as completed
    func markAsCompleted(applicationId: String, notes: String? = nil, completion: @escaping (Bool) -> Void) {
        guard let db = db else {
            print("⚠️ ApplicationManager: Firebase not configured")
            completion(false)
            return
        }
        
        var updateData: [String: Any] = [
            "status": ApplicationStatus.completed.rawValue,
            "completedAt": Timestamp(date: Date())
        ]
        
        if let notes = notes {
            updateData["completionNotes"] = notes
        }
        
        db.collection("applications").document(applicationId).updateData(updateData) { [weak self] error in
            if let error = error {
                print("❌ Error marking application complete: \(error.localizedDescription)")
                completion(false)
                return
            }
            
            print("✅ Application marked as completed")
            
            // Update opportunity status to completed
            if let application = self?.applications.first(where: { $0.id == applicationId }) {
                OpportunityManager.shared.updateOpportunityStatus(
                    opportunityId: application.opportunityId,
                    status: .completed,
                    acceptedApplicantId: nil
                )
            }
            
            completion(true)
        }
    }
    
    // MARK: - Profile Sync
    
    func updateApplicantProfile(userId: String, name: String, imageData: Data?) async {
        guard let db = db else {
            print("⚠️ ApplicationManager: Firebase not configured")
            return
        }
        
        print("🔄 Updating applicant profile in applications for user: \(userId)")
        
        // Get all applications from this user
        let userApplications = applications.filter { $0.applicantId == userId }
        
        for application in userApplications {
            var updateData: [String: Any] = [
                "applicantName": name
            ]
            
            if let imageData = imageData {
                updateData["applicantImageData"] = imageData
            }
            
            do {
                try await db.collection("applications").document(application.id).updateData(updateData)
                print("✅ Updated application \(application.id) with new applicant profile")
            } catch {
                print("❌ Error updating application \(application.id): \(error.localizedDescription)")
            }
        }
        
        print("✅ Updated \(userApplications.count) applications with new profile")
    }
}

// MARK: - Models

struct JobApplication: Identifiable, Codable {
    let id: String
    let opportunityId: String
    let applicantId: String
    let applicantName: String
    let applicantImageData: Data?
    var status: ApplicationStatus
    let appliedAt: Date
    var acceptedAt: Date?
    var completedAt: Date?
    var hirerConfirmedCompletionAt: Date?
    var workerConfirmedCompletionAt: Date?
    let message: String?
    var paymentId: String?      // Link to payment record
    var isPaid: Bool?            // Whether payment has been sent
    var paidAt: Date?            // When payment was made
    let opportunityTitleSnapshot: String?
    let opportunityJobTypeSnapshot: String?
    let opportunityLocationNameSnapshot: String?
    /// Coordinate snapshot taken at apply-time. Lets the worker show the
    /// destination on the in-progress map even after the opportunity
    /// transitions out of `.open` and is no longer readable from
    /// `OpportunityManager.opportunities`. Both nil for pre-2026-05-07
    /// applications — call sites must tolerate missing values.
    let opportunityLocationLatitudeSnapshot: Double?
    let opportunityLocationLongitudeSnapshot: Double?
    let hirerIdSnapshot: String?
    let hirerNameSnapshot: String?
    
    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: appliedAt, relativeTo: Date())
    }
}

enum ApplicationStatus: String, Codable {
    case pending = "pending"
    case accepted = "accepted"
    case rejected = "rejected"
    case completed = "completed"
    case cancelled = "cancelled"
}

/// Aggregated counts for any user's profile, fetched directly from Firestore so
/// the numbers don't depend on the *viewer's* local listener cache (which only
/// holds the viewer's own applications).
struct ProfileApplicationCounts {
    var completedAsApplicant: Int = 0
    var helpedAsApplicant: Int = 0   // accepted + completed
    var completedAsHirer: Int = 0
}

extension ApplicationManager {
    func fetchProfileApplicationCounts(
        forUserId userId: String,
        completion: @escaping (ProfileApplicationCounts) -> Void
    ) {
        guard let db = db else {
            DispatchQueue.main.async { completion(ProfileApplicationCounts()) }
            return
        }

        var counts = ProfileApplicationCounts()
        let group = DispatchGroup()

        group.enter()
        db.collection("applications")
            .whereField("applicantId", isEqualTo: userId)
            .getDocuments { snapshot, _ in
                for doc in snapshot?.documents ?? [] {
                    guard let raw = doc.data()["status"] as? String,
                          let status = ApplicationStatus(rawValue: raw) else { continue }
                    if status == .completed { counts.completedAsApplicant += 1 }
                    if status == .accepted || status == .completed { counts.helpedAsApplicant += 1 }
                }
                group.leave()
            }

        group.enter()
        db.collection("applications")
            .whereField("hirerIdSnapshot", isEqualTo: userId)
            .whereField("status", isEqualTo: ApplicationStatus.completed.rawValue)
            .getDocuments { snapshot, _ in
                counts.completedAsHirer = snapshot?.documents.count ?? 0
                group.leave()
            }

        group.notify(queue: .main) { completion(counts) }
    }

    /// How `currentUserId` and `otherUserId` have worked together. `nil` if
    /// they haven't yet. Direction is from the *current user's* point of view:
    /// `.theyWorkedForMe` shows up for hirers viewing past applicants;
    /// `.iWorkedForThem` shows up for seekers viewing past hirers.
    /// Counts only *completed* jobs to avoid showing the badge mid-flow.
    enum WorkRelationship {
        case theyWorkedForMe(count: Int)
        case iWorkedForThem(count: Int)
    }

    func workRelationship(currentUserId: String, otherUserId: String) -> WorkRelationship? {
        guard !currentUserId.isEmpty, !otherUserId.isEmpty,
              currentUserId != otherUserId else { return nil }

        let theyWorkedForMe = applications.filter {
            $0.applicantId == otherUserId
                && $0.status == .completed
                && hirerId(for: $0) == currentUserId
        }.count

        let iWorkedForThem = applications.filter {
            $0.applicantId == currentUserId
                && $0.status == .completed
                && hirerId(for: $0) == otherUserId
        }.count

        if theyWorkedForMe > 0 { return .theyWorkedForMe(count: theyWorkedForMe) }
        if iWorkedForThem > 0 { return .iWorkedForThem(count: iWorkedForThem) }
        return nil
    }

    /// Hirer id for an application — prefers the live opportunity (so renames
    /// land), falls back to the snapshot stored on the application itself
    /// (which is what gets indexed in Firestore queries anyway).
    private func hirerId(for app: JobApplication) -> String? {
        OpportunityManager.shared.opportunities.first { $0.safeId == app.opportunityId }?.hirerId
            ?? app.hirerIdSnapshot
    }
}

// MARK: - Worked-together badge

/// Compact pill that surfaces the "you've worked with this person before"
/// relationship anywhere a profile is rendered (applicants list, opportunity
/// "Posted by", etc.). Renders nothing when no relationship exists, so call
/// sites can drop it in unconditionally.
struct WorkedTogetherBadge: View {
    let currentUserId: String?
    let otherUserId: String
    @ObservedObject private var appManager = ApplicationManager.shared

    private var label: String? {
        guard let me = currentUserId,
              let rel = appManager.workRelationship(currentUserId: me, otherUserId: otherUserId)
        else { return nil }
        switch rel {
        case .theyWorkedForMe(let n):
            return n == 1 ? "Worked for you before" : "Worked for you \(n)×"
        case .iWorkedForThem(let n):
            return n == 1 ? "You worked for them before" : "You worked for them \(n)×"
        }
    }

    var body: some View {
        if let text = label {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 11, weight: .bold))
                Text(text)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(CommunallyTheme.primaryGreen)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(CommunallyTheme.primaryGreen.opacity(0.12)))
            .overlay(Capsule().stroke(CommunallyTheme.primaryGreen.opacity(0.30), lineWidth: 1))
        }
    }
}
