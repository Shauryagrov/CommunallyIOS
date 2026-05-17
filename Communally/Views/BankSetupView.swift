//
//  BankSetupView.swift
//  Communally
//
//  Bank account setup - shown AFTER first job completion (not during signup)
//

import SwiftUI

// MARK: - Dashboard Banner (shows when user has pending earnings)
struct BankAccountBanner: View {
    let pendingAmount: String
    let onAddBank: () -> Void
    @State private var isPressed = false
    
    var body: some View {
        Button(action: onAddBank) {
            HStack(spacing: 18) {
                // Money icon with glow
                ZStack {
                    Circle()
                        .fill(CommunallyTheme.buttonGradient)
                        .frame(width: 60, height: 60)
                        .shadow(color: CommunallyTheme.primaryGreen.opacity(0.4), radius: 12, x: 0, y: 6)

                    Image(systemName: "dollarsign.circle.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 5) {
                    Text("💰 You Earned \(pendingAmount)!")
                        .font(.system(size: 19, weight: .bold, design: .default))
                        .foregroundColor(Color(red: 0.08, green: 0.08, blue: 0.08))
                    
                    Text("Add your bank to get paid")
                        .font(.system(size: 15, weight: .medium, design: .default))
                        .foregroundColor(Color(red: 0.4, green: 0.4, blue: 0.4))
                }
                
                Spacer()
                
                // Arrow
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(CommunallyTheme.primaryGreen)
            }
            .padding(22)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: CommunallyTheme.primaryGreen.opacity(0.18), radius: 20, x: 0, y: 10)
                    .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(CommunallyTheme.primaryGreen.opacity(0.28), lineWidth: 1.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isPressed ? 0.97 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Bank Setup Sheet
struct BankSetupSheet: View {
    /// When true, shows Stripe Connect status and what still needs to be fixed for payouts.
    private let showsVerificationDetails = true
    
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.scenePhase) var scenePhase
    @StateObject private var stripeService = StripeService.shared
    
    @State private var isLoading = false
    @State private var showSuccess = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var statusRetryCount = 0
    @State private var connectStatus: ConnectAccountStatus?
    @State private var isStaleAccountRetry = false
    
    /// Primary CTA — placed directly under the **Get Paid!** header so users see the
    /// incentive before scrolling through trust copy.
    @ViewBuilder
    private var connectBankAccountButton: some View {
        Button(action: connectBank) {
            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            } else if showSuccess {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Connected!")
                }
                .font(.system(size: 18, weight: .bold, design: .default))
            } else {
                HStack(spacing: 12) {
                    Image(systemName: connectButtonIcon)
                    Text(connectButtonTitle)
                }
                .font(.system(size: 18, weight: .bold, design: .default))
            }
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .frame(height: CommunallyTheme.buttonHeight)
        .background(CommunallyTheme.buttonGradient)
        .clipShape(RoundedRectangle(cornerRadius: CommunallyTheme.cornerRadius, style: .continuous))
        .shadow(color: CommunallyTheme.primaryGreen.opacity(0.35), radius: 15, x: 0, y: 8)
        .disabled(isLoading || showSuccess)
        .padding(.horizontal, 20)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                LinearGradient(
                    colors: [
                        Color(red: 0.95, green: 0.98, blue: 0.93),
                        Color.white
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 32) {
                        // Header
                        VStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.green, Color(red: 0.2, green: 0.8, blue: 0.6)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 100, height: 100)
                                    .shadow(color: Color.green.opacity(0.3), radius: 20, x: 0, y: 10)
                                
                                Image(systemName: "building.columns.fill")
                                    .font(.system(size: 48, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                            
                            Text("Get Paid!")
                                .font(.system(size: 32, weight: .bold, design: .default))
                                .foregroundColor(Color(red: 0.08, green: 0.08, blue: 0.08))
                            
                            Text("Connect your bank to receive\npayments for completed jobs")
                                .font(.system(size: 16, weight: .medium, design: .default))
                                .foregroundColor(Color(red: 0.4, green: 0.4, blue: 0.4))
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 20)

                        // Under-18 nudge: US Stripe Connect requires the
                        // account holder to be 18+. Teens have to hand
                        // this to a parent/guardian, who fills it out
                        // using THEIR name + ID + bank. Payouts land in
                        // the parent's account; the teen still tracks
                        // their earnings inside Communally.
                        if (authManager.currentUser?.resolvedAge ?? 99) < 18 {
                            teenParentalNotice
                                .padding(.horizontal, 20)
                        }

                        connectBankAccountButton

                        // Verification status card — pulled up directly under
                        // the Finish Verification button so the requirement
                        // list is the first thing the user sees after the CTA.
                        if showsVerificationDetails, !showSuccess {
                            if let connectStatus {
                                StripeVerificationStatusCard(
                                    title: statusTitle(for: connectStatus),
                                    message: statusMessage(for: connectStatus),
                                    items: actionItems(for: connectStatus),
                                    isResolved: connectStatus.isReadyForPayouts
                                )
                                .padding(.horizontal, 20)
                            } else if authManager.currentUser?.stripeConnectAccountId != nil {
                                HStack(spacing: 12) {
                                    ProgressView()
                                    Text("Checking your verification status with Stripe…")
                                        .font(.system(size: 14, weight: .medium, design: .default))
                                        .foregroundColor(Color(red: 0.4, green: 0.4, blue: 0.4))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(18)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color.white)
                                        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
                                )
                                .padding(.horizontal, 20)
                            }
                        }

                        // Security info
                        VStack(spacing: 16) {
                            SecurityFeatureRow(
                                icon: "lock.shield.fill",
                                title: "Bank-Level Security",
                                description: "256-bit encryption protects your data"
                            )

                            SecurityFeatureRow(
                                icon: "checkmark.seal.fill",
                                title: "Powered by Stripe",
                                description: "Trusted by millions of businesses"
                            )

                            SecurityFeatureRow(
                                icon: "bolt.fill",
                                title: "Fast Payouts",
                                description: "Get paid within 1-2 business days"
                            )
                        }
                        .padding(24)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color.white)
                                .shadow(color: Color.black.opacity(0.05), radius: 15, x: 0, y: 8)
                        )
                        .padding(.horizontal, 20)

                        if showsVerificationDetails {
                            verificationExplainerSection
                                .padding(.horizontal, 20)
                        }
                        
                        // Reset bank for testing (if already connected).
                        // DEBUG-only: App Store reviewers flag user-visible
                        // "(Testing)" controls as in-progress / incomplete UI.
                        // If you need to reset a Stripe Connect account in
                        // production, do it from the Stripe Dashboard.
                        #if DEBUG
                        if authManager.currentUser?.hasBankAccount == true && !isLoading && !showSuccess {
                            Button(action: resetBankConnection) {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.counterclockwise")
                                    Text("Reset Bank Connection (Testing)")
                                }
                                .font(.system(size: 14, weight: .medium))
                            }
                            .foregroundColor(.orange)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.orange, lineWidth: 1.5)
                            )
                        }
                        #endif
                        
                        // Skip for now
                        Button("I'll do this later") {
                            dismiss()
                        }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                        
                        Spacer(minLength: 40)
                    }
                }
            }
            .navigationTitle("Bank Setup")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                scheduleConnectStatusRefresh(resetRetries: true)
                // Pull the freshest user doc — the Stripe webhook may have
                // already updated stripeConnectActive on the cloud while we
                // were in Safari. Without this the app keeps showing the
                // pre-onboarding state.
                authManager.refreshCurrentUserFromCloud()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    scheduleConnectStatusRefresh(resetRetries: true)
                    authManager.refreshCurrentUserFromCloud()
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(Color(red: 0.7, green: 0.7, blue: 0.7))
                    }
                }
            }
            .alert("Connection Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    /// Friendly heads-up for under-18 seekers. Stripe Connect can't onboard
    /// minors in the US, so we redirect the teen to hand the setup to a
    /// parent/guardian who fills it out with the adult's info. Information
    /// only — doesn't block the user from tapping Connect Bank below.
    private var teenParentalNotice: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(Color(red: 0.85, green: 0.50, blue: 0.10))
                Text("Under 18? Hand this to a parent")
                    .font(.system(size: 15, weight: .bold, design: .default))
                    .foregroundColor(Color(red: 0.20, green: 0.20, blue: 0.20))
            }
            Text("Stripe (our payments partner) requires the bank-account holder to be 18 or older. Have a parent or guardian fill this out with **their** name, ID, and bank — payouts land in their account, and you'll still see every dollar you've earned right here in Communally.")
                .font(.system(size: 13, weight: .medium, design: .default))
                .foregroundColor(Color(red: 0.38, green: 0.38, blue: 0.38))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 1.0, green: 0.96, blue: 0.88))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(red: 0.95, green: 0.65, blue: 0.20).opacity(0.50), lineWidth: 1)
        )
    }

    private var verificationExplainerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "person.text.rectangle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.green)
                Text("What is verification?")
                    .font(.system(size: 17, weight: .bold, design: .default))
                    .foregroundColor(Color(red: 0.1, green: 0.1, blue: 0.1))
            }
            Text("Communally uses Stripe to send money to your bank. Stripe is required by law to confirm who you are and that your payout details are correct. That process is called verification.")
                .font(.system(size: 14, weight: .medium, design: .default))
                .foregroundColor(Color(red: 0.38, green: 0.38, blue: 0.38))
            Text("You may be asked for things like your legal name, address, date of birth, a government ID, and bank information. When something is still missing, we list it below so you can finish in Stripe’s secure flow.")
                .font(.system(size: 14, weight: .medium, design: .default))
                .foregroundColor(Color(red: 0.38, green: 0.38, blue: 0.38))
            if authManager.currentUser?.stripeConnectAccountId == nil {
                (
                    Text("Tap ") +
                    Text("Connect Bank Account")
                        .fontWeight(.bold) +
                    Text(" at the top to open Stripe. After you save details there, come back to this screen to see your status update.")
                )
                .font(.system(size: 14, weight: .semibold, design: .default))
                .foregroundColor(Color(red: 0.22, green: 0.45, blue: 0.28))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 15, x: 0, y: 8)
        )
    }
    
    private func connectBank() {
        guard let currentUser = authManager.currentUser else {
            errorMessage = "User not logged in"
            showError = true
            return
        }
        
        isLoading = true
        showError = false
        
        // Use REAL Stripe Connect
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            errorMessage = "Unable to open Stripe Connect"
            showError = true
            isLoading = false
            return
        }
        
        print("🏦 Opening REAL Stripe Connect for user: \(currentUser.fullName)")
        
        // Call the REAL Stripe service. We pass first/last name and DOB so
        // the backend can prefill the Stripe account at creation time — that
        // skips the "Business details", "Business type", and "Your name"
        // screens in Stripe's hosted onboarding form, cutting the flow down
        // to just the things Stripe is legally required to collect (address,
        // SSN last 4, bank/debit card).
        stripeService.connectBankAccount(
            for: currentUser.id,
            userEmail: currentUser.email,
            userName: currentUser.fullName,
            firstName: currentUser.firstName,
            lastName: currentUser.lastName,
            dateOfBirth: currentUser.dateOfBirth
        ) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                
                switch result {
                case .success(let accountId):
                    print("✅ Stripe Connect started. Account ID: \(accountId)")
                    // Save accountId immediately, but do not mark as connected yet.
                    self.updateUserBankStatus(
                        accountId: accountId,
                        isActive: false,
                        detailsSubmitted: false
                    )
                    
                    // Re-check status after the user returns from Stripe.
                    self.scheduleConnectStatusRefresh(resetRetries: true)
                    
                case .failure(let error):
                    let msg = error.localizedDescription
                    print("❌ Stripe Connect failed: \(msg)")
                    let isStaleAccount = msg.contains("not connected to your platform") || msg.contains("does not exist")
                    if isStaleAccount && !self.isStaleAccountRetry {
                        self.clearStaleConnectAccountAndRetry()
                    } else {
                        self.isStaleAccountRetry = false
                        self.errorMessage = msg
                        self.showError = true
                    }
                }
            }
        }
    }
    
    private func resetBankConnection() {
        guard var updatedUser = authManager.currentUser else { return }
        
        updatedUser = User(
            id: updatedUser.id,
            email: updatedUser.email,
            username: updatedUser.username,
            firstName: updatedUser.firstName,
            lastName: updatedUser.lastName,
            age: updatedUser.age,
            dateOfBirth: updatedUser.dateOfBirth,
            userType: updatedUser.userType,
            profileImageURL: updatedUser.profileImageURL,
            profileImageData: updatedUser.profileImageData,
            skills: updatedUser.skills,
            description: updatedUser.description,
            location: updatedUser.location,
            createdAt: updatedUser.createdAt,
            parentalConsentGiven: updatedUser.parentalConsentGiven,
            hasCompletedOnboarding: updatedUser.hasCompletedOnboarding,
            acceptedTermsDate: updatedUser.acceptedTermsDate,
            acceptedPrivacyDate: updatedUser.acceptedPrivacyDate,
            lastUsernameChange: updatedUser.lastUsernameChange,
            lastNameChange: updatedUser.lastNameChange,
            stripeCustomerId: updatedUser.stripeCustomerId,
            stripeConnectAccountId: nil,
            stripeConnectActive: false,
            stripeConnectDetailsSubmitted: false,
            bankAccountConnected: false,
            stripeConnectedAccountId: nil,
            appleUserId: updatedUser.appleUserId,
            legalFirstNameOnId: updatedUser.legalFirstNameOnId,
            legalLastNameOnId: updatedUser.legalLastNameOnId,
            identityDocumentURL: updatedUser.identityDocumentURL,
            identityVerificationSubmittedAt: updatedUser.identityVerificationSubmittedAt,
            verifiedHomeAddress: updatedUser.verifiedHomeAddress,
            verifiedHomeLatitude: updatedUser.verifiedHomeLatitude,
            verifiedHomeLongitude: updatedUser.verifiedHomeLongitude,
            stripeIdentityVerified: updatedUser.stripeIdentityVerified,
            stripeIdentityVerifiedAt: updatedUser.stripeIdentityVerifiedAt,
            stripeIdentityLastSessionId: updatedUser.stripeIdentityLastSessionId,
            qualificationAttachments: updatedUser.qualificationAttachments,
            profileBannerImageData: updatedUser.profileBannerImageData,
            pronouns: updatedUser.pronouns,
            bioAttachmentData: updatedUser.bioAttachmentData
        )
        authManager.updateUser(updatedUser)

        print("🔄 Reset bank connection for testing")
    }

    private func clearStaleConnectAccountAndRetry() {
        guard let current = authManager.currentUser else { return }
        print("🔄 Clearing stale Stripe Connect ID and retrying...")
        isStaleAccountRetry = true
        isLoading = true

        let cleared = User(
            id: current.id,
            email: current.email,
            username: current.username,
            firstName: current.firstName,
            lastName: current.lastName,
            age: current.age,
            dateOfBirth: current.dateOfBirth,
            userType: current.userType,
            profileImageURL: current.profileImageURL,
            profileImageData: current.profileImageData,
            skills: current.skills,
            description: current.description,
            location: current.location,
            createdAt: current.createdAt,
            parentalConsentGiven: current.parentalConsentGiven,
            hasCompletedOnboarding: current.hasCompletedOnboarding,
            acceptedTermsDate: current.acceptedTermsDate,
            acceptedPrivacyDate: current.acceptedPrivacyDate,
            lastUsernameChange: current.lastUsernameChange,
            lastNameChange: current.lastNameChange,
            stripeCustomerId: current.stripeCustomerId,
            stripeConnectAccountId: nil,
            stripeConnectActive: false,
            stripeConnectDetailsSubmitted: false,
            bankAccountConnected: false,
            stripeConnectedAccountId: nil,
            appleUserId: current.appleUserId,
            legalFirstNameOnId: current.legalFirstNameOnId,
            legalLastNameOnId: current.legalLastNameOnId,
            identityDocumentURL: current.identityDocumentURL,
            identityVerificationSubmittedAt: current.identityVerificationSubmittedAt,
            verifiedHomeAddress: current.verifiedHomeAddress,
            verifiedHomeLatitude: current.verifiedHomeLatitude,
            verifiedHomeLongitude: current.verifiedHomeLongitude,
            stripeIdentityVerified: current.stripeIdentityVerified,
            stripeIdentityVerifiedAt: current.stripeIdentityVerifiedAt,
            stripeIdentityLastSessionId: current.stripeIdentityLastSessionId,
            qualificationAttachments: current.qualificationAttachments,
            profileBannerImageData: current.profileBannerImageData,
            pronouns: current.pronouns,
            bioAttachmentData: current.bioAttachmentData
        )
        authManager.updateUser(cleared)

        // Give Firestore a moment to sync the cleared ID before the function reads it
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.connectBank()
        }
    }

    private func scheduleConnectStatusRefresh(resetRetries: Bool) {
        if resetRetries {
            statusRetryCount = 0
        }
        
        refreshConnectStatusIfNeeded()
    }
    
    private func refreshConnectStatusIfNeeded() {
        guard let accountId = authManager.currentUser?.stripeConnectAccountId else { return }
        
        stripeService.checkConnectAccountStatus(accountId: accountId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let status):
                    self.connectStatus = status
                    self.showSuccess = status.isReadyForPayouts
                    
                    self.updateUserBankStatus(
                        accountId: accountId,
                        isActive: status.isReadyForPayouts,
                        detailsSubmitted: status.detailsSubmitted
                    )
                    
                    if status.isReadyForPayouts {
                        let notification = UINotificationFeedbackGenerator()
                        notification.notificationOccurred(.success)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            self.dismiss()
                        }
                    } else if status.hasOutstandingRequirements {
                        // Stripe already knows exactly what is missing, so stop retrying
                        // and let the user fix the listed items.
                        self.statusRetryCount = 5
                    } else if self.statusRetryCount < 5 {
                        self.statusRetryCount += 1
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            self.refreshConnectStatusIfNeeded()
                        }
                    }
                case .failure(let error):
                    print("❌ Failed to check Connect status: \(error.localizedDescription)")
                    if self.statusRetryCount < 3 {
                        self.statusRetryCount += 1
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            self.refreshConnectStatusIfNeeded()
                        }
                    }
                }
            }
        }
    }
    
    private func updateUserBankStatus(accountId: String, isActive: Bool, detailsSubmitted: Bool) {
        guard var updatedUser = authManager.currentUser else { return }
        
        updatedUser = User(
            id: updatedUser.id,
            email: updatedUser.email,
            username: updatedUser.username,
            firstName: updatedUser.firstName,
            lastName: updatedUser.lastName,
            age: updatedUser.age,
            dateOfBirth: updatedUser.dateOfBirth,
            userType: updatedUser.userType,
            profileImageURL: updatedUser.profileImageURL,
            profileImageData: updatedUser.profileImageData,
            skills: updatedUser.skills,
            description: updatedUser.description,
            location: updatedUser.location,
            createdAt: updatedUser.createdAt,
            parentalConsentGiven: updatedUser.parentalConsentGiven,
            hasCompletedOnboarding: updatedUser.hasCompletedOnboarding,
            acceptedTermsDate: updatedUser.acceptedTermsDate,
            acceptedPrivacyDate: updatedUser.acceptedPrivacyDate,
            lastUsernameChange: updatedUser.lastUsernameChange,
            lastNameChange: updatedUser.lastNameChange,
            stripeCustomerId: updatedUser.stripeCustomerId,
            stripeConnectAccountId: accountId,
            stripeConnectActive: isActive,
            stripeConnectDetailsSubmitted: detailsSubmitted,
            bankAccountConnected: isActive,
            stripeConnectedAccountId: accountId,
            appleUserId: updatedUser.appleUserId,
            legalFirstNameOnId: updatedUser.legalFirstNameOnId,
            legalLastNameOnId: updatedUser.legalLastNameOnId,
            identityDocumentURL: updatedUser.identityDocumentURL,
            identityVerificationSubmittedAt: updatedUser.identityVerificationSubmittedAt,
            verifiedHomeAddress: updatedUser.verifiedHomeAddress,
            verifiedHomeLatitude: updatedUser.verifiedHomeLatitude,
            verifiedHomeLongitude: updatedUser.verifiedHomeLongitude,
            stripeIdentityVerified: updatedUser.stripeIdentityVerified,
            stripeIdentityVerifiedAt: updatedUser.stripeIdentityVerifiedAt,
            stripeIdentityLastSessionId: updatedUser.stripeIdentityLastSessionId,
            qualificationAttachments: updatedUser.qualificationAttachments,
            profileBannerImageData: updatedUser.profileBannerImageData,
            pronouns: updatedUser.pronouns,
            bioAttachmentData: updatedUser.bioAttachmentData,
            // Carry parental approval fields through. Without these the User
            // gets rebuilt with `isParentalApproved == nil`, which makes
            // ContentView re-show the parental gate after Stripe onboarding.
            parentEmail: updatedUser.parentEmail,
            parentName: updatedUser.parentName,
            parentApprovalToken: updatedUser.parentApprovalToken,
            isParentalApproved: updatedUser.isParentalApproved,
            parentApprovalDate: updatedUser.parentApprovalDate
        )

        authManager.updateUser(updatedUser, shouldSyncProfile: false)
    }
    
    private var connectButtonTitle: String {
        guard showsVerificationDetails else {
            return authManager.currentUser?.hasBankAccount == true ? "Reconnect Bank Account" : "Connect Bank Account"
        }
        
        if connectStatus?.hasOutstandingRequirements == true {
            return "Finish Verification"
        }
        
        if connectStatus?.detailsSubmitted == true && connectStatus?.isReadyForPayouts == false {
            return "Check Verification Status"
        }
        
        return authManager.currentUser?.hasBankAccount == true ? "Reconnect Bank Account" : "Connect Bank Account"
    }
    
    private var connectButtonIcon: String {
        guard showsVerificationDetails else {
            return "link"
        }
        
        return connectStatus?.hasOutstandingRequirements == true ? "exclamationmark.shield.fill" : "link"
    }
    
    private func statusTitle(for status: ConnectAccountStatus) -> String {
        if status.isReadyForPayouts {
            return "Bank account connected"
        }
        
        if status.hasOutstandingRequirements {
            return "Action needed to finish verification"
        }
        
        if !status.pendingVerification.isEmpty {
            return "Stripe is reviewing your info"
        }
        
        if status.detailsSubmitted {
            return "Verification submitted"
        }
        
        return "Bank setup not started"
    }
    
    private func statusMessage(for status: ConnectAccountStatus) -> String {
        if status.isReadyForPayouts {
            return "Your payout account is enabled and ready to receive money."
        }
        
        if status.hasOutstandingRequirements {
            let reason = disabledReasonDescription(for: status.disabledReason)
            return "Stripe still needs a few details before payouts can be enabled. \(reason)"
        }
        
        if !status.pendingVerification.isEmpty {
            return "Your details were submitted and are being reviewed. You usually do not need to resubmit unless Stripe asks again."
        }
        
        if status.detailsSubmitted {
            return "Your information was submitted, but Stripe has not enabled payouts yet. Reopen verification if you need to review anything."
        }
        
        return "Connect your bank account through Stripe to start receiving payments."
    }
    
    private func actionItems(for status: ConnectAccountStatus) -> [String] {
        let actionableFields = status.pastDue + status.currentlyDue
        let labels = actionableFields.map(friendlyLabel(for:))
        var uniqueLabels: [String] = []
        
        for label in labels where !uniqueLabels.contains(label) {
            uniqueLabels.append(label)
        }
        
        return uniqueLabels
    }
    
    private func disabledReasonDescription(for reason: String?) -> String {
        switch reason {
        case "requirements.past_due":
            return "Some required identity details are missing or incomplete."
        case "requirements.pending_verification":
            return "Stripe is waiting on verification for one or more details."
        case "requirements.disabled":
            return "Stripe has paused payouts until the requested details are fixed."
        default:
            return "Reopen Stripe and double-check the requested information."
        }
    }
    
    private func friendlyLabel(for field: String) -> String {
        switch field {
        case "individual.dob.day", "individual.dob.month", "individual.dob.year":
            return "Date of birth"
        case "individual.verification.document":
            return "Government ID"
        case "individual.email":
            return "Email address"
        case "individual.phone":
            return "Phone number"
        case "individual.first_name":
            return "First name"
        case "individual.last_name":
            return "Last name"
        case "individual.address.line1":
            return "Street address"
        case "individual.address.city":
            return "City"
        case "individual.address.state":
            return "State"
        case "individual.address.postal_code":
            return "ZIP code"
        default:
            return field
                .split(separator: ".")
                .last
                .map { $0.replacingOccurrences(of: "_", with: " ").capitalized } ?? field
        }
    }
}

