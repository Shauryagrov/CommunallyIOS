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
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(CommunallyTheme.primaryGreen.opacity(0.12))
                        .frame(width: 140, height: 140)
                        .blur(radius: 16)

                    Circle()
                        .fill(CommunallyTheme.buttonGradient)
                        .frame(width: 100, height: 100)
                        .shadow(color: CommunallyTheme.primaryGreen.opacity(0.35), radius: 14, x: 0, y: 6)

                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundColor(.white)
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
