//
//  EmptyStateView.swift
//  Communally
//
//  Created by Madhur Grover on 10/2/25.
//

import SwiftUI

struct EmptyStateView: View {
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void
    /// Bambu pose for this empty state. Defaults to `.thinking` ("hmm,
    /// nothing here yet") which fits the search / no-results usage. Callers
    /// can pass a different pose for a different beat.
    var pose: BambuPose = .thinking

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(CommunallyTheme.primaryGreen.opacity(0.12))
                        .frame(width: 150, height: 150)
                        .blur(radius: 16)

                    BambuMascotView(size: 140, pose: pose)
                }

                VStack(spacing: 12) {
                    Text(title)
                        .font(.system(size: 24, weight: .bold, design: .default))
                        .foregroundColor(CommunallyTheme.darkGray)
                        .multilineTextAlignment(.center)

                    Text(message)
                        .font(.system(size: 16, weight: .medium, design: .default))
                        .foregroundColor(CommunallyTheme.darkGray.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 24)
                }
            }
            
            VStack(spacing: 14) {
                Button(action: {
                    let impactMed = UIImpactFeedbackGenerator(style: .medium)
                    impactMed.impactOccurred()
                    action()
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16, weight: .semibold))
                        Text(actionTitle)
                            .font(.system(size: 17, weight: .bold, design: .default))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(CommunallyTheme.buttonGradient)
                            .shadow(color: CommunallyTheme.primaryGreen.opacity(0.35), radius: 14, x: 0, y: 6)
                    )
                }
            }
            .padding(.horizontal, 24)
            
            Spacer()
        }
        .padding(24)
    }
}

#Preview {
    EmptyStateView(
        title: "No opportunities near you",
        message: "No opportunities near you right now. Try widening your radius or check back later.",
        actionTitle: "Refresh",
        action: {}
    )
}

// MARK: - Error state

/// Full-screen "something went wrong" view starring Bambu. Use for
/// load failures, network errors, etc. — anywhere you'd otherwise show
/// a bare error string. Pair with a retry action.
///
///     ErrorStateView(
///         title: "Couldn't load jobs",
///         message: "Check your connection and try again.",
///         retryTitle: "Retry"
///     ) { reload() }
struct ErrorStateView: View {
    var title: String = "Something went wrong"
    var message: String = "We hit a snag. Check your connection and try again."
    var retryTitle: String = "Try again"
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            ZStack {
                Circle()
                    .fill(CommunallyTheme.primaryGreen.opacity(0.10))
                    .frame(width: 150, height: 150)
                    .blur(radius: 16)
                // Thinking pose softens the failure — feels like "hmm, let
                // me look into that" rather than a hard red error wall.
                BambuMascotView(size: 140, pose: .thinking)
            }

            VStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(CommunallyTheme.darkGray)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(CommunallyTheme.darkGray.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 24)
            }

            Button(action: {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                retry()
            }) {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .semibold))
                    Text(retryTitle)
                        .font(.system(size: 17, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(CommunallyTheme.buttonGradient)
                        .shadow(color: CommunallyTheme.primaryGreen.opacity(0.35), radius: 14, x: 0, y: 6)
                )
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .padding(24)
    }
}

#Preview("Error") {
    ErrorStateView(
        title: "Couldn't load jobs",
        message: "Check your connection and try again.",
        retryTitle: "Retry"
    ) {}
}
