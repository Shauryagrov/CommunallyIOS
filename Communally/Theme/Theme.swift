//
//  Theme.swift
//  Communally
//
//  Created by Madhur Grover on 10/2/25.
//

import SwiftUI
import UIKit

struct CommunallyTheme {
    // Colors
    // NOTE: these tokens are now ADAPTIVE (Light/Dark). The brand greens stay
    // vivid in both modes; neutrals (gray/background/card) flip so the app
    // reads correctly in Dark mode without touching the ~900 call sites that
    // reference these names. See AdaptiveColor.swift.
    static let primaryGreen = Color.adaptive(
        light: UIColor(rgb: 0.18, 0.80, 0.44),
        dark:  UIColor(rgb: 0.22, 0.85, 0.50))   // Vibrant emerald-green
    static let secondaryGreen = Color.adaptive(
        light: UIColor(rgb: 0.12, 0.70, 0.36),
        dark:  UIColor(rgb: 0.16, 0.78, 0.42))
    static let accentGreen = Color.adaptive(
        light: UIColor(rgb: 0.08, 0.58, 0.28),
        dark:  UIColor(rgb: 0.30, 0.82, 0.50))   // brightened so it reads on dark
    static let lightGreen = Color.adaptive(
        light: UIColor(rgb: 0.28, 0.88, 0.52),
        dark:  UIColor(rgb: 0.34, 0.90, 0.58))
    static let white = Color.white
    static let lightGray = Color.adaptive(
        light: UIColor(rgb: 0.94, 0.95, 0.96),
        dark:  UIColor(rgb: 0.17, 0.18, 0.20))
    static let midGray = Color.adaptive(
        light: UIColor(rgb: 0.78, 0.80, 0.82),
        dark:  UIColor(rgb: 0.34, 0.36, 0.39))
    static let darkGray = Color.adaptive(
        light: UIColor(rgb: 0.15, 0.17, 0.20),
        dark:  UIColor(rgb: 0.92, 0.93, 0.94))   // primary text — flips to near-white
    static let backgroundTint = Color.adaptive(
        light: UIColor(rgb: 0.97, 1.0, 0.98),
        dark:  UIColor(rgb: 0.07, 0.09, 0.08))
    static let cardBackground = Color.adaptive(
        light: UIColor(rgb: 0.98, 0.99, 0.99),
        dark:  UIColor(rgb: 0.13, 0.14, 0.16))
    static let messageGreen = Color.adaptive(
        light: UIColor(rgb: 0.38, 0.90, 0.58),
        dark:  UIColor(rgb: 0.22, 0.55, 0.36))
    static let messageSoftBackground = Color.adaptive(
        light: UIColor(rgb: 0.93, 1.0, 0.95),
        dark:  UIColor(rgb: 0.12, 0.18, 0.14))

    // MARK: - Semantic surface / text tokens (adaptive)
    // Prefer these over raw Color.white / Color.black in new + migrated code.
    // Dark variants carry a subtle GREEN undertone (not flat gray) so the
    // dark theme reads as "Communally green-vibrant," not muddy.
    static let surface = Color.adaptive(            // page background
        light: .systemBackground,
        dark:  UIColor(rgb: 0.05, 0.08, 0.06))
    static let cardSurface = Color.adaptive(        // card / sheet fill
        light: .secondarySystemBackground,
        dark:  UIColor(rgb: 0.10, 0.15, 0.11))
    static let groupedSurface = Color.adaptive(     // nested rows inside a card
        light: .tertiarySystemBackground,
        dark:  UIColor(rgb: 0.14, 0.19, 0.15))
    static let textPrimary = Color(.label)
    static let textSecondary = Color(.secondaryLabel)
    static let textTertiary = Color(.tertiaryLabel)
    static let separator = Color(.separator)

    // Gradients
    // Adaptive: soft green wash over the page background in both modes. The
    // adaptive Color stops resolve per-trait when rendered, so Dark mode gets
    // a deep near-black instead of glaring white.
    static let backgroundGradient = LinearGradient(
        gradient: Gradient(stops: [
            .init(color: .adaptive(light: UIColor(rgb: 0.90, 0.99, 0.93),
                                   dark:  UIColor(rgb: 0.06, 0.11, 0.08)), location: 0),
            .init(color: .adaptive(light: .white, dark: UIColor(rgb: 0.07, 0.08, 0.09)), location: 0.4),
            .init(color: .adaptive(light: .white, dark: UIColor(rgb: 0.07, 0.08, 0.09)), location: 1)
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

    // Adaptive card fill (flat — cards shouldn't shimmer; gradient retired per
    // HIG "defer to content"). Kept as a LinearGradient type for call-site compat.
    static let cardGradient = LinearGradient(
        gradient: Gradient(colors: [cardSurface, cardSurface]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // Typography — SF (system font); .default matches standard Apple UI text
    static let titleFont = Font.system(size: 28, weight: .bold, design: .default)
    static let subtitleFont = Font.system(size: 20, weight: .semibold, design: .default)
    static let bodyFont = Font.system(size: 16, weight: .regular, design: .default)
    static let captionFont = Font.system(size: 14, weight: .medium, design: .default)
    static let labelFont = Font.system(size: 16, weight: .medium, design: .default)

    // MARK: - Semantic Dynamic Type ramp (preferred for new/migrated text)
    // These scale with the user's text-size setting (HIG: "Use Dynamic Type").
    // 5 roles — use these instead of inventing per-view Font.system(size:).
    static let screenTitle = Font.system(.title2, design: .default).weight(.bold)
    static let sectionHeader = Font.system(.headline, design: .default)
    static let bodyText = Font.system(.body, design: .default)
    static let secondaryText = Font.system(.subheadline, design: .default)
    static let captionText = Font.system(.caption, design: .default).weight(.medium)

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
            // Adaptive surface (was hardcoded Color.white → invisible text in Dark)
            .background(CommunallyTheme.cardSurface)
            .foregroundColor(CommunallyTheme.textPrimary)
            .cornerRadius(CommunallyTheme.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: CommunallyTheme.cornerRadius)
                    .stroke(CommunallyTheme.separator, lineWidth: 1)
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

// MARK: - Design System: spacing + radius scales
// Closed scales so geometry reads as one system (HIG: Layout consistency).
// Migrate ad-hoc paddings / the 15 live corner radii onto these over time.
enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum Radius {
    static let control: CGFloat = 12   // buttons, chips, fields
    static let card: CGFloat = 16      // cards, sheet content
    static let pill: CGFloat = 999     // pills, the floating tab bar
}

// MARK: - One elevation primitive
// A single card recipe: adaptive fill, one corner radius, one subtle shadow —
// no gradient stroke, no second shadow. Replaces the ~4 hand-rolled card
// backgrounds so elevation reads as one consistent light source (HIG: Materials).
struct CommunallyCard: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var padding: CGFloat = Spacing.lg
    var radius: CGFloat = Radius.card
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(CommunallyTheme.cardSurface)
            )
            // Soft green glow in Dark mode (vibrancy), neutral shadow in Light.
            .shadow(
                color: scheme == .dark
                    ? CommunallyTheme.primaryGreen.opacity(0.13)
                    : Color.black.opacity(0.06),
                radius: scheme == .dark ? 14 : 10, x: 0, y: 4
            )
    }
}

extension View {
    /// One consistent card surface + elevation. Prefer over bespoke
    /// `.background(RoundedRectangle…).shadow(…)` stacks.
    func communallyCard(padding: CGFloat = Spacing.lg, radius: CGFloat = Radius.card) -> some View {
        modifier(CommunallyCard(padding: padding, radius: radius))
    }
}
