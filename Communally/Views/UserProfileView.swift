//
//  UserProfileView.swift
//  Communally
//
//  Displays user profile with ratings, stats, and share functionality
//

import SwiftUI
import UIKit

struct UserProfileView: View {
    let userId: String
    @EnvironmentObject var authManager: AuthenticationManager
    @ObservedObject private var ratingManager = RatingManager.shared
    @ObservedObject private var applicationManager = ApplicationManager.shared
    @ObservedObject private var opportunityManager = OpportunityManager.shared
    @Environment(\.dismiss) var dismiss
    
    @State private var user: User?
    /// Counts fetched directly from Firestore for the *target* user. Required
    /// for non-own profiles because `ApplicationManager.applications` only
    /// contains the viewer's own apps — see `ApplicationManager.startListening`.
    @State private var profileCounts: ProfileApplicationCounts?
    @State private var showShareSheet = false
    @State private var shareImage: UIImage?
    @State private var shareCaption: String = ""
    @State private var shareKind: ShareKind = .poster

    private enum ShareKind {
        case poster
        case link
    }
    @State private var showEditProfile = false
    @State private var showSignOutConfirmation = false
    @State private var showDeleteAccountConfirmation = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountError: String?
    @State private var showAccountActions = false
    @State private var showBankSetup = false
    @State private var showLocationShare = false
    @State private var showStripeIdentityVerification = false
    @State private var isLoadingUser = true
    @State private var showTerms = false
    @State private var showPrivacy = false

    /// Cover banner photo. Tapping the banner on your own profile lets you change it,
    /// matching the Twitter / LinkedIn pattern from the redesign sketch.
    @State private var fullscreenBioImage: UIImage? = nil
    
    var isOwnProfile: Bool {
        authManager.currentUser?.id == userId
    }
    
    var stats: UserRatingStats {
        ratingManager.getStats(forUser: userId)
    }
    
    var completedJobs: Int {
        if isOwnProfile {
            return applicationManager.applications.filter {
                $0.applicantId == userId && $0.status == .completed
            }.count
        }
        return profileCounts?.completedAsApplicant ?? 0
    }

    var jobsPosted: Int {
        opportunityManager.opportunities.filter {
            $0.hirerId == userId
        }.count
    }

    /// Seeker: completed / accepted gigs. (Hirers use `applicantsToReviewCount` + jobs posted instead.)
    var peopleHelped: Int {
        if isOwnProfile {
            return applicationManager.applications.filter {
                $0.applicantId == userId &&
                    ($0.status == .accepted || $0.status == .completed)
            }.count
        }
        return profileCounts?.helpedAsApplicant ?? 0
    }

    /// Hirer: pending applications across their open listings (needs review).
    var applicantsToReviewCount: Int {
        let myOppIds = Set(opportunityManager.opportunities.filter { $0.hirerId == userId }.map(\.safeId))
        return applicationManager.applications.filter {
            myOppIds.contains($0.opportunityId) && $0.status == .pending
        }.count
    }

    var hirerJobsCompleted: Int {
        if isOwnProfile {
            let myOppIds = Set(opportunityManager.opportunities.filter { $0.hirerId == userId }.map(\.safeId))
            return applicationManager.applications.filter {
                myOppIds.contains($0.opportunityId) && $0.status == .completed
            }.count
        }
        return profileCounts?.completedAsHirer ?? 0
    }
    