// MARK: - Security Feature Row
struct SecurityFeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.12))
                    .frame(width: 50, height: 50)
                
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.green)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .default))
                    .foregroundColor(Color(red: 0.1, green: 0.1, blue: 0.1))
                
                Text(description)
                    .font(.system(size: 14, weight: .medium, design: .default))
                    .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
            }
            
            Spacer()
        }
    }
}

struct StripeVerificationStatusCard: View {
    let title: String
    let message: String
    let items: [String]
    let isResolved: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: isResolved ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(isResolved ? .green : .orange)
                
                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .default))
                    .foregroundColor(Color(red: 0.1, green: 0.1, blue: 0.1))
            }
            
            Text(message)
                .font(.system(size: 14, weight: .medium, design: .default))
                .foregroundColor(Color(red: 0.35, green: 0.35, blue: 0.35))
            
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(items, id: \.self) { item in
                        HStack(spacing: 8) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 6))
                                .foregroundColor(.orange)
                            Text(item)
                                .font(.system(size: 14, weight: .semibold, design: .default))
                                .foregroundColor(Color(red: 0.16, green: 0.16, blue: 0.16))
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white)
                .shadow(color: (isResolved ? Color.green : Color.orange).opacity(0.14), radius: 16, x: 0, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke((isResolved ? Color.green : Color.orange).opacity(0.25), lineWidth: 1.5)
        )
    }
}

#Preview {
    BankSetupSheet()
        .environmentObject(AuthenticationManager.shared)
}
