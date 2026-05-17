//
//  Theme.swift
//  Communally
//
//  Created by Madhur Grover on 10/2/25.
//

import SwiftUI

struct CommunallyTheme {
    // Colors
    static let primaryGreen = Color(red: 0.18, green: 0.80, blue: 0.44)  // Vibrant emerald-green
    static let secondaryGreen = Color(red: 0.12, green: 0.70, blue: 0.36)
    static let accentGreen = Color(red: 0.08, green: 0.58, blue: 0.28)
    static let lightGreen = Color(red: 0.28, green: 0.88, blue: 0.52)
    static let white = Color.white
    static let lightGray = Color(red: 0.94, green: 0.95, blue: 0.96)
    static let midGray = Color(red: 0.78, green: 0.80, blue: 0.82)
    static let darkGray = Color(red: 0.15, green: 0.17, blue: 0.20)
    static let backgroundTint = Color(red: 0.97, green: 1.0, blue: 0.98)
    static let cardBackground = Color(red: 0.98, green: 0.99, blue: 0.99)
    static let messageGreen = Color(red: 0.38, green: 0.90, blue: 0.58)
    static let messageSoftBackground = Color(red: 0.93, green: 1.0, blue: 0.95)

    // Gradients
    static let backgroundGradient = LinearGradient(
        gradient: Gradient(stops: [
            .init(color: Color(red: 0.90, green: 0.99, blue: 0.93), location: 0),
            .init(color: Color.white, location: 0.4),
            .init(color: Color.white, location: 1)
        ]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Welcome / auth hero — calm, desaturated lime (yellow‑green, not teal; only on `AuthenticationView`).
    static let heroGradient = LinearGradient(
        gradient: Gradient(stops: [
            .init(color: Color(red: 0.94, green: 0.97, blue: 0.90), location: 0),
            .init(color: Color(red: 0.88, green: 0.94, blue: 0.80), location: 0.42),
            .init(color: Color(red: 0.78, green: 0.89, blue: 0.70), location: 0.78),
            .init(color: Color(red: 0.72, green: 0.84, blue: 0.64), location: 1)
        ]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Muted lime for soft glows on the auth hero (matches `heroGradient`, not `primaryGreen`).
    static let heroMutedLime = Color(red: 0.68, green: 0.82, blue: 0.58)

    static let buttonGradient = LinearGradient(
        gradient: Gradient(colors: [primaryGreen, secondaryGreen]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let cardGradient = LinearGradient(
        gradient: Gradient(colors: [Color.white, cardBackground]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // Typography — SF (system font); .default matches standard Apple UI text
    static let titleFont = Font.system(size: 28, weight: .bold, design: .default)
    static let subtitleFont = Font.system(size: 20, weight: .semibold, design: .default)
    static let bodyFont = Font.system(size: 16, weight: .regular, design: .default)
    static let captionFont = Font.system(size: 14, weight: .medium, design: .default)
    static let labelFont = Font.system(size: 16, weight: .medium, design: .default)

    // Spacing
    static let padding: CGFloat = 20
    static let smallPadding: CGFloat = 12
    static let largePadding: CGFloat = 32
    static let cornerRadius: CGFloat = 16
    static let cardCornerRadius: CGFloat = 20
    static let buttonHeight: CGFloat = 54
    
    // Button Styles
    static let primaryButtonStyle = PrimaryButtonStyle()
    static let secondaryButtonStyle = SecondaryButtonStyle()
    
    // Text Field Style
    static let textFieldStyle = CommunallyTextFieldStyle()
}

// MARK: - Button Styles
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold, design: .default))
            .foregroundColor(.white)
            .padding()
            .frame(height: CommunallyTheme.buttonHeight)
            .background(CommunallyTheme.buttonGradient)
            .clipShape(RoundedRectangle(cornerRadius: CommunallyTheme.cornerRadius, style: .continuous))
            .shadow(color: CommunallyTheme.primaryGreen.opacity(0.35), radius: 8, x: 0, y: 4)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold, design: .default))
            .foregroundColor(CommunallyTheme.darkGray)
            .padding()
            .frame(height: CommunallyTheme.buttonHeight)
            .background(CommunallyTheme.lightGray)
            .clipShape(RoundedRectangle(cornerRadius: CommunallyTheme.cornerRadius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Text Field Style
struct CommunallyTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding()
            .background(Color.white)
            .cornerRadius(CommunallyTheme.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: CommunallyTheme.cornerRadius)
                    .stroke(CommunallyTheme.lightGray, lineWidth: 1)
            )
    }
}

// MARK: - Green Text Border Modifier
struct GreenTextBorder: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}

extension View {
    func greenTextBorder() -> some View {
        modifier(GreenTextBorder())
    }
}