    var body: some View {
        Group {
            if isLoadingUser {
                ZStack {
                    CommunallyTheme.backgroundGradient.ignoresSafeArea()
                    VStack(spacing: 14) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: CommunallyTheme.primaryGreen))
                            .scaleEffect(1.2)
                        Text("Loading profile…")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(CommunallyTheme.darkGray.opacity(0.6))
                    }
                }
            } else if user == nil {
                ContentUnavailableView(
                    "Profile Unavailable",
                    systemImage: "person.crop.circle.badge.exclamationmark",
                    description: Text("We couldn't load this profile right now.")
                )
            } else {
                profileContent
            }
        }
        .onAppear {
            loadUser()
        }
        .onChange(of: showStripeIdentityVerification) { _, isPresented in
            guard !isPresented, isOwnProfile, let uid = authManager.currentUser?.id else { return }
            UserDatabase.shared.fetchUserFromFirebase(byUserId: uid) { cloud in
                guard let cloud else { return }
                DispatchQueue.main.async {
                    authManager.updateUser(cloud, shouldSyncProfile: false)
                    user = cloud
                }
            }
        }
    }
    
    private let profileAvatarSize: CGFloat = 92
    private let bannerHeight: CGFloat = 150
    
    private var profilePhotoView: some View {
        Group {
            if let imageData = user?.profileImageData,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: profileAvatarSize, height: profileAvatarSize)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(CommunallyTheme.primaryGreen.opacity(0.92))
                    .frame(width: profileAvatarSize, height: profileAvatarSize)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 38))
                            .foregroundColor(.white)
                    )
            }
        }
        // Two-tone ring: white card edge + brand green outline so the avatar
        // reads cleanly when overlapping the banner.
        .overlay(
            Circle()
                .stroke(Color.white, lineWidth: 4)
        )
        .overlay(
            Circle()
                .stroke(CommunallyTheme.primaryGreen.opacity(0.85), lineWidth: 2)
                .padding(2)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
    }
    
    /// Default banner gradient — uses the existing brand greens so the cover photo
    /// matches the rest of the app when the user hasn't set their own image yet.
    private var defaultBannerFill: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [
                CommunallyTheme.lightGreen.opacity(0.55),
                CommunallyTheme.primaryGreen.opacity(0.78),
                CommunallyTheme.secondaryGreen.opacity(0.85)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    /// Cover banner above the avatar. Static brand-green gradient — custom
    /// banner uploads were removed because the cropper produced corrupted /
    /// white outputs in some flows.
    private var bannerView: some View {
        defaultBannerFill
            .frame(maxWidth: .infinity)
            .frame(height: bannerHeight)
            .clipped()
    }
    
    /// Distinct pill-style "❤️ N helped" badge — pink heart on a soft pink chip,
    /// positioned top-right of the header card per the redesign sketch.
    private var peopleHelpedBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "heart.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.pink)
            Text("\(peopleHelped)")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(CommunallyTheme.darkGray)
                .monospacedDigit()
            Text("helped")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(CommunallyTheme.darkGray.opacity(0.75))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(Color.pink.opacity(0.10))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.pink.opacity(0.22), lineWidth: 1)
        )
        .accessibilityLabel("\(peopleHelped) people helped")
    }
    
    /// Tappable rating row — pushes a full Reviews list. Chevron signals affordance.
    private var ratingView: some View {
        NavigationLink {
            ReviewsListView(
                userId: userId,
                userName: user?.fullName ?? "",
                stats: stats
            )
        } label: {
            HStack(spacing: 8) {
                if stats.hasRatings {
                    HStack(spacing: 2) {
                        ForEach(0..<5) { index in
                            let filled = stats.averageScore >= Double(index + 1)
                            let half = !filled && stats.averageScore >= Double(index) + 0.5
                            Image(systemName: filled ? "star.fill" : (half ? "star.leadinghalf.filled" : "star"))
                                .foregroundColor(.yellow)
                                .font(.system(size: 16))
                        }
                    }
                    
                    Text(String(format: "%.1f", stats.averageScore))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(CommunallyTheme.darkGray)
                    
                    Text("(\(stats.totalRatings) ratings)")
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                } else {
                    Image(systemName: "star")
                        .foregroundColor(CommunallyTheme.darkGray.opacity(0.4))
                        .font(.system(size: 15))
                    
                    Text("Not Rated")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(CommunallyTheme.darkGray.opacity(0.6))
                    
                    Text("· 0 ratings")
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(CommunallyTheme.darkGray.opacity(0.45))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(stats.hasRatings ? Color.yellow.opacity(0.08) : Color.gray.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
    }
    
    /// Banner + overlapping avatar + name / username / pronouns / verified.
    /// "❤️ helped" badge sits top-right of the name row as a distinct chip.
    private var profileHeaderView: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack(alignment: .bottomLeading) {
                bannerView

                HStack(alignment: .bottom, spacing: 0) {
                    profilePhotoView
                        .padding(.leading, 16)

                    Spacer()

                    if isOwnProfile {
                        Menu {
                            // Primary action — IG Stories direct, Muso.ai-style.
                            Button {
                                generateShareImage(target: .instagramStories)
                            } label: {
                                Label("Share to Instagram Story", systemImage: "camera.aperture")
                            }
                            Button {
                                generateShareImage(target: .systemSheet)
                            } label: {
                                Label("More share options…", systemImage: "ellipsis.rectangle")
                            }
                            Divider()
                            Button {
                                shareProfileLink()
                            } label: {
                                Label("Share profile link", systemImage: "link")
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 13, weight: .bold))
                                Text("Share your stats!")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(Capsule().fill(Color.black.opacity(0.40)))
                        }
                        .padding(.trailing, 14)
                    }
                }
                .offset(y: profileAvatarSize / 2)
            }
            // Reserve space for the avatar overhang.
            .padding(.bottom, profileAvatarSize / 2)
            
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(user?.fullName ?? "Loading...")
                        .font(.system(size: 22, weight: .bold, design: .default))
                        .foregroundColor(CommunallyTheme.darkGray)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .multilineTextAlignment(.leading)
                    
                    if let username = user?.displayUsername, !username.isEmpty {
                        HStack(spacing: 8) {
                            Text(username)
                                .font(.system(size: 15, weight: .semibold, design: .default))
                                .foregroundColor(CommunallyTheme.primaryGreen)
                            
                            if let pronouns = user?.pronouns?
                                .trimmingCharacters(in: .whitespacesAndNewlines),
                               !pronouns.isEmpty {
                                Text("· \(pronouns)")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(CommunallyTheme.darkGray.opacity(0.6))
                            }
                        }
                    }
                    
                    if user?.userType == .jobHirer {
                        identityVerificationBadge
                            .padding(.top, 2)
                    }

                    if user?.userType == .jobHirer {
                        HStack(spacing: 10) {
                            HStack(spacing: 4) {
                                Image(systemName: "star.fill")
                                    .foregroundColor(.yellow)
                                    .font(.system(size: 12))
                                Text(stats.hasRatings ? String(format: "%.1f", stats.averageScore) : "—")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(CommunallyTheme.darkGray)
                                if stats.totalRatings > 0 {
                                    Text("(\(stats.totalRatings))")
                                        .font(.system(size: 11))
                                        .foregroundColor(.gray)
                                }
                            }
                            Circle()
                                .fill(CommunallyTheme.darkGray.opacity(0.3))
                                .frame(width: 3, height: 3)
                            HStack(spacing: 4) {
                                Image(systemName: "briefcase.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(CommunallyTheme.primaryGreen)
                                Text("\(jobsPosted) posted")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(CommunallyTheme.darkGray.opacity(0.8))
                            }
                        }
                        .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if user?.userType == .jobSeeker {
                    peopleHelpedBadge
                }
            }
            .padding(.horizontal, 16)

            if user?.userType != .jobHirer {
                ratingView
                    .padding(.horizontal, 16)

                if let rank = SeekerRank.rank(forCompletedJobs: completedJobs) {
                    HStack(spacing: 8) {
                        SeekerRankBadge(rank: rank, compact: true)
                        if let next = SeekerRank.nextRank(afterCompletedJobs: completedJobs) {
                            Text("\(next.jobsRemaining) job\(next.jobsRemaining == 1 ? "" : "s") to \(next.rank.rawValue)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(CommunallyTheme.darkGray.opacity(0.55))
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }
    
    /// Instagram-style bio: plain multiline text, no card chrome.
    private func profileBioSection(bio: String) -> some View {
        Text(bio)
            .font(.system(size: 14, weight: .regular, design: .default))
            .foregroundColor(CommunallyTheme.darkGray)
            .lineSpacing(5)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
    }
    
    /// Restores a clear entry point to edit bio / cover / pronouns and open the
    /// same account tools that live behind the gear menu.
    private var ownProfileAccountCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Account & Profile")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(CommunallyTheme.darkGray)
                    Text("Photos, bio, categories, and settings")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(CommunallyTheme.darkGray.opacity(0.5))
                }
                Spacer()
            }
            
            Button {
                showEditProfile = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Edit profile & bio")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Name, @username, about, cover & profile photo")
                            .font(.system(size: 12, weight: .medium))
                            .opacity(0.75)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .opacity(0.4)
                }
                .foregroundColor(.white)
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(
                    LinearGradient(
                        colors: [CommunallyTheme.primaryGreen, CommunallyTheme.secondaryGreen],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: CommunallyTheme.primaryGreen.opacity(0.3), radius: 10, x: 0, y: 5)
            }
            .buttonStyle(.plain)
            
            Button {
                showAccountActions = true
            } label: {
                HStack {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Account settings, safety & more")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(CommunallyTheme.darkGray.opacity(0.45))
                }
                .foregroundColor(CommunallyTheme.darkGray)
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.92))
                .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
        )
        .padding(.horizontal, 16)
    }
    
    private var profileContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                profileHeaderView

                // Skills / job categories (shown above bio)
                if let skills = user?.skills, !skills.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(user?.userType == .jobSeeker ? "Job categories" : "Skills")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(CommunallyTheme.darkGray)

                        FlowLayout(spacing: 8) {
                            ForEach(skills, id: \.self) { skill in
                                Text(skill)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(CommunallyTheme.accentGreen)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(
                                        Capsule()
                                            .fill(CommunallyTheme.primaryGreen.opacity(0.10))
                                    )
                                    .overlay(
                                        Capsule()
                                            .stroke(CommunallyTheme.primaryGreen.opacity(0.25), lineWidth: 1)
                                    )
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                }

                // Bio directly under header row (Instagram-style).
                // If the bio is empty and you're viewing your own profile, show a
                // tappable "Add your bio" placeholder that opens the editor.
                if let bio = user?.description?.trimmingCharacters(in: .whitespacesAndNewlines), !bio.isEmpty {
                    if isOwnProfile {
                        Button {
                            showEditProfile = true
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Text(bio)
                                    .font(.system(size: 14, weight: .regular, design: .default))
                                    .foregroundColor(CommunallyTheme.darkGray)
                                    .lineSpacing(5)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "pencil")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(CommunallyTheme.primaryGreen.opacity(0.9))
                                    .padding(.top, 2)
                            }
                            .padding(.horizontal, 16)
                        }
                        .buttonStyle(.plain)
                    } else {
                        profileBioSection(bio: bio)
                    }
                } else if isOwnProfile {
                    Button {
                        showEditProfile = true
                    } label: {
                        Text("Add your bio")
                            .font(.system(size: 14, weight: .regular, design: .default))
                            .italic()
                            .foregroundColor(CommunallyTheme.darkGray.opacity(0.5))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                    }
                    .buttonStyle(.plain)
                }
                
                // Bio photo attachments
                let attachments = (user?.bioAttachmentData ?? []).compactMap { UIImage(data: $0) }
                if !attachments.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(Array(attachments.enumerated()), id: \.offset) { _, img in
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 88, height: 88)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .onTapGesture { fullscreenBioImage = img }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .fullScreenCover(item: $fullscreenBioImage) { img in
                        FullscreenImageView(image: img)
                    }
                }

                if isOwnProfile {
                    ownProfileAccountCard
                }
                
                // Block (always available when viewing someone else's profile).
                // Safety / abuse reporting was intentionally moved to the
                // active-job view only — users should only be able to file an
                // emergency report when they're actually in a job with the
                // person, not just because they viewed their profile.
                if !isOwnProfile {
                    UserSafetyButtons(
                        userId: userId,
                        userName: user?.fullName ?? "",
                        relatedJobId: nil,
                        relatedJobTitle: nil
                    )
                    .padding(.horizontal)
                }
                
                // Recent Ratings
                let userRatings = ratingManager.getRatings(forUser: userId)
                if !userRatings.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recent Ratings")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(CommunallyTheme.darkGray)
                            .padding(.horizontal)
                        
                        ForEach(userRatings.prefix(5)) { rating in
                            RatingCard(rating: rating)
                        }
                    }
                }

                // Legal links — only shown on own profile
                if isOwnProfile {
                    VStack(spacing: 0) {
                        Divider()
                            .padding(.horizontal)
                            .padding(.bottom, 16)

                        HStack(spacing: 0) {
                            Button("Terms of Service") { showTerms = true }
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(CommunallyTheme.primaryGreen)
                            Text(" · ")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                            Button("Privacy Policy") { showPrivacy = true }
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(CommunallyTheme.primaryGreen)
                            Text(" · ")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                            Button("Do Not Sell My Info") {
                                if let url = URL(string: "mailto:communallyapp@gmail.com?subject=Do%20Not%20Sell%20My%20Personal%20Information") {
                                    UIApplication.shared.open(url)
                                }
                            }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(CommunallyTheme.primaryGreen)
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 8)

                        Text("© 2026 Communally. All rights reserved.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .padding(.bottom, 8)
                    }
                }
            }
            .padding(.bottom, 40)
        }
        .background(CommunallyTheme.backgroundGradient)
        .navigationTitle(isOwnProfile ? "My Profile" : "Profile")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showTerms) {
            NavigationView { TermsAndConditionsView() }
        }
        .sheet(isPresented: $showPrivacy) {
            NavigationView { PrivacyPolicyView() }
        }
        .overlay {
            if showAccountActions {
                accountSettingsPopup
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: showAccountActions)
        .sheet(isPresented: $showShareSheet) {
            switch shareKind {
            case .poster:
                // Image only — no caption. The caption was producing a long
                // text message in iMessage previews ("Madhur posts jobs on
                // Communally… Download Communally (free): …"). Recipients
                // should just get the poster, like Muso.ai.
                if let image = shareImage {
                    ShareSheet(activityItems: [image])
                }
            case .link:
                ShareSheet(activityItems: [shareCaption])
            }
        }
        .sheet(isPresented: $showEditProfile) {
            if let user = user {
                EditProfileView(user: user)
                    .environmentObject(authManager)
            }
        }
        .sheet(isPresented: $showBankSetup) {
            BankSetupSheet()
                .environmentObject(authManager)
        }
        .sheet(isPresented: $showLocationShare) {
            QuickLocationShareView()
                .environmentObject(authManager)
        }
        .sheet(isPresented: $showStripeIdentityVerification) {
            StripeIdentityVerificationView()
                .environmentObject(authManager)
        }
        .alert("Sign Out", isPresented: $showSignOutConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) {
                AuthenticationManager.shared.signOut()
            }
        } message: {
            Text("Are you sure you want to sign out? You'll need to sign back in to access your account.")
        }
        .alert("Delete Account?", isPresented: $showDeleteAccountConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete Permanently", role: .destructive) {
                isDeletingAccount = true
                AuthenticationManager.shared.deleteAccount { result in
                    isDeletingAccount = false
                    if case .failure(let err) = result {
                        deleteAccountError = err.localizedDescription
                    }
                    // On success, ContentView routes to AuthenticationView automatically
                    // since isAuthenticated flips to false.
                }
            }
        } message: {
            Text("This permanently deletes your profile, jobs, applications, messages, and ratings from every device. This cannot be undone.")
        }
        .alert("Couldn't delete account", isPresented: Binding(get: { deleteAccountError != nil }, set: { if !$0 { deleteAccountError = nil } })) {
            Button("OK", role: .cancel) { deleteAccountError = nil }
        } message: {
            Text(deleteAccountError ?? "")
        }
        .overlay {
            if isDeletingAccount {
                ZStack {
                    Color.black.opacity(0.45).ignoresSafeArea()
                    VStack(spacing: 14) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.2)
                        Text("Deleting your account…")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .padding(28)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.black.opacity(0.6))
                    )
                }
            }
        }
    }
    
    private func loadUser() {
        if let currentUser = authManager.currentUser, currentUser.id == userId {
            user = currentUser
            isLoadingUser = false
            loadProfileCounts()
            return
        }

        if let cachedUser = UserDatabase.shared.getUser(byGoogleId: userId) {
            user = cachedUser
            isLoadingUser = false
            loadProfileCounts()
            return
        }

        isLoadingUser = true
        UserDatabase.shared.fetchUserFromFirebase(byGoogleId: userId) { fetchedUser in
            self.user = fetchedUser
            self.isLoadingUser = false
            self.loadProfileCounts()
        }
    }

    /// Pulls completed / helped / completed-as-hirer counts for the *target*
    /// user from Firestore, so visiting a profile always shows that person's
    /// real numbers — not whatever happened to be in the viewer's app cache.
    private func loadProfileCounts() {
        applicationManager.fetchProfileApplicationCounts(forUserId: userId) { counts in
            self.profileCounts = counts
        }
    }
    
    // MARK: - Account settings popup (centered white card)

    private var accountSettingsPopup: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { closeAccountSettings() }

            VStack(spacing: 0) {
                HStack(alignment: .center) {
                    Text("Account Settings")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(CommunallyTheme.darkGray)
                    Spacer()
                    Button {
                        closeAccountSettings()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(CommunallyTheme.darkGray.opacity(0.55))
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color.gray.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 10)

                Divider()

                VStack(spacing: 4) {
                    accountActionRow(icon: "person.crop.circle.fill", label: "Edit Profile") {
                        closeAccountSettings { showEditProfile = true }
                    }
                    if user?.userType == .jobSeeker {
                        accountActionRow(icon: "building.columns.fill", label: "Manage Bank Account") {
                            closeAccountSettings { showBankSetup = true }
                        }
                    }
                    accountActionRow(icon: "shield.lefthalf.filled", label: "Share My Location") {
                        closeAccountSettings { showLocationShare = true }
                    }
                    if user?.userType == .jobHirer && user?.isStripeIdentityVerified != true {
                        accountActionRow(icon: "checkmark.seal.fill", label: "Verify Identity") {
                            closeAccountSettings { showStripeIdentityVerification = true }
                        }
                    }
                    Divider().padding(.vertical, 6).padding(.horizontal, 12)
                    accountActionRow(icon: "rectangle.portrait.and.arrow.right.fill", label: "Sign Out", destructive: true) {
                        closeAccountSettings { showSignOutConfirmation = true }
                    }
                    accountActionRow(icon: "trash.fill", label: "Delete Account", destructive: true) {
                        closeAccountSettings { showDeleteAccountConfirmation = true }
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 6)
            }
            .frame(maxWidth: 340)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.20), radius: 22, x: 0, y: 10)
            )
            .padding(.horizontal, 28)
        }
        .zIndex(120)
    }

    /// Identity-verification badge for hirers. Two states:
    ///   - Verified: green check + "Verified" (informational, not tappable).
    ///   - Not verified: gray pill + "Not verified" + chevron. Tappable on own
    ///     profile to open the Stripe Identity sheet; informational for others.
    @ViewBuilder
    private var identityVerificationBadge: some View {
        let verified = user?.isStripeIdentityVerified == true
        if verified {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text("Verified")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(CommunallyTheme.primaryGreen)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(CommunallyTheme.primaryGreen.opacity(0.12))
            )
        } else {
            Button {
                if isOwnProfile {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showStripeIdentityVerification = true
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Not verified")
                        .font(.system(size: 12, weight: .semibold))
                    if isOwnProfile {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .opacity(0.7)
                    }
                }
                .foregroundColor(Color(red: 0.55, green: 0.45, blue: 0.0))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(Color(red: 1.0, green: 0.95, blue: 0.78))
                )
            }
            .buttonStyle(.plain)
            .disabled(!isOwnProfile)
        }
    }

    private func accountActionRow(
        icon: String,
        label: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(destructive ? .red : CommunallyTheme.primaryGreen)
                    .frame(width: 28)
                Text(label)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(destructive ? .red : CommunallyTheme.darkGray)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(CommunallyTheme.darkGray.opacity(0.30))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func closeAccountSettings(_ then: (() -> Void)? = nil) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
            showAccountActions = false
        }
        if let then {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { then() }
        }
    }

    /// Where the user wants the rendered stats poster to go.
    private enum ShareTarget {
        case instagramStories  // direct hand-off via instagram-stories:// URL
        case systemSheet       // standard iOS share sheet
    }

    private func generateShareImage(target: ShareTarget = .systemSheet) {
        let isHirer = user?.userType == .jobHirer
        let renderer = ImageRenderer(content: ShareStatsCard(
            userName: user?.fullName ?? "",
            username: user?.username,
            userImage: user?.profileImageData.flatMap { UIImage(data: $0) },
            rating: stats.averageScore,
            completedJobs: isHirer ? hirerJobsCompleted : completedJobs,
            peopleHelped: peopleHelped,
            totalRatings: stats.totalRatings,
            isHirer: isHirer,
            jobsPosted: jobsPosted,
            globalRankLabel: globalRankLabel(for: stats.totalRatings)
        ))

        renderer.scale = 3.0 // High resolution for sharing

        guard let image = renderer.uiImage else { return }

        let displayName = user?.fullName ?? "this person"
        let roleBlurb = isHirer
            ? "posts jobs on Communally"
            : "finds local work on Communally"
        shareCaption = """
\(displayName) \(roleBlurb) — neighbors helping neighbors with everyday gigs.

Download Communally (free): https://apps.apple.com/app/communally
"""
        shareImage = image
        shareKind = .poster

        switch target {
        case .instagramStories:
            // Hand the poster straight to Instagram Stories. Falls back to
            // the system share sheet if Instagram isn't installed (or if the
            // app doesn't have `instagram-stories` in its
            // LSApplicationQueriesSchemes Info.plist entry).
            if Self.shareImageToInstagramStories(image) { return }
            showShareSheet = true
        case .systemSheet:
            showShareSheet = true
        }
    }

    /// Pastes the rendered image onto the system pasteboard with Instagram's
    /// special background-image keys, then opens `instagram-stories://share`.
    /// Returns `false` (so the caller can fall back) when Instagram isn't
    /// installed or the URL scheme can't be opened.
    @discardableResult
    static func shareImageToInstagramStories(_ image: UIImage) -> Bool {
        guard let url = URL(string: "instagram-stories://share?source_application=communally"),
              UIApplication.shared.canOpenURL(url),
              let data = image.pngData()
        else { return false }

        // 5-min expiration so the pasteboard isn't sticky.
        let pasteboardItems: [String: Any] = [
            "com.instagram.sharedSticker.backgroundImage": data,
            "com.instagram.sharedSticker.backgroundTopColor":    "#1FCC70",
            "com.instagram.sharedSticker.backgroundBottomColor": "#0E9D52"
        ]
        UIPasteboard.general.setItems(
            [pasteboardItems],
            options: [.expirationDate: Date().addingTimeInterval(60 * 5)]
        )
        UIApplication.shared.open(url)
        return true
    }

    /// Plain link share — no poster, just the App Store URL so the recipient
    /// gets a clean message preview. (Universal-link routing into a specific
    /// profile would need an apple-app-site-association file; not set up yet.)
    private func shareProfileLink() {
        shareCaption = "https://apps.apple.com/app/communally"
        shareImage = nil
        shareKind = .link
        showShareSheet = true
    }

    /// Ranks the user against everyone we have ratings stats for. Returns a
    /// short label like "#42 WORLDWIDE" or "TOP 5%" suitable for the poster.
    /// Uses `totalRatings` as the activity proxy; ties keep the user in the
    /// higher rank. Returns nil if there isn't enough population to rank.
    private func globalRankLabel(for myTotalRatings: Int) -> String? {
        let allStats = ratingManager.userStats
        // 1-indexed rank = 1 + (number of users strictly more active than me).
        let ahead = allStats.values.filter { $0.totalRatings > myTotalRatings }.count
        let rank = ahead + 1
        let population = max(allStats.count, rank)

        if rank <= 100 {
            return "#\(rank) WORLDWIDE"
        }
        let percentile = max(1, Int((Double(rank) / Double(population)) * 100.0))
        return "TOP \(percentile)% WORLDWIDE"
    }
}

