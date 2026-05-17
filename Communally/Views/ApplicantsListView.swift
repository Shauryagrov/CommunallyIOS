//
//  ApplicantsListView.swift
//  Communally
//
//  View for hirers to see and accept applicants
//

import SwiftUI

struct ApplicantsListView: View {
    let opportunity: Opportunity
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var applicationManager = ApplicationManager.shared
    @ObservedObject private var ratingManager = RatingManager.shared
    
    @State private var selectedApplicant: JobApplication?
    @State private var showingAcceptConfirm = false
    @State private var paymentError: String?
    @State private var showPaymentError = false
    
    private var pendingApplications: [JobApplication] {
        applicationManager.getPendingApplications(forOpportunity: opportunity.safeId)
    }
    
    private var rankedApplications: [JobApplication] {
        // Use smart ranking to sort applicants
        ratingManager.rankApplicants(pendingApplications, opportunity: opportunity)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Beautiful green-to-white gradient background
                CommunallyTheme.backgroundGradient
                    .ignoresSafeArea()
                
                if pendingApplications.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            // Applicants first — primary action is picking someone
                            VStack(spacing: 14) {
                                ForEach(rankedApplications) { application in
                                    ModernApplicantCard(
                                        application: application,
                                        badge: ratingManager.getRankingBadge(
                                            for: application,
                                            in: pendingApplications,
                                            opportunity: opportunity
                                        )
                                    ) {
                                        selectedApplicant = application
                                        showingAcceptConfirm = true
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 8)

                            Text("Sorted by fit (ratings & experience).")
                                .font(.system(size: 12, weight: .medium, design: .default))
                                .foregroundColor(Color(red: 0.45, green: 0.45, blue: 0.45))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 24)

                            // Compact summary below the list
                            HStack(spacing: 10) {
                                Image(systemName: "person.2.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(CommunallyTheme.primaryGreen)
                                Text("\(pendingApplications.count) applicant\(pendingApplications.count == 1 ? "" : "s") · tap a card to review")
                                    .font(.system(size: 14, weight: .medium, design: .default))
                                    .foregroundColor(Color(red: 0.35, green: 0.35, blue: 0.35))
                                Spacer(minLength: 0)
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color.white)
                                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
                            )
                            .padding(.horizontal, 20)

                            Spacer(minLength: 40)
                        }
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle("Applicants")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        dismiss()
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color(red: 0.95, green: 0.95, blue: 0.95))
                                .frame(width: 32, height: 32)
                            
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(Color(red: 0.3, green: 0.3, blue: 0.3))
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
            .sheet(isPresented: $showPaymentSheet) {
                if let application = selectedApplication {
                    PaymentConfirmationSheet(
                        opportunity: opportunity,
                        application: application,
                        onPaymentComplete: completeAcceptance
                    )
                }
            }
            .alert("Can't Accept Applicant", isPresented: $showPaymentError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(paymentError ?? "This applicant can't be accepted right now.")
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                CommunallyTheme.primaryGreen.opacity(0.15),
                                CommunallyTheme.lightGreen.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                
                Image(systemName: "person.2.slash.fill")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundColor(CommunallyTheme.primaryGreen)
            }
            
            VStack(spacing: 12) {
                Text("No Applications Yet")
                    .font(.system(size: 24, weight: .bold, design: .default))
                    .foregroundColor(Color(red: 0.15, green: 0.15, blue: 0.15))
                
                Text("Job seekers can discover your opportunity on the map and apply.\n\nCheck back later!")
                    .font(.system(size: 15, weight: .medium, design: .default))
                    .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    @State private var showPaymentSheet = false
    @State private var selectedApplication: JobApplication?
    
    private func acceptApplicant(_ application: JobApplication) {
        if let existingJob = applicationManager.activeAcceptedApplication(
            for: application.applicantId,
            excludingOpportunityId: opportunity.safeId
        ) {
            let jobTitle = existingJob.opportunityTitleSnapshot ?? "another job"
            paymentError = "\(application.applicantName) is already accepted for \(jobTitle). They can only have one active job at a time."
            showPaymentError = true
            return
        }
        
        // Show payment confirmation first (if not volunteer)
        if !opportunity.isVolunteer {
            selectedApplication = application
            showPaymentSheet = true
        } else {
            // Volunteer job - accept directly without payment
            applicationManager.acceptApplication(applicationId: application.id) { success, message in
                if success {
                    print("✅ Accepted applicant: \(application.applicantName)")
                    dismiss()
                } else {
                    paymentError = message
                    showPaymentError = true
                }
            }
        }
    }
    
    private func completeAcceptance() {
        guard let application = selectedApplication else { return }
        
        applicationManager.acceptApplication(applicationId: application.id) { success, message in
            if success {
                print("✅ Accepted applicant with payment: \(application.applicantName)")
                dismiss()
            } else {
                paymentError = message
                showPaymentError = true
            }
        }
    }
}

// MARK: - Modern Applicant Card
struct ModernApplicantCard: View {
    let application: JobApplication
    let badge: String?
    let onAccept: () -> Void
    @ObservedObject private var ratingManager = RatingManager.shared
    @State private var isPressed = false
    
