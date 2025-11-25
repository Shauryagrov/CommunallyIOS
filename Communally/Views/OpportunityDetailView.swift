//
//  OpportunityDetailView.swift
//  Communally
//
//  Detail view for opportunities with apply/manage options
//

import SwiftUI
import MapKit

struct OpportunityDetailView: View {
    let opportunity: Opportunity
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authManager: AuthenticationManager
    @ObservedObject private var applicationManager = ApplicationManager.shared
    @ObservedObject private var opportunityManager = OpportunityManager.shared
    @ObservedObject private var ratingManager = RatingManager.shared
    
    @State private var showingApplicants = false
    @State private var showingCompletionConfirm = false
    @State private var selectedApplicant: JobApplication?
    @State private var showingAcceptConfirm = false
    @State private var showingRatingView = false
    @State private var acceptedJobSeeker: JobApplication?
    
    private var isHirer: Bool {
        authManager.currentUser?.id == opportunity.hirerId
    }
    
    private var hasApplied: Bool {
        guard let userId = authManager.currentUser?.id else { return false }
        return applicationManager.hasApplied(opportunityId: opportunity.safeId, applicantId: userId)
    }
    
    private var pendingApplications: [JobApplication] {
        applicationManager.getPendingApplications(forOpportunity: opportunity.safeId)
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Combined Header with Posted By
                    combinedHeaderSection
                    
                    // Pay Info
                    payInfoSection
                    
                    // Description
                    descriptionSection
                    
                    // Location
                    locationSection
                    
                    // Applications (for hirer)
                    if isHirer && opportunity.status == .open {
                        applicationsSection
                    }
                    
                    // Hirer action buttons (in scroll view)
                    if isHirer {
                        hirerActionButtons
                    }
                    
                    // Extra space at bottom for floating button
                    Spacer(minLength: 120)
                }
                .padding(20)
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
            
