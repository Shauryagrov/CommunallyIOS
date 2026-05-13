//
//  UserTypeSelectionView.swift
//  Communally
//
//  Created by Madhur Grover on 10/2/25.
//

import SwiftUI
import GoogleSignIn

struct UserTypeSelectionView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var selectedUserType: UserType = .jobSeeker
    @State private var showOnboarding = false
    @State private var animateCards = false

    var body: some View {
        ZStack {
            // Beautiful green-to-white gradient background
            CommunallyTheme.backgroundGradient
                .ignoresSafeArea()
            
            // Decorative circles
            Circle()
                .fill(CommunallyTheme.primaryGreen.opacity(0.05))
                .frame(width: 300, height: 300)
                .offset(x: -150, y: -200)
                .blur(radius: 40)
            
            Circle()
                .fill(CommunallyTheme.secondaryGreen.opacity(0.05))
                .frame(width: 250, height: 250)
                .offset(x: 180, y: 300)
                .blur(radius: 40)
            
            VStack(spacing: 0) {
                // Back button — signs out so the user lands on the welcome/login screen.
                HStack {
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        authManager.signOut()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(CommunallyTheme.primaryGreen)
                            .frame(width: 36, height: 36)
                            .background(
                                Circle().fill(CommunallyTheme.primaryGreen.opacity(0.10))
                            )
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .opacity(animateCards ? 1.0 : 0.0)
                .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1), value: animateCards)
                
                Spacer()
                    .frame(height: 60)

                // Header — short, direct, serif headline. No hero icon; the
                // screen breathes more without it and the copy carries weight.
                VStack(spacing: 12) {
                    Text("What do you want to do?")
                        .font(.system(size: 30, weight: .bold, design: .serif))
                        .foregroundColor(Color(red: 0.10, green: 0.10, blue: 0.10))
                        .multilineTextAlignment(.center)
                        .tracking(-0.4)
                        .padding(.horizontal, 8)
                        .opacity(animateCards ? 1.0 : 0.0)
                        .offset(y: animateCards ? 0 : 20)
                        .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.18), value: animateCards)

                    Text("Earn money or get help nearby.")
                        .font(.system(size: 15, weight: .medium, design: .default))
                        .foregroundColor(Color(red: 0.42, green: 0.42, blue: 0.42))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .opacity(animateCards ? 1.0 : 0.0)
                        .offset(y: animateCards ? 0 : 20)
                        .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.24), value: animateCards)
                }
                .padding(.horizontal, 30)

                Spacer()
                    .frame(height: 40)

                // User Type Selection — minimal: title + one-line subtitle.
                VStack(spacing: 14) {
                    UserTypeCard(
                        title: "Earn Money",
                        subtitle: "Find nearby gigs",
                        iconSystemName: "hand.thumbsup.fill",
                        isSelected: selectedUserType == .jobSeeker,
                        animateIn: animateCards
                    ) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            selectedUserType = .jobSeeker
                        }
                    }
                    .opacity(animateCards ? 1.0 : 0.0)
                    .offset(x: animateCards ? 0 : -50)
                    .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.32), value: animateCards)

                    UserTypeCard(
                        title: "Get Help",
                        subtitle: "Post a job fast",
                        iconSystemName: "briefcase.fill",
                        isSelected: selectedUserType == .jobHirer,
                        animateIn: animateCards
                    ) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            selectedUserType = .jobHirer
                        }
                    }
                    .opacity(animateCards ? 1.0 : 0.0)
                    .offset(x: animateCards ? 0 : 50)
                    .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.40), value: animateCards)
                }
                .padding(.horizontal, 24)

                Spacer()

                // Continue Button — premium gradient + green halo shadow
                Button(action: {
                    let impactMed = UIImpactFeedbackGenerator(style: .medium)
                    impactMed.impactOccurred()
                    updateUserType()
                    showOnboarding = true
                }) {
                    HStack(spacing: 10) {
                        Text("Continue")
                            .font(.system(size: 17, weight: .bold, design: .default))
                            .tracking(0.2)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 15, weight: .heavy))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            CommunallyTheme.primaryGreen,
                                            CommunallyTheme.secondaryGreen
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            // Subtle top-edge highlight for that polished depth.
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.30), Color.white.opacity(0.0)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 1
                                )
                        }
                    )
                    .shadow(color: CommunallyTheme.primaryGreen.opacity(0.45), radius: 18, x: 0, y: 10)
                    .shadow(color: .black.opacity(0.10), radius: 8, x: 0, y: 4)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 50)
                .opacity(animateCards ? 1.0 : 0.0)
                .offset(y: animateCards ? 0 : 30)
                .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.6), value: animateCards)
            }
        }
        .onAppear {
            animateCards = true
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            if selectedUserType == .jobSeeker {
                JobSeekerOnboardingView()
                    .environmentObject(authManager)
            } else {
                JobHirerOnboardingView()
                    .environmentObject(authManager)
            }
        }
    }
    
    private func updateUserType() {
        guard let currentUser = authManager.currentUser else { return }
        
        let updatedUser = User(
            id: currentUser.id,
            email: currentUser.email,
            username: currentUser.username,
            firstName: currentUser.firstName,
            lastName: currentUser.lastName,
            age: currentUser.age,
            dateOfBirth: currentUser.dateOfBirth,
            userType: selectedUserType,
            profileImageURL: currentUser.profileImageURL,
            profileImageData: currentUser.profileImageData,
            skills: currentUser.skills,
            description: currentUser.description,
            location: currentUser.location,
            createdAt: currentUser.createdAt,
            parentalConsentGiven: currentUser.parentalConsentGiven,
            hasCompletedOnboarding: currentUser.hasCompletedOnboarding,
            acceptedTermsDate: currentUser.acceptedTermsDate,
            acceptedPrivacyDate: currentUser.acceptedPrivacyDate,
            lastUsernameChange: currentUser.lastUsernameChange,
            lastNameChange: currentUser.lastNameChange,
            stripeCustomerId: currentUser.stripeCustomerId,
            stripeConnectAccountId: currentUser.stripeConnectAccountId,
            stripeConnectActive: currentUser.stripeConnectActive,
            stripeConnectDetailsSubmitted: currentUser.stripeConnectDetailsSubmitted,
            bankAccountConnected: currentUser.bankAccountConnected,
            stripeConnectedAccountId: currentUser.stripeConnectedAccountId,
            appleUserId: currentUser.appleUserId,
            legalFirstNameOnId: currentUser.legalFirstNameOnId,
            legalLastNameOnId: currentUser.legalLastNameOnId,
            identityDocumentURL: currentUser.identityDocumentURL,
            identityVerificationSubmittedAt: currentUser.identityVerificationSubmittedAt,
            verifiedHomeAddress: currentUser.verifiedHomeAddress,
            verifiedHomeLatitude: currentUser.verifiedHomeLatitude,
            verifiedHomeLongitude: currentUser.verifiedHomeLongitude,
            stripeIdentityVerified: currentUser.stripeIdentityVerified,
            stripeIdentityVerifiedAt: currentUser.stripeIdentityVerifiedAt,
            stripeIdentityLastSessionId: currentUser.stripeIdentityLastSessionId,
            qualificationAttachments: currentUser.qualificationAttachments,
            profileBannerImageData: currentUser.profileBannerImageData,
            pronouns: currentUser.pronouns,
            bioAttachmentData: currentUser.bioAttachmentData,
            // Preserve parental approval state when role changes.
            parentEmail: currentUser.parentEmail,
            parentName: currentUser.parentName,
            parentApprovalToken: currentUser.parentApprovalToken,
            isParentalApproved: currentUser.isParentalApproved,
            parentApprovalDate: currentUser.parentApprovalDate
        )

        authManager.updateUser(updatedUser)
    }
}