// MARK: - Profile Stat Card Component
struct ProfileStatCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(color)
                .frame(height: 26)

            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(CommunallyTheme.darkGray)
                .monospacedDigit()

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(CommunallyTheme.darkGray.opacity(0.5))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white)
                .shadow(color: color.opacity(0.12), radius: 10, x: 0, y: 4)
                .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
        )
    }
}

// MARK: - Rating Card Component
struct RatingCard: View {
    let rating: Rating
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(rating.raterName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(CommunallyTheme.darkGray)
                    
                    HStack(spacing: 2) {
                        ForEach(0..<5) { index in
                            Image(systemName: index < Int(rating.score) ? "star.fill" : "star")
                                .foregroundColor(.yellow)
                                .font(.system(size: 14))
                        }
                    }
                }
                
                Spacer()
                
                Text(rating.timeAgo)
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
            
            if let review = rating.review, !review.isEmpty {
                Text(review)
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .lineLimit(3)
            }
            
            Text(rating.jobTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(CommunallyTheme.accentGreen)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(CommunallyTheme.primaryGreen.opacity(0.10))
                )
                .overlay(
                    Capsule()
                        .stroke(CommunallyTheme.primaryGreen.opacity(0.22), lineWidth: 1)
                )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(CommunallyTheme.lightGray, lineWidth: 1)
        )
        .padding(.horizontal)
    }
}

