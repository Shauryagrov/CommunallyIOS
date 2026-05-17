//
//  ParentalApprovalGateView.swift
//  Communally
//
//  Hard gate for under-18 seekers who haven't been approved by their parent.
//  Single path: tap "Share via Messages" → iOS share sheet → parent gets a
//  link → fills a mini form → user doc flips → gate auto-unlocks.
//

import SwiftUI

struct ParentalApprovalGateView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @StateObject private var service = ParentalApprovalService.shared

    @State private var inFlight = false
    @State private var statusText: String?
    @State private var statusIsError = false
    @State private var entered = false
    @State private var shareURL: URL?
    @State private var presentShareSheet = false

    var body: some View {
        ZStack {
            CommunallyTheme.backgroundGradient.ignoresSafeArea()

            Circle()
                .fill(CommunallyTheme.primaryGreen.opacity(0.10))
                .frame(width: 380, height: 380)
                .blur(radius: 90)
                .offset(x: -120, y: -260)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    heroIcon
                        .padding(.top, 32)

                    VStack(spacing: 10) {
                        Text("Get your parent's OK")
                            .font(.system(size: 26, weight: .bold, design: .default))
                            .foregroundColor(CommunallyTheme.darkGray)
                            .multilineTextAlignment(.center)
                        Text("Send your parent a one-time approval link. They'll fill out a quick form, and we'll unlock your account automatically.")
                            .font(.system(size: 15, weight: .medium, design: .default))
                            .foregroundColor(CommunallyTheme.darkGray.opacity(0.62))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                    }
                    .opacity(entered ? 1 : 0)
                    .offset(y: entered ? 0 : 12)

                    howItWorks
                        .padding(.horizontal, 4)

                    if let statusText {
                        Text(statusText)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(statusIsError ? .red : CommunallyTheme.primaryGreen)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                            .transition(.opacity)
                    }

                    primaryShareButton

                    Button(action: signOut) {
                        Text("Sign out")
                            .font(.system(size: 14, weight: .medium, design: .default))
                            .foregroundColor(CommunallyTheme.darkGray.opacity(0.6))
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 8)

                    #if DEBUG
                    Button(action: devForceApprove) {
                        Text("DEV: force approve")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.orange.opacity(0.7))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.orange.opacity(0.5), lineWidth: 1)
                            )
                    }
                    .padding(.bottom, 20)
                    #endif
                }
                .padding(.horizontal, 24)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.78)) { entered = true }
            // Always re-check the cloud copy so a stale local cache can't keep
            // the gate up after the parent has already approved.
            authManager.refreshCurrentUserFromCloud()
            if let userId = authManager.currentUser?.id {
                service.startObserving(userId: userId)
            }
        }
        .onDisappear { service.stopObserving() }
        .onChange(of: service.isApproved) { _, approved in
            guard approved else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            authManager.refreshCurrentUserFromCloud()
        }
    }

    // MARK: - Pieces

    private var heroIcon: some View {
        ZStack {
            Circle()
                .fill(CommunallyTheme.primaryGreen.opacity(0.12))
                .frame(width: 110, height: 110)
            Image(systemName: "message.badge.filled.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [CommunallyTheme.primaryGreen, CommunallyTheme.secondaryGreen],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .scaleEffect(entered ? 1 : 0.92)
        .opacity(entered ? 1 : 0)
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepRow(number: 1, title: "Tap Generate New Link + Share",
                    subtitle: "We'll create a one-time link and open the share sheet.")
            stepRow(number: 2, title: "Send it to your parent",
                    subtitle: "Pick them in Messages, send the link.")
            stepRow(number: 3, title: "They fill out a quick form",
                    subtitle: "Name, relationship, and a confirmation.")
            stepRow(number: 4, title: "You're in",
                    subtitle: "This screen unlocks the moment they submit.")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
        )
    }

    private func stepRow(number: Int, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(CommunallyTheme.primaryGreen.opacity(0.13))
                    .frame(width: 28, height: 28)
                Text("\(number)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(CommunallyTheme.primaryGreen)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .default))
                    .foregroundColor(CommunallyTheme.darkGray)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .foregroundColor(CommunallyTheme.darkGray.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    /// Single combined action: generates a fresh approval link AND opens the
    /// iOS share sheet in one tap. Earlier we had two buttons (generate, then
    /// share) and testers thought the share already happened after the first
    /// tap — this collapses that into one action so it's unambiguous.
    private var primaryShareButton: some View {
        Button(action: prepareAndShare) {
            buttonChrome(
                label: inFlight ? "Preparing link…" : "Generate New Link + Share",
                systemIcon: inFlight ? "message.fill" : "square.and.arrow.up.fill",
                spinning: inFlight
            )
        }
        .buttonStyle(.plain)
        .disabled(inFlight)
        .sheet(isPresented: $presentShareSheet) {
            if let url = shareURL {
                ShareSheet(activityItems: [shareMessageText, url])
            }
        }
    }

    private func buttonChrome(label: String, systemIcon: String, spinning: Bool) -> some View {
        HStack(spacing: 10) {
            if spinning {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(0.9)
            } else {
                Image(systemName: systemIcon)
                    .font(.system(size: 15, weight: .bold))
            }
            Text(label)
                .font(.system(size: 17, weight: .bold, design: .default))
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .frame(height: CommunallyTheme.buttonHeight)
        .background(CommunallyTheme.buttonGradient)
        .clipShape(RoundedRectangle(cornerRadius: CommunallyTheme.cornerRadius, style: .continuous))
        .shadow(color: CommunallyTheme.primaryGreen.opacity(0.40), radius: 12, x: 0, y: 6)
    }

    private var shareMessageText: String {
        let me = authManager.currentUser?.firstName ?? "Hi"
        return "\(me) here — I just signed up for Communally to find local jobs. Since I'm under 18, I need you to approve my account. Tap the link, fill out a quick form. Thanks! 💚"
    }

    // MARK: - Actions

    /// Generates a fresh approval link, then immediately presents the iOS
    /// share sheet. Always regenerates so the parent always gets a current
    /// (non-expired, non-consumed) link.
    private func prepareAndShare() {
        guard let user = authManager.currentUser else { return }
        inFlight = true
        statusText = nil
        ParentalApprovalService.shared.prepareShareableLink(
            userId: user.id,
            childFirstName: user.firstName,
            parentName: nil
        ) { result in
            DispatchQueue.main.async {
                inFlight = false
                switch result {
                case .success(let url):
                    shareURL = url
                    statusIsError = false
                    statusText = nil
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    presentShareSheet = true
                case .failure(let err):
                    statusText = err.localizedDescription
                    statusIsError = true
                }
            }
        }
    }

    private func signOut() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        authManager.signOut()
    }

    #if DEBUG
    private func devForceApprove() {
        guard let userId = authManager.currentUser?.id else { return }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        statusText = nil
        ParentalApprovalService.shared.devForceApprove(userId: userId) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    statusText = "DEV approved — refreshing…"
                    statusIsError = false
                    authManager.refreshCurrentUserFromCloud()
                case .failure(let err):
                    statusText = "DEV approve failed: \(err.localizedDescription)"
                    statusIsError = true
                }
            }
        }
    }
    #endif
}

#Preview {
    ParentalApprovalGateView()
        .environmentObject(AuthenticationManager.shared)
}
