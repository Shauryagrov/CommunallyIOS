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
                // Gradient background
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
                
                if pendingApplications.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            // Header card
                            VStack(spacing: 12) {
                                HStack {
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
                                            .frame(width: 52, height: 52)
                                        
                                        Image(systemName: "person.2.fill")
                                            .font(.system(size: 24, weight: .semibold))
                                            .foregroundColor(.white)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("\(pendingApplications.count) Applicant\(pendingApplications.count == 1 ? "" : "s")")
                                            .font(.system(size: 20, weight: .bold, design: .rounded))
                                            .foregroundColor(Color(red: 0.15, green: 0.15, blue: 0.15))
                                        
                                        Text("Choose the best fit for your job")
                                            .font(.system(size: 14, weight: .medium, design: .rounded))
                                            .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                                    }
                                    
                                    Spacer()
                                }
                                .padding(20)
                                .background(
                                    RoundedRectangle(cornerRadius: 20)
                                        .fill(Color.white)
                                        .shadow(color: Color(red: 0.6, green: 0.4, blue: 1.0).opacity(0.15), radius: 15, x: 0, y: 8)
                                        .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
                                )
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                            
                            // Smart ranking info
                            HStack(spacing: 10) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(Color.blue)
                                
                                Text("Sorted by best match • Based on ratings, experience & more")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(Color.blue)
                                
                                Spacer()
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.blue.opacity(0.1))
                            )
                            .padding(.horizontal, 20)
                            
                            // Applicants list (ranked)
                            VStack(spacing: 16) {
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
                            
                            Spacer(minLength: 100)
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
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.6, green: 0.4, blue: 1.0).opacity(0.15),
                                Color(red: 0.7, green: 0.5, blue: 1.0).opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)
                
                Image(systemName: "person.2.slash.fill")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundColor(Color(red: 0.6, green: 0.4, blue: 1.0))
            }
            
            VStack(spacing: 12) {
                Text("No Applications Yet")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 0.15, green: 0.15, blue: 0.15))
                
                Text("Job seekers can discover your opportunity on the map and apply.\n\nCheck back later!")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func acceptApplicant(_ application: JobApplication) {
        applicationManager.acceptApplication(applicationId: application.id)
        print("✅ Accepted applicant: \(application.applicantName)")
        dismiss()
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
                // Profile picture with gradient border
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
                        .frame(width: 70, height: 70)
                    
                    if let imageData = application.applicantImageData,
                       let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 64, height: 64)
                            .clipShape(Circle())
                    } else {
                        ZStack {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 64, height: 64)
                            
                            Image(systemName: "person.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 32, height: 32)
                                .foregroundColor(Color(red: 0.6, green: 0.4, blue: 1.0))
                        }
                    }
                }
                
                // Info
                VStack(alignment: .leading, spacing: 8) {
                    // Badge if top match
                    if let badgeText = badge {
                        RatingBadge(badge: badgeText)
                    }
                    
                    Text(application.applicantName)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 0.15, green: 0.15, blue: 0.15))
                    
                    // Rating
                    UserRatingDisplay(userId: application.applicantId, compact: true)
                    
                    HStack(spacing: 6) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(red: 0.6, green: 0.4, blue: 1.0))
                        
                        Text("Applied \(application.timeAgo)")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
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
                            Color(red: 0.6, green: 0.4, blue: 1.0).opacity(0.2),
                            Color(red: 0.7, green: 0.5, blue: 1.0).opacity(0.1)
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
                        .font(.system(size: 17, weight: .bold, design: .rounded))
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
                            Color(red: 0.6, green: 0.4, blue: 1.0),
                            Color(red: 0.7, green: 0.5, blue: 1.0)
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
        .shadow(color: Color(red: 0.6, green: 0.4, blue: 1.0).opacity(0.2), radius: 15, x: 0, y: 8)
        .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
    }
}

struct ApplicantCard: View {
    let application: JobApplication
    let onAccept: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            // Profile picture
            if let imageData = application.applicantImageData,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60, height: 60)
                    .foregroundColor(CommunallyTheme.darkGray.opacity(0.3))
            }
            
            // Info
            VStack(alignment: .leading, spacing: 6) {
                Text(application.applicantName)
                    .font(CommunallyTheme.bodyFont)
                    .fontWeight(.bold)
                    .foregroundColor(CommunallyTheme.darkGray)
                
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
        acceptedApplicantId: nil
    ))
}