// MARK: - Share Stats Card
struct ShareStatsCard: View {
    let userName: String
    var username: String? = nil
    let userImage: UIImage?
    let rating: Double
    let completedJobs: Int
    let peopleHelped: Int
    let totalRatings: Int
    var isHirer: Bool = false
    var jobsPosted: Int = 0
    /// Global rank label like "#42 WORLDWIDE" or "TOP 5%". Pass `nil` to hide.
    var globalRankLabel: String? = nil

    var body: some View {
        ZStack {
            // Holographic mesh-style gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.07, blue: 0.22),  // deep indigo
                    Color(red: 0.27, green: 0.16, blue: 0.62),  // electric violet
                    Color(red: 0.10, green: 0.56, blue: 0.85),  // cyan-blue
                    Color(red: 0.18, green: 0.85, blue: 0.55)   // brand green
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Layered glow blobs for depth + "fire" vibe
            Circle()
                .fill(Color(red: 0.95, green: 0.40, blue: 0.85).opacity(0.55))
                .frame(width: 420)
                .blur(radius: 90)
                .offset(x: -180, y: -260)

            Circle()
                .fill(Color(red: 0.30, green: 0.95, blue: 0.70).opacity(0.55))
                .frame(width: 360)
                .blur(radius: 80)
                .offset(x: 200, y: 240)

            Circle()
                .fill(Color(red: 0.35, green: 0.65, blue: 1.00).opacity(0.45))
                .frame(width: 300)
                .blur(radius: 70)
                .offset(x: 0, y: 80)

            // Subtle vignette so the edges read clean
            LinearGradient(
                colors: [Color.black.opacity(0.0), Color.black.opacity(0.35)],
                startPoint: .top, endPoint: .bottom
            )

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image("CommunallyLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .shadow(color: .black.opacity(0.30), radius: 6, x: 0, y: 2)
                    Text("communally")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .tracking(-0.4)
                }
                .padding(.top, 56)

                if let label = globalRankLabel {
                    HStack(spacing: 6) {
                        Image(systemName: "globe.americas.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text(label)
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .tracking(1.2)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        Capsule().fill(.ultraThinMaterial)
                    )
                    .overlay(
                        Capsule().stroke(Color.white.opacity(0.55), lineWidth: 1)
                    )
                    .shadow(color: Color(red: 0.95, green: 0.40, blue: 0.85).opacity(0.5), radius: 14, x: 0, y: 4)
                    .padding(.top, 14)
                }

                Spacer()

                // Avatar with rainbow halo + outer glow
                ZStack {
                    Circle()
                        .fill(
                            AngularGradient(
                                gradient: Gradient(colors: [
                                    Color(red: 0.95, green: 0.40, blue: 0.85),
                                    Color(red: 0.35, green: 0.65, blue: 1.00),
                                    Color(red: 0.30, green: 0.95, blue: 0.70),
                                    Color(red: 1.00, green: 0.78, blue: 0.30),
                                    Color(red: 0.95, green: 0.40, blue: 0.85)
                                ]),
                                center: .center
                            )
                        )
                        .frame(width: 138, height: 138)
                        .blur(radius: 14)
                        .opacity(0.95)

                    Group {
                        if let img = userImage {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 120, height: 120)
                                .clipShape(Circle())
                        } else {
                            Circle()
                                .fill(Color.white.opacity(0.18))
                                .frame(width: 120, height: 120)
                                .overlay(
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 56))
                                        .foregroundColor(.white.opacity(0.85))
                                )
                        }
                    }
                    .overlay(Circle().stroke(Color.white.opacity(0.95), lineWidth: 4))
                    .shadow(color: .black.opacity(0.35), radius: 14, x: 0, y: 8)
                }
                .padding(.bottom, 18)

