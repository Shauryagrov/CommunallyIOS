//
//  StripeIdentityVerificationView.swift
//  Communally
//

import SwiftUI
import StripeIdentity
import UIKit

private enum StripeIdentityPresentation {
    static func topViewController(from base: UIViewController? = nil) -> UIViewController? {
        let root: UIViewController?
        if let base = base {
            root = base
        } else {
            root = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .filter { $0.activationState == .foregroundActive }
                .flatMap(\.windows)
                .first { $0.isKeyWindow }?
                .rootViewController
        }
        if let nav = root as? UINavigationController {
            return topViewController(from: nav.visibleViewController)
        }
        if let tab = root as? UITabBarController {
            return topViewController(from: tab.selectedViewController)
        }
        if let presented = root?.presentedViewController {
            return topViewController(from: presented)
        }
        return root
    }

    static func presentVerification(clientSecret: String, onResult: @escaping (IdentityVerificationSheet.VerificationFlowResult) -> Void) {
        guard let host = topViewController() else {
            onResult(.flowFailed(error: NSError(
                domain: "StripeIdentity",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not open verification screen."]
            )))
            return
        }
        let sheet = IdentityVerificationSheet(verificationSessionClientSecret: clientSecret)
        sheet.present(from: host, completion: onResult)
    }
}

struct StripeIdentityVerificationView: View {
    /// Pass `false` when used as a full-screen gate — hides the Close button so the user can't skip.
    var allowDismiss: Bool = true

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: AuthenticationManager

    @State private var isStarting = false
    @State private var isPolling = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        ZStack {
            CommunallyTheme.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                if allowDismiss {
                    HStack {
                        Spacer()
                        Button("Close") { dismiss() }
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(CommunallyTheme.darkGray.opacity(0.55))
                            .padding(.horizontal, 24)
                            .padding(.top, 16)
                    }
                } else {
                    HStack {
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            authManager.signOut()
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Back to Login")
                                    .font(.system(size: 15, weight: .semibold, design: .default))
                            }
                            .foregroundColor(CommunallyTheme.primaryGreen)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                }

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // MARK: Hero
                        VStack(spacing: 18) {
                            ZStack {
                                Circle()
                                    .fill(CommunallyTheme.primaryGreen.opacity(0.12))
                                    .frame(width: 110, height: 110)
                                Circle()
                                    .fill(CommunallyTheme.primaryGreen.opacity(0.07))
                                    .frame(width: 140, height: 140)
                                Image(systemName: isPolling ? "clock.badge.checkmark" : "checkmark.shield.fill")
                                    .font(.system(size: 52, weight: .semibold))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [CommunallyTheme.primaryGreen, CommunallyTheme.secondaryGreen],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .symbolEffect(.pulse, isActive: isPolling)
                            }
                            .padding(.top, 12)

                            VStack(spacing: 8) {
                                Text(isPolling ? "Confirming…" : "One last step")
                                    .font(.system(size: 30, weight: .bold, design: .default))
                                    .foregroundStyle(CommunallyTheme.darkGray)

                                Text(isPolling
                                    ? "Stripe is processing your verification. This usually takes just a moment."
                                    : "Verify your identity to join the Communally community and keep everyone safe."
                                )
                                    .font(.system(size: 15, weight: .medium, design: .default))
                                    .foregroundStyle(CommunallyTheme.darkGray.opacity(0.6))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 8)
                            }
                        }
                        .padding(.horizontal, 28)

                        Spacer().frame(height: 36)