            // Floating Apply Button for Job Seekers (sticky at bottom)
            if !isHirer {
                floatingApplyButton
            }
        }
        .navigationTitle("Opportunity Details")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingApplicants) {
            ApplicantsListView(opportunity: opportunity)
        }
        .alert("Complete Job?", isPresented: $showingCompletionConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Complete") {
                completeJob()
            }
        } message: {
            Text("Mark this job as completed?")
        }
        .sheet(isPresented: $showingRatingView) {
            if let jobSeeker = acceptedJobSeeker {
                RateUserView(opportunity: opportunity, jobSeeker: jobSeeker)
                    .environmentObject(authManager)
            }
        }
        .onAppear {
            loadAcceptedJobSeeker()
        }
    }
    
    // MARK: - Combined Header Section
    private var combinedHeaderSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Title and Job Type Icon
            HStack(spacing: 14) {
                // Job type icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.6, green: 0.4, blue: 1.0),
                                    Color(red: 0.7, green: 0.5, blue: 1.0)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                        .shadow(color: Color(red: 0.6, green: 0.4, blue: 1.0).opacity(0.3), radius: 8, x: 0, y: 4)
                    
                    Image(systemName: iconForJobType(opportunity.jobType))
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(opportunity.title)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 0.15, green: 0.15, blue: 0.15))
                    
                    Text(opportunity.jobType)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                }
                
                Spacer()
            }
            
            // Posted by section
            HStack(spacing: 12) {
                // Profile picture
                if let imageData = opportunity.hirerImageData,
                   let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color(red: 0.9, green: 0.9, blue: 0.9), lineWidth: 2)
                        )
                } else {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.95, green: 0.95, blue: 0.95))
                            .frame(width: 40, height: 40)
                        
                        Image(systemName: "person.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(Color(red: 0.6, green: 0.6, blue: 0.6))
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Posted by")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                    
                    Text(opportunity.hirerName)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(Color(red: 0.2, green: 0.2, blue: 0.2))
                }
                
                Spacer()
                
                // Time posted
                Text(opportunity.timeAgo)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 2)
            )
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 6)
        )
    }
    
    // MARK: - Old Status Badge (not used)
    private var statusBadge: some View {
        HStack(spacing: 12) {
            // Profile picture
            if let imageData = opportunity.hirerImageData,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.6, green: 0.4, blue: 1.0),
                                        Color(red: 0.7, green: 0.5, blue: 1.0)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    )
            } else {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.6, green: 0.4, blue: 1.0).opacity(0.2),
                                    Color(red: 0.7, green: 0.5, blue: 1.0).opacity(0.2)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "person.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(Color(red: 0.6, green: 0.4, blue: 1.0))
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Posted by")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                
                Text(opportunity.hirerName)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 0.15, green: 0.15, blue: 0.15))
            }
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: Color(red: 0.6, green: 0.4, blue: 1.0).opacity(0.1), radius: 10, x: 0, y: 4)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
    }
    
    // MARK: - Pay Info Section
    private var payInfoSection: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(opportunity.isVolunteer ? Color.red.opacity(0.1) : Color(red: 0.6, green: 0.4, blue: 1.0).opacity(0.1))
                    .frame(width: 50, height: 50)
                
                Image(systemName: opportunity.isVolunteer ? "heart.fill" : "dollarsign.circle.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(opportunity.isVolunteer ? .red : Color(red: 0.6, green: 0.4, blue: 1.0))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Compensation")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                
                Text(opportunity.displayPay)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 0.15, green: 0.15, blue: 0.15))
            }
            
            Spacer()
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
        )
    }
    
    // MARK: - Description Section
    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(red: 0.6, green: 0.4, blue: 1.0))
                
                Text("Description")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 0.15, green: 0.15, blue: 0.15))
            }
            
            Text(opportunity.description)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundColor(Color(red: 0.3, green: 0.3, blue: 0.3))
                .lineSpacing(4)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
        )
    }
    
    // MARK: - Location Section
    private var locationSection: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.6, green: 0.4, blue: 1.0).opacity(0.1))
                    .frame(width: 50, height: 50)
                
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(Color(red: 0.6, green: 0.4, blue: 1.0))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Location")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                
                Text(opportunity.locationName)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(red: 0.15, green: 0.15, blue: 0.15))
            }
            
            Spacer()
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
        )
    }
    
    // MARK: - Applications Section
    private var applicationsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.6, green: 0.4, blue: 1.0).opacity(0.1))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(Color(red: 0.6, green: 0.4, blue: 1.0))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Applications")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 0.15, green: 0.15, blue: 0.15))
                    
                    Text("\(opportunity.applicantCount) \(opportunity.applicantCount == 1 ? "applicant" : "applicants")")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                }
                
                Spacer()
            }
            
            if opportunity.applicantCount == 0 {
                // Empty state with better design
                VStack(spacing: 12) {
                    Image(systemName: "person.2.slash.fill")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundColor(Color(red: 0.7, green: 0.7, blue: 0.7))
                    
                    Text("No applications yet")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                    
                    Text("Applications will appear here when job seekers apply")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundColor(Color(red: 0.6, green: 0.6, blue: 0.6))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .padding(.horizontal, 24)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
                )
            } else {
                // Show applicants inline
                VStack(spacing: 12) {
                    ForEach(pendingApplications) { application in
                        InlineApplicantCard(
                            application: application,
                            onAccept: {
                                selectedApplicant = application
                                showingAcceptConfirm = true
                            }
                        )
                    }
                }
            }
        }
        .alert("Accept Applicant?", isPresented: $showingAcceptConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Accept", role: .destructive) {
                if let applicant = selectedApplicant {
                    let impactMed = UIImpactFeedbackGenerator(style: .medium)
                    impactMed.impactOccurred()
                    acceptApplicant(applicant)
                }
            }
        } message: {
            if let applicant = selectedApplicant {
                Text("Accept \(applicant.applicantName) for this job?\n\nAll other applications will be automatically rejected and the opportunity will close to new applicants.")
            }
        }
    }
    
    // MARK: - Floating Apply Button (Job Seekers)
    private var floatingApplyButton: some View {
        VStack(spacing: 0) {
            if opportunity.status == .open && !hasApplied {
                // Apply button - Clean and prominent
                Button(action: {
                    applyToJob()
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 20, weight: .semibold))
                        
                        Text("Apply for This Job")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                CommunallyTheme.primaryGreen,
                                CommunallyTheme.secondaryGreen
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(16)
                    .shadow(color: CommunallyTheme.primaryGreen.opacity(0.4), radius: 15, x: 0, y: 8)
                }
                .pulsingButton()
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.clear,
                            Color.white.opacity(0.8),
                            Color.white
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 100)
                    .ignoresSafeArea()
                )
            } else if hasApplied {
                // Already applied status
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(CommunallyTheme.primaryGreen)
                    
                    Text("Application Submitted ✓")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(CommunallyTheme.darkGray)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(CommunallyTheme.primaryGreen.opacity(0.15))
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .background(
                    Color.white
                        .ignoresSafeArea()
                )
            }
        }
    }
    
    // MARK: - Hirer Action Buttons
    private var hirerActionButtons: some View {
        VStack(spacing: 12) {
            if isHirer && opportunity.status == .inProgress {
                // Complete job button
                Button(action: {
                    showingCompletionConfirm = true
                }) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                        
                        Text(opportunity.isVolunteer ? "Mark as Complete" : "Complete & Pay")
                            .font(CommunallyTheme.bodyFont)
                            .fontWeight(.bold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                CommunallyTheme.primaryGreen,
                                CommunallyTheme.secondaryGreen
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
                    .shadow(color: CommunallyTheme.primaryGreen.opacity(0.3), radius: 12, x: 0, y: 6)
                }
            }
        }
    }
    
    // MARK: - Helper Functions
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
    
    private func applyToJob() {
        guard let user = authManager.currentUser else { return }
        
        applicationManager.applyToOpportunity(
            opportunityId: opportunity.safeId,
            applicantId: user.id,
            applicantName: user.fullName,
            applicantImageData: user.profileImageData
        )
        
        print("✅ Applied to job: \(opportunity.title)")
    }
    
    private func completeJob() {
        applicationManager.completeJob(opportunityId: opportunity.safeId)
        
        // Show rating view after completion
        if acceptedJobSeeker != nil {
            // Check if not already rated
            if !ratingManager.hasRated(opportunityId: opportunity.safeId, raterId: authManager.currentUser?.id ?? "") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showingRatingView = true
                }
            } else {
                dismiss()
            }
        } else {
            dismiss()
        }
    }
    
    private func acceptApplicant(_ application: JobApplication) {
        applicationManager.acceptApplication(applicationId: application.id)
        acceptedJobSeeker = application
        print("✅ Accepted applicant: \(application.applicantName)")
    }
    
    private func loadAcceptedJobSeeker() {
        if opportunity.status == .inProgress || opportunity.status == .completed {
            if let acceptedId = opportunity.acceptedApplicantId {
                acceptedJobSeeker = applicationManager.applications.first {
                    $0.opportunityId == opportunity.safeId && $0.applicantId == acceptedId
                }
            }
        }
    }
}