                Text(userName)
                    .font(.system(size: 32, weight: .heavy, design: .serif))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .shadow(color: .black.opacity(0.30), radius: 6, x: 0, y: 2)

                if let username, !username.isEmpty {
                    Text("@\(username)")
                        .font(.system(size: 16, weight: .medium, design: .serif))
                        .italic()
                        .foregroundColor(.white.opacity(0.78))
                        .padding(.top, 4)
                        .padding(.bottom, 14)
                } else {
                    Color.clear.frame(height: 14)
                }

                // Medal — cardboard placeholder for users with 0 jobs done.
                ShareTierMedal(jobsCompleted: isHirer ? jobsPosted : completedJobs)
                    .padding(.bottom, 14)

                // Single Jobs Done stat — centered, single column.
                ShareStatBox(
                    icon: "checkmark.seal.fill",
                    value: "\(isHirer ? jobsPosted : completedJobs)",
                    label: isHirer ? "Jobs Posted" : "Jobs Done"
                )
                .frame(maxWidth: 220)
                .padding(.horizontal, 36)
                .padding(.bottom, 16)

                // Rating BELOW the stat.
                if totalRatings > 0 {
                    VStack(spacing: 6) {
                        HStack(spacing: 3) {
                            ForEach(0..<5) { i in
                                let filled = rating >= Double(i + 1)
                                let half = !filled && rating >= Double(i) + 0.5
                                Image(systemName: filled ? "star.fill" : (half ? "star.leadinghalf.filled" : "star"))
                                    .foregroundColor(Color(red: 1.00, green: 0.85, blue: 0.30))
                                    .font(.system(size: 20))
                                    .shadow(color: Color(red: 1.00, green: 0.85, blue: 0.30).opacity(0.6), radius: 6)
                            }
                        }
                        Text(String(format: "%.1f  ·  %d rating%@", rating, totalRatings, totalRatings == 1 ? "" : "s"))
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.92))
                    }
                } else {
                    Text("Not rated yet")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.78))
                        .tracking(0.3)
                }

                Spacer()

                VStack(spacing: 6) {
                    Text("Join me on Communally")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .tracking(-0.3)
                    Text("Find local help or earn in your community")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.78))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 54)
            }
        }
        .frame(width: 540, height: 960)
    }
}

