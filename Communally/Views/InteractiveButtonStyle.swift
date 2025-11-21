//
//  InteractiveButtonStyle.swift
//  Communally
//
//  Premium interactive button style with press animations and haptics
//

import SwiftUI

// MARK: - Interactive Button Style
struct InteractiveButtonStyle: ButtonStyle {
    var scaleAmount: CGFloat = 0.92
    var hapticStyle: UIImpactFeedbackGenerator.FeedbackStyle = .medium
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scaleAmount : 1.0)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) {
                if configuration.isPressed {
                    let impact = UIImpactFeedbackGenerator(style: hapticStyle)
                    impact.impactOccurred()
                }
            }
    }
}

// MARK: - Bouncy Button Style (More Dramatic)
struct BouncyButtonStyle: ButtonStyle {
    var scaleAmount: CGFloat = 0.88
    var bounceScale: CGFloat = 1.05
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scaleAmount : 1.0)
            .brightness(configuration.isPressed ? -0.08 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.5), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) {
                if configuration.isPressed {
                    let impact = UIImpactFeedbackGenerator(style: .medium)
                    impact.impactOccurred()
                }
            }
    }
}

// MARK: - Grow Button Style (Expands on Press)
struct GrowButtonStyle: ButtonStyle {
    var growScale: CGFloat = 1.08
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? growScale : 1.0)
            .brightness(configuration.isPressed ? 0.05 : 0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) {
                if configuration.isPressed {
                    let impact = UIImpactFeedbackGenerator(style: .light)
                    impact.impactOccurred()
                }
            }
    }
}

// MARK: - Pulsing Button Style (With Glow)
struct PulsingButtonStyle: ButtonStyle {
    @State private var isPulsing = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .shadow(
                color: configuration.isPressed ? .green.opacity(0.4) : .green.opacity(0.2),
                radius: configuration.isPressed ? 15 : 10,
                x: 0,
                y: configuration.isPressed ? 6 : 4
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) {
                if configuration.isPressed {
                    let impact = UIImpactFeedbackGenerator(style: .medium)
                    impact.impactOccurred()
                }
            }
    }
}

// MARK: - Smooth Scale Button Style (Subtle)
struct SmoothScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) {
                if configuration.isPressed {
                    let impact = UIImpactFeedbackGenerator(style: .light)
                    impact.impactOccurred()
                }
            }
    }
}

// MARK: - View Extensions
extension View {
    /// Apply interactive button style with press feedback
    func interactiveButton(scale: CGFloat = 0.92, haptic: UIImpactFeedbackGenerator.FeedbackStyle = .medium) -> some View {
        self.buttonStyle(InteractiveButtonStyle(scaleAmount: scale, hapticStyle: haptic))
    }
    
    /// Apply bouncy button style
    func bouncyButton(scale: CGFloat = 0.88) -> some View {
        self.buttonStyle(BouncyButtonStyle(scaleAmount: scale))
    }
    
    /// Apply grow button style (expands on press)
    func growButton(scale: CGFloat = 1.08) -> some View {
        self.buttonStyle(GrowButtonStyle(growScale: scale))
    }
    
    /// Apply pulsing button style with glow
    func pulsingButton() -> some View {
        self.buttonStyle(PulsingButtonStyle())
    }
    
    /// Apply smooth scale button style (subtle)
    func smoothButton() -> some View {
        self.buttonStyle(SmoothScaleButtonStyle())
    }
}