/// Minimal role-selection card. Icon badge + title + one-line subtitle.
/// Selected state uses the brand button gradient + a green halo shadow;
/// unselected gets a soft gradient stroke and a much softer halo.
struct UserTypeCard: View {
    let title: String
    let subtitle: String
    let iconSystemName: String
    let isSelected: Bool
    let animateIn: Bool
    let action: () -> Void
    @State private var isPressed = false

    var body: some View {
        Button(action: {
            let impactLight = UIImpactFeedbackGenerator(style: .light)
            impactLight.impactOccurred()
            action()
        }) {
            HStack(alignment: .center, spacing: 14) {
                iconBadge
                contentColumn
                Spacer(minLength: 0)
                selectionDot
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(cardBackground)
            .shadow(color: shadowColor, radius: isSelected ? 20 : 14, x: 0, y: isSelected ? 10 : 6)
        }
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded   { _ in isPressed = false }
        )
    }

    // MARK: - Pieces

    private var iconBadge: some View {
        ZStack {
            // Soft outer halo when selected — adds the "expensive" feel.
            if isSelected {
                Circle()
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 60, height: 60)
                    .blur(radius: 10)
            }
            Circle()
                .fill(
                    isSelected
                    ? AnyShapeStyle(Color.white.opacity(0.22))
                    : AnyShapeStyle(LinearGradient(
                        colors: [
                            CommunallyTheme.primaryGreen.opacity(0.18),
                            CommunallyTheme.secondaryGreen.opacity(0.10)
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                )
                .frame(width: 50, height: 50)
                .overlay(
                    Circle().strokeBorder(
                        isSelected ? Color.white.opacity(0.40) : CommunallyTheme.primaryGreen.opacity(0.25),
                        lineWidth: 1
                    )
                )
            Image(systemName: iconSystemName)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(
                    isSelected
                    ? AnyShapeStyle(Color.white)
                    : AnyShapeStyle(LinearGradient(
                        colors: [CommunallyTheme.primaryGreen, CommunallyTheme.secondaryGreen],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                )
        }
    }

    private var contentColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .default))
                .foregroundColor(isSelected ? .white : CommunallyTheme.darkGray)
                .lineLimit(1)
            Text(subtitle)
                .font(.system(size: 14, weight: .medium, design: .default))
                .foregroundColor(isSelected ? .white.opacity(0.92) : Color(red: 0.42, green: 0.42, blue: 0.42))
                .lineLimit(1)
        }
    }

    private var selectionDot: some View {
        ZStack {
            Circle()
                .strokeBorder(
                    isSelected ? Color.white : Color(red: 0.85, green: 0.85, blue: 0.85),
                    lineWidth: 2.5
                )
                .frame(width: 26, height: 26)
            if isSelected {
                Circle().fill(Color.white).frame(width: 16, height: 16)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(CommunallyTheme.primaryGreen)
            }
        }
    }

    @ViewBuilder
    private var cardBackground: some View {
        if isSelected {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [CommunallyTheme.primaryGreen, CommunallyTheme.secondaryGreen],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                // Top-edge highlight gives the card depth — same trick as
                // the Continue button.
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.28), Color.white.opacity(0.0)],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            }
        } else {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    CommunallyTheme.primaryGreen.opacity(0.22),
                                    CommunallyTheme.secondaryGreen.opacity(0.08)
                                ],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.25
                        )
                )
        }
    }

    private var shadowColor: Color {
        isSelected
            ? CommunallyTheme.primaryGreen.opacity(0.40)
            : CommunallyTheme.primaryGreen.opacity(0.10)
    }
}

#Preview {
    UserTypeSelectionView()
        .environmentObject(AuthenticationManager.shared)
}