/// Tier medal shown above the stat on the share poster. Cardboard placeholder
/// for new users (0 jobs); upgrades to Bronze/Silver/Gold as they earn.
struct ShareTierMedal: View {
    let jobsCompleted: Int

    private var tier: SeekerRank? { SeekerRank.rank(forCompletedJobs: jobsCompleted) }

    var body: some View {
        if let tier {
            medal(
                iconName: tier.iconName,
                label: tier.rawValue,
                primary: tier.primaryColor,
                accent: tier.accentColor,
                glowColor: tier.accentColor.opacity(0.55)
            )
        } else {
            // "Unranked" placeholder — neutral grey so it reads as "no rank
            // yet" without competing with the real Bronze/Silver/Gold/Platinum
            // tiers below it.
            medal(
                iconName: "questionmark.circle.fill",
                label: "Unranked",
                primary: Color(red: 0.62, green: 0.64, blue: 0.68),
                accent: Color(red: 0.42, green: 0.44, blue: 0.48),
                glowColor: Color(red: 0.42, green: 0.44, blue: 0.48).opacity(0.40)
            )
        }
    }

    private func medal(iconName: String, label: String, primary: Color, accent: Color, glowColor: Color) -> some View {
        // Big glowing medallion + "RANK" label + tier name. Matches the
        // SeekerRankBadge profile design but scaled up for the share poster.
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(glowColor)
                    .frame(width: 64, height: 64)
                    .blur(radius: 10)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [primary, accent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 54, height: 54)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.55), lineWidth: 2)
                    )

                Image(systemName: iconName)
                    .font(.system(size: 26, weight: .black))
                    .foregroundColor(.white)
                    .shadow(color: accent.opacity(0.6), radius: 2, x: 0, y: 1)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("RANK")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .tracking(2.0)
                    .foregroundColor(.white.opacity(0.85))
                Text(label.uppercased())
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .tracking(0.6)
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [primary, accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.50), lineWidth: 1.25)
        )
        .shadow(color: glowColor, radius: 16, x: 0, y: 5)
    }
}