// MARK: - Inline Applicant Card
struct InlineApplicantCard: View {
    let application: JobApplication
    let onAccept: () -> Void
    
    var body: some View {
        HStack(spacing: 14) {
            // Profile picture
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.6, green: 0.4, blue: 1.0),
                                Color(red: 0.7, green: 0.5, blue: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                
                if let imageData = application.applicantImageData,
                   let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 52, height: 52)
                        .clipShape(Circle())
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.white)
                }
            }
            
            // Applicant info
            VStack(alignment: .leading, spacing: 4) {
                Text(application.applicantName)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 0.15, green: 0.15, blue: 0.15))
                
                HStack(spacing: 6) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(red: 0.6, green: 0.4, blue: 1.0))
                    
                    Text("Applied \(application.timeAgo)")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                }
            }
            
            Spacer()
            
            // Accept button
            Button(action: {
                let impactMed = UIImpactFeedbackGenerator(style: .medium)
                impactMed.impactOccurred()
                onAccept()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                    
                    Text("Accept")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.6, green: 0.4, blue: 1.0),
                            Color(red: 0.7, green: 0.5, blue: 1.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(20)
                .shadow(color: Color(red: 0.6, green: 0.4, blue: 1.0).opacity(0.4), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: Color(red: 0.6, green: 0.4, blue: 1.0).opacity(0.1), radius: 10, x: 0, y: 4)
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        )
    }
}

#Preview {
    NavigationView {
        OpportunityDetailView(opportunity: Opportunity(
            id: "1",
            title: "Gardening Needed",
            description: "Need help with lawn mowing and weeding",
            hirerId: "hirer123",
            hirerName: "John Smith",
            hirerImageData: nil,
            location: Location(latitude: 37.7749, longitude: -122.4194, address: "San Francisco"),
            locationName: "San Francisco, CA",
            isVolunteer: false,
            payAmount: "50",
            jobType: "Gardening",
            createdAt: Date(),
            isActive: true,
            applicantCount: 3,
            status: .open,
            acceptedApplicantId: nil
        ))
    }
    .environmentObject(AuthenticationManager.shared)
}

