//
//  MyApplicationsView.swift
//  Communally
//
//  View for job seekers to track their applications
//

import SwiftUI

struct MyApplicationsView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @ObservedObject private var applicationManager = ApplicationManager.shared
    @ObservedObject private var opportunityManager = OpportunityManager.shared
    @State private var selectedOpportunity: Opportunity?
    
    private var myApplications: [JobApplication] {
        guard let userId = authManager.currentUser?.id else { return [] }
        return applicationManager.getApplications(byUser: userId)
            .sorted { $0.appliedAt > $1.appliedAt } // Most recent first
    }
    
    private var pendingApplications: [JobApplication] {
        myApplications.filter { $0.status == .pending }
    }
    
    private var acceptedApplications: [JobApplication] {
        myApplications.filter { $0.status == .accepted }
    }
    
    private var otherApplications: [JobApplication] {
        myApplications.filter { $0.status == .rejected || $0.status == .completed }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Accepted Applications (Most Important)
                    if !acceptedApplications.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(Color(red: 0.3, green: 0.8, blue: 0.4))
                                
                                Text("Accepted")
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundColor(Color(red: 0.15, green: 0.15, blue: 0.15))
                                
                                Spacer()
                                
                                Text("\(acceptedApplications.count)")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule()
                                            .fill(Color(red: 0.3, green: 0.8, blue: 0.4))
                                    )
                            }
                            
                            ForEach(acceptedApplications) { application in
                                ApplicationStatusCard(
                                    application: application,
                                    opportunity: getOpportunity(for: application),
                                    onTap: {
                                        selectedOpportunity = getOpportunity(for: application)
                                    }
                                )
                            }
                        }
                    }
                    
                    // Pending Applications
                    if !pendingApplications.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 10) {
                                Image(systemName: "clock.fill")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(Color(red: 1.0, green: 0.7, blue: 0.2))
                                
                                Text("Pending")
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundColor(Color(red: 0.15, green: 0.15, blue: 0.15))
                                
                                Spacer()
                                
                                Text("\(pendingApplications.count)")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule()
                                            .fill(Color(red: 1.0, green: 0.7, blue: 0.2))
                                    )
                            }
                            
                            ForEach(pendingApplications) { application in
                                ApplicationStatusCard(
                                    application: application,
                                    opportunity: getOpportunity(for: application),
                                    onTap: {
                                        selectedOpportunity = getOpportunity(for: application)
                                    }
                                )
                            }
                        }
                    }
                    
                    // Past Applications (Rejected/Completed)
                    if !otherApplications.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 10) {
                                Image(systemName: "archivebox.fill")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundColor(Color(red: 0.6, green: 0.6, blue: 0.6))
                                
                                Text("Past Applications")
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundColor(Color(red: 0.15, green: 0.15, blue: 0.15))
                                
                                Spacer()
                                
                                Text("\(otherApplications.count)")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule()
                                            .fill(Color(red: 0.6, green: 0.6, blue: 0.6))
                                    )
                            }
                            
                            ForEach(otherApplications) { application in
                                ApplicationStatusCard(
                                    application: application,
                                    opportunity: getOpportunity(for: application),
                                    onTap: {
                                        selectedOpportunity = getOpportunity(for: application)
                                    }
                                )
                            }
                        }
                    }
                    
                    // Empty state
                    if myApplications.isEmpty {
                        VStack(spacing: 20) {
                            Spacer()
                            
                            ZStack {
                                Circle()
                                    .fill(Color(red: 0.6, green: 0.4, blue: 1.0).opacity(0.1))
                                    .frame(width: 100, height: 100)
                                
                                Image(systemName: "doc.text.magnifyingglass")
                                    .font(.system(size: 50, weight: .medium))
                                    .foregroundColor(Color(red: 0.6, green: 0.4, blue: 1.0))
                            }
                            
                            Text("No Applications Yet")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundColor(Color(red: 0.15, green: 0.15, blue: 0.15))
                            
                            Text("Apply to opportunities on the map\nto start tracking your applications")
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                                .multilineTextAlignment(.center)
                                .lineSpacing(4)
                            
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    }
                    
                    Spacer(minLength: 100)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.97, green: 0.99, blue: 0.95),
                        Color.white,
                        Color(red: 0.98, green: 1.0, blue: 0.96)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .navigationTitle("My Applications")
            .navigationBarTitleDisplayMode(.large)
            .sheet(item: $selectedOpportunity) { opportunity in
                NavigationView {
                    OpportunityDetailView(opportunity: opportunity)
                }
            }
        }
    }
    
    private func getOpportunity(for application: JobApplication) -> Opportunity? {
        return opportunityManager.opportunities.first { $0.safeId == application.opportunityId }
    }
}