struct ShareStatBox: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 1.00, green: 0.78, blue: 0.30),
                            Color(red: 0.95, green: 0.40, blue: 0.85)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color(red: 0.95, green: 0.40, blue: 0.85).opacity(0.5), radius: 8, x: 0, y: 2)
            Text(value)
                .font(.system(size: 38, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .tracking(-0.5)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.85))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.30), lineWidth: 1)
        )
    }
}

// MARK: - Share Sheet
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let activityVC = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        
        // Exclude some activities to make Instagram Story more prominent
        activityVC.excludedActivityTypes = [
            .addToReadingList,
            .assignToContact,
            .openInIBooks,
            .markupAsPDF,
            .print
        ]
        
        // Set suggested actions to prioritize social sharing
        if #available(iOS 15.0, *) {
            // Instagram Stories will appear first in the share sheet
        }
        
        return activityVC
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Reviews List View
/// Full reviews screen pushed when the rating row on `UserProfileView` is tapped.
/// Filterable by star rating; uses the existing `RatingCard` for visual consistency.
struct ReviewsListView: View {
    let userId: String
    let userName: String
    let stats: UserRatingStats
    
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var ratingManager = RatingManager.shared
    @State private var selectedFilter: Int? = nil  // nil = all, 1...5 = star count
    