    init(application: JobApplication, badge: String? = nil, onAccept: @escaping () -> Void) {
        self.application = application
        self.badge = badge
        self.onAccept = onAccept
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                CompactClickableProfile(
                    userId: application.applicantId,
                    userName: application.applicantName,
                    userImageData: application.applicantImageData,
                    size: 64
                )
                
                // Info
                VStack(alignment: .leading, spacing: 8) {
                    // Badge if top match
                    if let badgeText = badge {
                        RatingBadge(badge: badgeText)
                    }

                    // "Worked for you before" — only renders when applicable.
                    WorkedTogetherBadge(
                        currentUserId: AuthenticationManager.shared.currentUser?.id,
                        otherUserId: application.applicantId
                    )

                    HStack(spacing: 6) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(CommunallyTheme.primaryGreen)

                        Text("Applied \(application.timeAgo)")
                            .font(.system(size: 14, weight: .medium, design: .default))
                            .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                    }
                }
                
                Spacer()
            }
            .padding(20)
            
            // Divider
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            CommunallyTheme.primaryGreen.opacity(0.2),
                            CommunallyTheme.lightGreen.opacity(0.1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
                .padding(.horizontal, 20)
            
            // Accept button
            Button(action: {
                let impactMed = UIImpactFeedbackGenerator(style: .medium)
                impactMed.impactOccurred()
                onAccept()
            }) {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text("Accept Applicant")
                        .font(.system(size: 17, weight: .bold, design: .default))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(18)
                .background(
                    LinearGradient(
                        colors: [
                            CommunallyTheme.primaryGreen,
                            CommunallyTheme.lightGreen
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            }
            .buttonStyle(PlainButtonStyle())
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            isPressed = true
                        }
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            isPressed = false
                        }
                    }
            )
        }
        .background(Color.white)
        .cornerRadius(20)
        .shadow(color: CommunallyTheme.primaryGreen.opacity(0.2), radius: 15, x: 0, y: 8)
        .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
    }
}

struct ApplicantCard: View {
    let application: JobApplication
    let onAccept: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            CompactClickableProfile(
                userId: application.applicantId,
                userName: application.applicantName,
                userImageData: application.applicantImageData,
                size: 60
            )
            
            // Info
            VStack(alignment: .leading, spacing: 6) {
                Text("Applied \(application.timeAgo)")
                    .font(CommunallyTheme.captionFont)
                    .foregroundColor(CommunallyTheme.darkGray.opacity(0.6))
            }
            
            Spacer()
            
            // Accept button
            Button(action: onAccept) {
                Text("Accept")
                    .font(CommunallyTheme.captionFont)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(CommunallyTheme.primaryGreen)
                    .cornerRadius(20)
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
}

#Preview {
    ApplicantsListView(opportunity: Opportunity(
        id: "1",
        title: "Gardening Needed",
        description: "Need help with lawn mowing",
        hirerId: "hirer123",
        hirerName: "Sarah Johnson",
        hirerImageData: nil,
        location: Location(latitude: 37.7749, longitude: -122.4194, address: "SF"),
        locationName: "San Francisco, CA",
        isVolunteer: false,
        payAmount: "50",
        jobType: "Gardening",
        createdAt: Date(),
        isActive: true,
        applicantCount: 2,
        status: .open,
        acceptedApplicantId: nil,
        scheduledDate: Date(),
        scheduledTime: "Morning (8AM - 12PM)"
    ))
}