                        // MARK: What happens cards
                        if !isPolling {
                            VStack(spacing: 12) {
                                verificationStepCard(
                                    icon: "person.text.rectangle.fill",
                                    iconColor: Color(red: 0.25, green: 0.60, blue: 1.0),
                                    title: "Government ID",
                                    subtitle: "Driver's license, passport, or state ID"
                                )
                                verificationStepCard(
                                    icon: "faceid",
                                    iconColor: CommunallyTheme.primaryGreen,
                                    title: "Quick selfie",
                                    subtitle: "Stripe matches your face to your ID"
                                )
                                verificationStepCard(
                                    icon: "bolt.shield.fill",
                                    iconColor: Color(red: 0.58, green: 0.28, blue: 0.98),
                                    title: "Instant result",
                                    subtitle: "Takes about 60 seconds — then you're in"
                                )
                            }
                            .padding(.horizontal, 24)

                            Spacer().frame(height: 20)

                            // Privacy note
                            HStack(spacing: 8) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(CommunallyTheme.darkGray.opacity(0.4))
                                Text("Communally never sees or stores your ID images. Stripe handles everything securely.")
                                    .font(.system(size: 12, weight: .medium, design: .default))
                                    .foregroundStyle(CommunallyTheme.darkGray.opacity(0.45))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.horizontal, 28)
                        }

                        // MARK: Polling spinner
                        if isPolling {
                            VStack(spacing: 16) {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: CommunallyTheme.primaryGreen))
                                    .scaleEffect(1.3)
                                Text("Waiting for Stripe…")
                                    .font(.system(size: 14, weight: .semibold, design: .default))
                                    .foregroundStyle(CommunallyTheme.darkGray.opacity(0.5))
                            }
                            .padding(.top, 32)
                        }

                        Spacer().frame(height: 36)
                    }
                }

                // MARK: CTA
                if !isPolling {
                    VStack(spacing: 12) {
                        Button {
                            startVerification()
                        } label: {
                            HStack(spacing: 10) {
                                if isStarting {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.9)
                                }
                                Text(isStarting ? "Opening Stripe…" : "Verify My Identity")
                                    .font(.system(size: 17, weight: .bold, design: .default))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: CommunallyTheme.buttonHeight)
                            .background(
                                LinearGradient(
                                    colors: isStarting
                                        ? [CommunallyTheme.primaryGreen.opacity(0.7), CommunallyTheme.secondaryGreen.opacity(0.7)]
                                        : [CommunallyTheme.primaryGreen, CommunallyTheme.secondaryGreen],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: CommunallyTheme.primaryGreen.opacity(0.35), radius: 12, x: 0, y: 6)
                        }
                        .disabled(isStarting)
                        .buttonStyle(.plain)

                        Text("Powered by Stripe Identity")
                            .font(.system(size: 12, weight: .medium, design: .default))
                            .foregroundStyle(CommunallyTheme.darkGray.opacity(0.35))
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 36)
                }
            }
        }
        .interactiveDismissDisabled(!allowDismiss)
        .alert("Verification Error", isPresented: $showError) {
            Button("Try Again", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Step card
    private func verificationStepCard(icon: String, iconColor: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .default))
                    .foregroundStyle(CommunallyTheme.darkGray)
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium, design: .default))
                    .foregroundStyle(CommunallyTheme.darkGray.opacity(0.55))
            }

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 4)
        )
    }

    // MARK: - Logic
    private func startVerification() {
        guard !isStarting else { return }
        isStarting = true

        StripeIdentityVerificationService.fetchVerificationClientSecret { result in
            switch result {
            case .failure(let error):
                isStarting = false
                errorMessage = error.localizedDescription
                showError = true
            case .success(let secret):
                StripeIdentityPresentation.presentVerification(clientSecret: secret) { flowResult in
                    DispatchQueue.main.async {
                        isStarting = false
                        switch flowResult {
                        case .flowCompleted:
                            isPolling = true
                            pollForVerifiedUser(attempt: 0)
                        case .flowCanceled:
                            break
                        case .flowFailed(let error):
                            errorMessage = error.localizedDescription
                            showError = true
                        }
                    }
                }
            }
        }
    }

    /// Webhook may lag slightly after the sheet completes; retry up to ~10 seconds.
    private func pollForVerifiedUser(attempt: Int) {
        guard let uid = authManager.currentUser?.id else {
            dismiss()
            return
        }
        if attempt > 10 {
            isPolling = false
            errorMessage = "Stripe is still processing. Come back in a minute and reopen the app."
            showError = true
            return
        }

        UserDatabase.shared.fetchUserFromFirebase(byUserId: uid) { user in
            DispatchQueue.main.async {
                guard let user else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        pollForVerifiedUser(attempt: attempt + 1)
                    }
                    return
                }
                if user.isStripeIdentityVerified {
                    authManager.updateUser(user, shouldSyncProfile: false)
                    dismiss()
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    pollForVerifiedUser(attempt: attempt + 1)
                }
            }
        }
    }
}

#Preview {
    StripeIdentityVerificationView()
        .environmentObject(AuthenticationManager.shared)
}