    private var allRatings: [Rating] {
        ratingManager.getRatings(forUser: userId)
    }
    
    private var filteredRatings: [Rating] {
        guard let stars = selectedFilter else { return allRatings }
        return allRatings.filter { Int($0.score) == stars }
    }
    
    private var summaryHeader: some View {
        VStack(spacing: 10) {
            if stats.hasRatings {
                Text(String(format: "%.1f", stats.averageScore))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundColor(CommunallyTheme.darkGray)
                    .monospacedDigit()
                
                HStack(spacing: 4) {
                    ForEach(0..<5) { index in
                        Image(systemName: index < Int(stats.averageScore) ? "star.fill" : "star")
                            .foregroundColor(.yellow)
                            .font(.system(size: 18))
                    }
                }
                
                Text("\(stats.totalRatings) rating\(stats.totalRatings == 1 ? "" : "s")")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.gray)
            } else {
                Image(systemName: "star")
                    .font(.system(size: 36))
                    .foregroundColor(CommunallyTheme.darkGray.opacity(0.4))
                Text("Not Rated yet")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(CommunallyTheme.darkGray.opacity(0.7))
                Text("Reviews from completed jobs will show up here.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
        )
        .padding(.horizontal)
    }
    
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ReviewsFilterChip(
                    label: "All",
                    isSelected: selectedFilter == nil
                ) {
                    selectedFilter = nil
                }
                
                ForEach((1...5).reversed(), id: \.self) { stars in
                    ReviewsFilterChip(
                        label: "\(stars)★",
                        isSelected: selectedFilter == stars
                    ) {
                        selectedFilter = stars
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    
    /// Inline back button rendered at the top of the scroll content. The
    /// dashboard's `safeAreaInset` swallows the navigation bar in this nested
    /// setup, so the standard toolbar back button never paints — this pill
    /// guarantees a back affordance regardless.
    private var inlineBackButton: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .bold))
                    Text("Back")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(CommunallyTheme.primaryGreen)
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.94))
                        .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 3)
                )
                .overlay(
                    Capsule()
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to profile")
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                inlineBackButton
                summaryHeader

                if !allRatings.isEmpty {
                    filterBar
                }
                
                if filteredRatings.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "text.bubble")
                            .font(.system(size: 32))
                            .foregroundColor(CommunallyTheme.darkGray.opacity(0.35))
                        Text(allRatings.isEmpty ? "No reviews yet" : "No reviews match this filter")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredRatings) { rating in
                            RatingCard(rating: rating)
                        }
                    }
                }
            }
            .padding(.bottom, 40)
        }
        .background(CommunallyTheme.backgroundGradient.ignoresSafeArea())
        .navigationTitle(userName.isEmpty ? "Reviews" : "Reviews")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundColor(CommunallyTheme.primaryGreen)
                }
                .accessibilityLabel("Back to profile")
            }
        }
    }
}

private struct ReviewsFilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isSelected ? .white : CommunallyTheme.darkGray)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? CommunallyTheme.primaryGreen : Color.white)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(
                            isSelected ? Color.clear : CommunallyTheme.darkGray.opacity(0.15),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Flow Layout for Skills
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }
                
                positions.append(CGPoint(x: x, y: y))
                lineHeight = max(lineHeight, size.height)
                x += size.width + spacing
            }
            
            self.size = CGSize(width: maxWidth, height: y + lineHeight)
        }
    }
}