// MARK: - Application Status Card
struct ApplicationStatusCard: View {
    let application: JobApplication
    let opportunity: Opportunity?
    let onTap: () -> Void
    
    private var statusColor: Color {
        switch application.status {
        case .pending: return Color(red: 1.0, green: 0.7, blue: 0.2)
        case .accepted: return Color(red: 0.3, green: 0.8, blue: 0.4)
        case .rejected: return Color(red: 0.9, green: 0.3, blue: 0.3)
        case .completed: return Color(red: 0.4, green: 0.6, blue: 1.0)
        case .cancelled: return Color(red: 0.6, green: 0.6, blue: 0.6)
        }
    }
    
    private var statusIcon: String {
        switch application.status {
        case .pending: return "clock.fill"
        case .accepted: return "checkmark.seal.fill"
        case .rejected: return "xmark.circle.fill"
        case .completed: return "star.fill"
        case .cancelled: return "slash.circle.fill"
        }
    }
    
    private var statusText: String {
        switch application.status {
        case .pending: return "Pending Review"
        case .accepted: return "Accepted! 🎉"
        case .rejected: return "Not Selected"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        }
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack(spacing: 12) {
                    // Job type icon
                    if let opp = opportunity {
                        ZStack {
                            Circle()
                                .fill(statusColor.opacity(0.2))
                                .frame(width: 50, height: 50)
                            
                            Image(systemName: iconForJobType(opp.jobType))
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(statusColor)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(opp.title)
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundColor(Color(red: 0.15, green: 0.15, blue: 0.15))
                                .lineLimit(1)
                            
                            HStack(spacing: 6) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(statusColor)
                                
                                Text(opp.locationName)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                                    .lineLimit(1)
                            }
                        }
                    } else {
                        // Opportunity not found
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Opportunity Unavailable")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                            
                            Text("This posting has been removed")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundColor(Color(red: 0.6, green: 0.6, blue: 0.6))
                        }
                    }
                    
                    Spacer()
                }
                
                // Divider
                Rectangle()
                    .fill(Color(red: 0.9, green: 0.9, blue: 0.9))
                    .frame(height: 1)
                
                // Status and time
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: statusIcon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(statusColor)
                        
                        Text(statusText)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(statusColor)
                    }
                    
                    Spacer()
                    
                    Text("Applied \(application.timeAgo)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                }
                
                // Special message for accepted applications
                if application.status == .accepted, opportunity != nil {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.bubble.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color(red: 0.3, green: 0.8, blue: 0.4))
                        
                        Text("The hirer has accepted you! Tap to view details and contact information.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(Color(red: 0.2, green: 0.2, blue: 0.2))
                            .lineSpacing(3)
                        
                        Spacer()
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(red: 0.3, green: 0.8, blue: 0.4).opacity(0.1))
                    )
                }
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.white)
                    .shadow(color: statusColor.opacity(0.15), radius: 12, x: 0, y: 6)
                    .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func iconForJobType(_ type: String) -> String {
        switch type.lowercased() {
        case "gardening": return "leaf.fill"
        case "pet care": return "pawprint.fill"
        case "tutoring": return "book.fill"
        case "moving help": return "box.truck.fill"
        case "painting": return "paintbrush.fill"
        case "babysitting": return "figure.2.and.child.holdinghands"
        case "event help": return "calendar.badge.plus"
        case "cleaning": return "sparkles"
        case "delivery": return "shippingbox.fill"
        default: return "briefcase.fill"
        }
    }
}

#Preview {
    MyApplicationsView()
        .environmentObject(AuthenticationManager.shared)
}

