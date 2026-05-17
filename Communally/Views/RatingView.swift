//
//  RatingView.swift
//  Communally
//
//  UI for rating job seekers and displaying ratings
//

import SwiftUI

// MARK: - Rate User View
struct RateUserView: View {
    let opportunity: Opportunity
    let jobSeeker: JobApplication
    @EnvironmentObject var authManager: AuthenticationManager
    @ObservedObject private var ratingManager = RatingManager.shared
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedStars: Int = 5
    @State private var reviewText: String = ""
    @State private var isSubmitting = false
    @State private var showSuccess = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 28) {
                    // Header
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.yellow, Color.orange],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 80, height: 80)
                                .shadow(color: Color.yellow.opacity(0.4), radius: 15, x: 0, y: 8)
                            
                            Image(systemName: "star.fill")
                                .font(.system(size: 40, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        
                        Text("Rate \(jobSeeker.applicantName)")
                            .font(.system(size: 24, weight: .bold, design: .default))
                            .foregroundColor(CommunallyTheme.darkGray)
                        
                        Text("How was your experience working together?")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(CommunallyTheme.darkGray.opacity(0.6))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)
                    
                    // Job info
                    HStack(spacing: 12) {
                        Image(systemName: "briefcase.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(CommunallyTheme.primaryGreen)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Job Completed")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(CommunallyTheme.darkGray.opacity(0.6))
                            
                            Text(opportunity.title)
                                .font(.system(size: 15, weight: .semibold, design: .default))
                                .foregroundColor(CommunallyTheme.darkGray)
                        }
                        
                        Spacer()
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(CommunallyTheme.primaryGreen.opacity(0.1))
                    )
                    
                    // Star rating
                    VStack(spacing: 16) {
                        Text("Tap to rate")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(CommunallyTheme.darkGray.opacity(0.7))
                        
                        HStack(spacing: 16) {
                            ForEach(1...5, id: \.self) { star in
                                Button(action: {
                                    let impactMed = UIImpactFeedbackGenerator(style: .medium)
                                    impactMed.impactOccurred()
                                    selectedStars = star
                                }) {
                                    Image(systemName: star <= selectedStars ? "star.fill" : "star")
                                        .font(.system(size: 42, weight: .medium))
                                        .foregroundColor(star <= selectedStars ? Color.yellow : Color.gray.opacity(0.3))
                                }
                                .scaleEffect(star == selectedStars ? 1.1 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: selectedStars)
                            }
                        }
                        
                        Text(ratingDescription)
                            .font(.system(size: 16, weight: .semibold, design: .default))
                            .foregroundColor(ratingColor)
                    }
                    .padding(.vertical, 20)
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white)
                            .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
                    )
                    
                    // Review text (optional)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Add a review (optional)")
                            .font(.system(size: 15, weight: .semibold, design: .default))
                            .foregroundColor(CommunallyTheme.darkGray)
                        
                        TextEditor(text: $reviewText)
                            .font(.system(size: 15, design: .default))
                            .foregroundColor(.black)
                            .scrollContentBackground(.hidden)
                            .frame(height: 100)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(CommunallyTheme.primaryGreen.opacity(0.3), lineWidth: 1)
                                    )
                            )
                        
                        Text("\(reviewText.count)/500")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(CommunallyTheme.darkGray.opacity(0.5))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    
                    // Success message
                    if showSuccess {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(CommunallyTheme.primaryGreen)
                            
                            Text("Rating submitted successfully!")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(CommunallyTheme.primaryGreen)
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(CommunallyTheme.primaryGreen.opacity(0.1))
                        )
                    }
                    
                    // Submit button
                    Button(action: submitRating) {
                        HStack(spacing: 12) {
                            if isSubmitting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 20, weight: .semibold))
                                
                                Text("Submit Rating")
                                    .font(.system(size: 18, weight: .bold))
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            LinearGradient(
                                colors: isSubmitting ?
                                    [CommunallyTheme.primaryGreen.opacity(0.6), CommunallyTheme.primaryGreen.opacity(0.6)] :
                                    [CommunallyTheme.primaryGreen, CommunallyTheme.primaryGreen.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                        .shadow(color: CommunallyTheme.primaryGreen.opacity(0.4), radius: 15, x: 0, y: 8)
                    }
                    .disabled(isSubmitting || showSuccess)
                    
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 24)
            }
            .background(Color(red: 0.97, green: 0.97, blue: 0.97))
            .navigationTitle("Rate Worker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !showSuccess {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                }
            }
        }
    }
    
    private var ratingDescription: String {
        switch selectedStars {
        case 5: return "Excellent!"
        case 4: return "Very Good"
        case 3: return "Good"
        case 2: return "Fair"
        case 1: return "Poor"
        default: return ""
        }
    }
    
    private var ratingColor: Color {
        switch selectedStars {
        case 5: return Color.green
        case 4: return Color(red: 0.6, green: 0.8, blue: 0.3)
        case 3: return Color.yellow
        case 2: return Color.orange
        case 1: return Color.red
        default: return Color.gray
        }
    }
    
    private func submitRating() {
        guard let user = authManager.currentUser else { return }
        
        isSubmitting = true
        
        let trimmedReview = reviewText.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalReview = trimmedReview.isEmpty ? nil : String(trimmedReview.prefix(500))
        
        ratingManager.submitRating(
            opportunityId: opportunity.safeId,
            applicationId: jobSeeker.id,
            raterId: user.id,
            raterName: user.fullName,
            ratedUserId: jobSeeker.applicantId,
            ratedUserName: jobSeeker.applicantName,
            score: Double(selectedStars),
            review: finalReview,
            jobTitle: opportunity.title
        ) { success in
            isSubmitting = false
            
            if success {
                showSuccess = true
                
                // Haptic feedback
                let notification = UINotificationFeedbackGenerator()
                notification.notificationOccurred(.success)
                
                // Auto dismiss after delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Rate hirer (after job completed — worker rates hirer)

struct RateHirerView: View {
    let opportunity: Opportunity
    let application: JobApplication
    @EnvironmentObject var authManager: AuthenticationManager
    @ObservedObject private var ratingManager = RatingManager.shared
    @Environment(\.dismiss) var dismiss

    @State private var selectedStars: Int = 5
    @State private var reviewText: String = ""
    @State private var isSubmitting = false
    @State private var showSuccess = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.yellow, Color.orange],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 80, height: 80)
                                .shadow(color: Color.yellow.opacity(0.4), radius: 15, x: 0, y: 8)

                            Image(systemName: "star.fill")
                                .font(.system(size: 40, weight: .semibold))
                                .foregroundColor(.white)
                        }

                        Text("Rate \(opportunity.hirerName)")
                            .font(.system(size: 24, weight: .bold, design: .default))
                            .foregroundColor(CommunallyTheme.darkGray)

                        Text("How was your experience with this hirer?")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(CommunallyTheme.darkGray.opacity(0.6))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 20)

                    HStack(spacing: 12) {
                        Image(systemName: "briefcase.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(CommunallyTheme.primaryGreen)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Job")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(CommunallyTheme.darkGray.opacity(0.6))

                            Text(opportunity.title)
                                .font(.system(size: 15, weight: .semibold, design: .default))
                                .foregroundColor(CommunallyTheme.darkGray)
                        }

                        Spacer()
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(CommunallyTheme.primaryGreen.opacity(0.1))
                    )

                    VStack(spacing: 16) {
                        Text("Tap to rate")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(CommunallyTheme.darkGray.opacity(0.7))

                        HStack(spacing: 16) {
                            ForEach(1...5, id: \.self) { star in
                                Button(action: {
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    selectedStars = star
                                }) {
                                    Image(systemName: star <= selectedStars ? "star.fill" : "star")
                                        .font(.system(size: 42, weight: .medium))
                                        .foregroundColor(star <= selectedStars ? Color.yellow : Color.gray.opacity(0.3))
                                }
                                .scaleEffect(star == selectedStars ? 1.1 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: selectedStars)
                            }
                        }
                    }
                    .padding(.vertical, 20)
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white)
                            .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
                    )

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Add a review (optional)")
                            .font(.system(size: 15, weight: .semibold, design: .default))
                            .foregroundColor(CommunallyTheme.darkGray)

                        TextEditor(text: $reviewText)
                            .font(.system(size: 15, design: .default))
                            .foregroundColor(.black)
                            .scrollContentBackground(.hidden)
                            .frame(height: 100)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(CommunallyTheme.primaryGreen.opacity(0.3), lineWidth: 1)
                                    )
                            )

                        Text("\(reviewText.count)/500")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(CommunallyTheme.darkGray.opacity(0.5))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    if showSuccess {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(CommunallyTheme.primaryGreen)

                            Text("Thanks — your rating was submitted!")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(CommunallyTheme.primaryGreen)
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(CommunallyTheme.primaryGreen.opacity(0.1))
                        )
                    }

                    Button(action: submitRating) {
                        HStack(spacing: 12) {
                            if isSubmitting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 20, weight: .semibold))

                                Text("Submit Rating")
                                    .font(.system(size: 18, weight: .bold))
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            LinearGradient(
                                colors: isSubmitting ?
                                    [CommunallyTheme.primaryGreen.opacity(0.6), CommunallyTheme.primaryGreen.opacity(0.6)] :
                                    [CommunallyTheme.primaryGreen, CommunallyTheme.primaryGreen.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                        .shadow(color: CommunallyTheme.primaryGreen.opacity(0.4), radius: 15, x: 0, y: 8)
                    }
                    .disabled(isSubmitting || showSuccess)

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 24)
            }
            .background(Color(red: 0.97, green: 0.97, blue: 0.97))
            .navigationTitle("Rate Hirer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !showSuccess {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    private func submitRating() {
        guard let user = authManager.currentUser else { return }

        isSubmitting = true

        let trimmedReview = reviewText.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalReview = trimmedReview.isEmpty ? nil : String(trimmedReview.prefix(500))

        ratingManager.submitRating(
            opportunityId: opportunity.safeId,
            applicationId: application.id,
            raterId: user.id,
            raterName: user.fullName,
            ratedUserId: opportunity.hirerId,
            ratedUserName: opportunity.hirerName,
            score: Double(selectedStars),
            review: finalReview,
            jobTitle: opportunity.title
        ) { success in
            isSubmitting = false

            if success {
                showSuccess = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Rating Display Component
struct UserRatingDisplay: View {
    let userId: String
    let compact: Bool
    @ObservedObject private var ratingManager = RatingManager.shared
    
    init(userId: String, compact: Bool = false) {
        self.userId = userId
        self.compact = compact
    }
    
    private var stats: UserRatingStats {
        ratingManager.getStats(forUser: userId)
    }
    
    var body: some View {
        if compact {
            compactView
        } else {
            fullView
        }
    }
    
    private var compactView: some View {
        HStack(spacing: 6) {
            Image(systemName: "star.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color.yellow)
            
            Text(stats.scoreDisplay)
                .font(.system(size: 14, weight: .bold, design: .default))
                .foregroundColor(CommunallyTheme.darkGray)
            
            if stats.hasRatings {
                Text("(\(stats.totalRatings))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(CommunallyTheme.darkGray.opacity(0.6))
            } else {
                HStack(spacing: 4) {
                    Text("•")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(CommunallyTheme.darkGray.opacity(0.4))
                    
                    Text("New")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color.blue)
                }
            }
        }
    }
    
    private var fullView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "star.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(Color.yellow)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(stats.scoreDisplay)
                            .font(.system(size: 32, weight: .bold, design: .default))
                            .foregroundColor(CommunallyTheme.darkGray)
                        
                        Text("out of 5")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(CommunallyTheme.darkGray.opacity(0.6))
                    }
                    
                    if stats.hasRatings {
                        Text("\(stats.totalRatings) rating\(stats.totalRatings == 1 ? "" : "s")")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(CommunallyTheme.darkGray.opacity(0.7))
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color.blue)
                            
                            Text("New user • Starting rating")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Color.blue)
                        }
                    }
                }
                
                Spacer()
            }
            
            // Info box for new users
            if !stats.hasRatings {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color.blue)
                    
                    Text("New members start with 4 stars to give them a fair chance. This rating updates as they complete jobs.")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(CommunallyTheme.darkGray.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Spacer()
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.blue.opacity(0.1))
                )
            }
            
            if stats.hasRatings {
                // Star breakdown
                VStack(spacing: 8) {
                    ForEach((1...5).reversed(), id: \.self) { stars in
                        HStack(spacing: 10) {
                            Text("\(stars)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(CommunallyTheme.darkGray.opacity(0.7))
                                .frame(width: 15)
                            
                            Image(systemName: "star.fill")
                                .font(.system(size: 11))
                                .foregroundColor(Color.yellow)
                            
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    // Background
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(height: 6)
                                    
                                    // Filled portion
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.yellow)
                                        .frame(width: geometry.size.width * (stats.percentage(for: stars) / 100), height: 6)
                                }
                            }
                            .frame(height: 6)
                            
                            Text("\(Int(stats.percentage(for: stars)))%")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(CommunallyTheme.darkGray.opacity(0.6))
                                .frame(width: 35, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
        )
    }
}

// MARK: - Rating Badge
struct RatingBadge: View {
    let badge: String
    
    private var badgeColor: Color {
        switch badge {
        case "Top Match": return Color.green
        case "Great Match": return Color.blue
        case "Good Match": return Color.orange
        default: return Color.gray
        }
    }
    
    private var badgeIcon: String {
        switch badge {
        case "Top Match": return "crown.fill"
        case "Great Match": return "star.fill"
        case "Good Match": return "checkmark.circle.fill"
        default: return "circle.fill"
        }
    }
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: badgeIcon)
                .font(.system(size: 12, weight: .bold))
            
            Text(badge)
                .font(.system(size: 12, weight: .bold, design: .default))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(badgeColor)
        )
        .shadow(color: badgeColor.opacity(0.4), radius: 6, x: 0, y: 3)
    }
}

#Preview {
    UserRatingDisplay(userId: "test123", compact: false)
}

