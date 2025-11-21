//
//  ApplicationManager.swift
//  Communally
//
//  Manages job applications and workflow
//

import Foundation
import SwiftUI
import FirebaseFirestore

class ApplicationManager: ObservableObject {
    static let shared = ApplicationManager()
    
    @Published var applications: [JobApplication] = []
    
    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    
    private init() {
        startListening()
    }
    
    deinit {
        listener?.remove()
    }
    
    // Real-time sync with Firebase
    private func startListening() {
        listener = db.collection("applications")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ Error listening to applications: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    print("ℹ️ No applications found")
                    return
                }
                
                self.applications = documents.compactMap { doc -> JobApplication? in
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
                    let message = data["message"] as? String
                    
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
                        message: message
                    )
                }
                
                print("✅ Synced \(self.applications.count) applications from Firebase")
            }
    }
    
    // Submit application
    func applyToOpportunity(opportunityId: String, applicantId: String, applicantName: String, applicantImageData: Data?) {
        // Check if already applied
        if hasApplied(opportunityId: opportunityId, applicantId: applicantId) {
            print("⚠️ User already applied to this opportunity")
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
            "message": NSNull()
        ]
        
        // Save to Firebase
        db.collection("applications").document(applicationId).setData(applicationData) { error in
            if let error = error {
                print("❌ Error submitting application: \(error.localizedDescription)")
            } else {
                print("✅ Application submitted by \(applicantName)")
                
                // Update opportunity applicant count
                OpportunityManager.shared.incrementApplicantCount(opportunityId: opportunityId)
                
                // Get the opportunity to send notification to hirer
                if let opportunity = OpportunityManager.shared.opportunities.first(where: { $0.safeId == opportunityId }) {
                    // Create temporary application for notification
                    let tempApplication = JobApplication(
                        id: applicationId,
                        opportunityId: opportunityId,
                        applicantId: applicantId,
                        applicantName: applicantName,
                        applicantImageData: applicantImageData,
                        status: .pending,
                        appliedAt: Date(),
                        message: nil
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
    
    // Accept application (hirer chooses someone)
    func acceptApplication(applicationId: String) {
        guard let application = applications.first(where: { $0.id == applicationId }) else {
            print("❌ Application not found")
            return
        }
        
        let opportunityId = application.opportunityId
        
        // Update this application to accepted in Firebase
        db.collection("applications").document(applicationId).updateData([
            "status": ApplicationStatus.accepted.rawValue,
            "acceptedAt": Timestamp(date: Date())
        ]) { [weak self] error in
            if let error = error {
                print("❌ Error accepting application: \(error.localizedDescription)")
                return
            }
            
            print("✅ Application accepted for opportunity \(opportunityId)")
            
            // Update opportunity status to in progress
            OpportunityManager.shared.updateOpportunityStatus(
                opportunityId: opportunityId,
                status: .inProgress,
                acceptedApplicantId: application.applicantId
            )
            
            // Send notification to accepted applicant
            if let opportunity = OpportunityManager.shared.opportunities.first(where: { $0.safeId == opportunityId }) {
                NotificationManager.shared.sendApplicationAcceptedNotification(
                    application: application,
                    opportunityTitle: opportunity.title
                )
            }
            
            // Create conversation for messaging
            Task { [weak self] in
                await self?.createConversationForAcceptedApplication(application)
            }
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
    func completeJob(opportunityId: String) {
        // Mark opportunity as completed
        OpportunityManager.shared.updateOpportunityStatus(
            opportunityId: opportunityId,
            status: .completed,
            acceptedApplicantId: nil
        )
        
        // Update application status in Firebase
        if let application = applications.first(where: {
            $0.opportunityId == opportunityId && $0.status == .accepted
        }) {
            db.collection("applications").document(application.id).updateData([
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
    }
    
    // Cancel application
    func cancelApplication(applicationId: String) {
        db.collection("applications").document(applicationId).updateData([
            "status": ApplicationStatus.cancelled.rawValue
        ]) { error in
            if let error = error {
                print("❌ Error cancelling application: \(error.localizedDescription)")
            } else {
                print("✅ Application cancelled")
            }
        }
    }
    
    // MARK: - Create Conversation
    
    private func createConversationForAcceptedApplication(_ application: JobApplication) async {
        // Get opportunity details
        let opportunity = OpportunityManager.shared.opportunities.first { $0.safeId == application.opportunityId }
        
        guard let opp = opportunity else {
            print("⚠️ Opportunity not found for conversation creation")
            return
        }
        
        // Create conversation
        let conversationId = await MessageManager.shared.createConversation(
            opportunityId: opp.safeId,
            hirerId: opp.hirerId,
            hirerName: opp.hirerName,
            hirerImageData: opp.hirerImageData,
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
    let message: String?
    
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

