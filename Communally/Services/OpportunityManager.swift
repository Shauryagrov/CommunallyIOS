//
//  OpportunityManager.swift
//  Communally
//
//  Manages job opportunities with Firebase Firestore
//

import Foundation
import SwiftUI
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
    
    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    
    private init() {
        // Start listening to Firestore for real-time updates
        startListening()
    }
    
    deinit {
        listener?.remove()
    }
    
    // MARK: - Firestore Methods
    
    /// Start listening for real-time updates from Firestore
    private func startListening() {
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
            }
    }
    
    /// Fetch opportunities once (useful for initial load or refresh)
    func fetchOpportunities() async {
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
        hirerImageData: Data?
    ) {
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
            acceptedApplicantId: nil
        )
        
        // Save to Firestore
        do {
            try db.collection("opportunities").document(opportunityId).setData(from: opportunity)
            print("✅ Posted opportunity to Firestore: \(title)")
            print("🔍 Opportunity ID: \(opportunityId)")
            print("👤 Hirer: \(hirerName) (\(hirerId))")
            
            // Send notification to all job seekers
            NotificationManager.shared.sendNewOpportunityNotification(opportunity: opportunity)
        } catch {
            print("❌ Error posting opportunity: \(error.localizedDescription)")
        }
        
        // Note: The listener will automatically update the local array
    }
    
    func getUserOpportunities(userId: String) -> [Opportunity] {
        return opportunities.filter { $0.hirerId == userId }
    }
    
    func getAllActiveOpportunities() -> [Opportunity] {
        return opportunities.filter { $0.isActive }
    }
    
    func deleteOpportunity(id: String) {
        db.collection("opportunities").document(id).delete { error in
            if let error = error {
                print("❌ Error deleting opportunity: \(error.localizedDescription)")
            } else {
                print("✅ Deleted opportunity: \(id)")
            }
        }
        // The listener will automatically update the local array
    }
    
    func toggleOpportunityStatus(id: String) {
        guard let opportunity = opportunities.first(where: { $0.safeId == id }) else { return }
        
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
    }
    
    // Safe id access - returns the id or a fallback
    var safeId: String {
        return id ?? UUID().uuidString
    }
    
    var displayPay: String {
        if isVolunteer {
            return "Volunteer"
        } else if let amount = payAmount, !amount.isEmpty {
            return "$\(amount)"
        } else {
            return "Negotiable"
        }
    }
    
    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: createdAt, relativeTo: Date())
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

