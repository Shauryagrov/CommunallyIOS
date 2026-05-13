                                    //
//  OnboardingFormComponents.swift
//  Communally
//
//  Shared profile-style onboarding UI (hirer + seeker).
//

import SwiftUI

// MARK: - Background & chrome

struct OnboardingFlowBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.97, green: 0.99, blue: 0.95),
                Color.white,
                Color(red: 0.98, green: 1.0, blue: 0.96)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

struct OnboardingHeaderBar: View {
    let currentStep: Int
    let totalSteps: Int
    /// Shown only on the first onboarding step (return to hirer/seeker choice).
    var showBackToSelection: Bool = true
    let onBackToSelection: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center) {
                Group {
                    if showBackToSelection {
                        Button(action: onBackToSelection) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(CommunallyTheme.primaryGreen)
                                .frame(width: 36, height: 36)
                                .background(
                                    Circle().fill(CommunallyTheme.primaryGreen.opacity(0.10))
                                )
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear.frame(width: 36, height: 36)
                    }
                }
                .frame(minWidth: 0, alignment: .leading)
                Spacer(minLength: 8)
                Text("Step \(currentStep + 1) of \(totalSteps)")
                    .font(.system(size: 13, weight: .medium, design: .default))
                    .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                    .multilineTextAlignment(.trailing)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            HStack(spacing: 8) {
                ForEach(0..<max(totalSteps, 1), id: \.self) { idx in
                    OnboardingStepDot(state: dotState(for: idx))
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .background(Color.white)
    }

    private func dotState(for idx: Int) -> OnboardingStepDot.State {
        if idx < currentStep { return .done }
        if idx == currentStep { return .current }
        return .upcoming
    }
}

struct OnboardingStepDot: View {
    enum State { case done, current, upcoming }
    let state: State

    var body: some View {
        Capsule()
            .fill(fill)
            .frame(height: 6)
            .frame(maxWidth: .infinity)
            .animation(.spring(response: 0.5, dampingFraction: 0.82), value: state)
    }

    private var fill: AnyShapeStyle {
        switch state {
        case .done:
            return AnyShapeStyle(CommunallyTheme.primaryGreen)
        case .current:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [CommunallyTheme.primaryGreen, CommunallyTheme.secondaryGreen],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        case .upcoming:
            return AnyShapeStyle(Color(red: 0.92, green: 0.93, blue: 0.94))
        }
    }
}

// MARK: - Text field (black border, matches reference)

struct OnboardingOutlinedTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.system(size: 14, weight: .regular, design: .default))
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(Color.white)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.black.opacity(0.85), lineWidth: 0.75)
            )
            .foregroundColor(.black)
    }
}

// MARK: - Profile photo

struct OnboardingProfilePhotoPicker: View {
    @Binding var image: UIImage?
    var onTap: () -> Void
    // Slimmed from 128 → 76 so the profile-creation screen fits on a 6.1"
    // device without scrolling (the date-of-birth picker was getting clipped).
    private let size: CGFloat = 76

    var body: some View {
        VStack(spacing: 6) {
            Button(action: onTap) {
                ZStack(alignment: .bottomTrailing) {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: size, height: size)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: [CommunallyTheme.primaryGreen, CommunallyTheme.secondaryGreen],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 2.5
                                    )
                            )
                    } else {
                        ZStack {
                            Circle()
                                .fill(CommunallyTheme.primaryGreen.opacity(0.10))
                                .frame(width: size, height: size)
                            Image(systemName: "person.fill")
                                .font(.system(size: 30))
                                .foregroundColor(CommunallyTheme.primaryGreen.opacity(0.45))
                        }
                        .overlay(
                            Circle()
                                .stroke(CommunallyTheme.primaryGreen.opacity(0.20), lineWidth: 1.5)
                        )
                    }

                    ZStack {
                        Circle()
                            .fill(CommunallyTheme.primaryGreen)
                            .frame(width: 26, height: 26)
                            .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 2)
                        Image(systemName: "camera.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .offset(x: -1, y: -1)
                }
            }
            .buttonStyle(.plain)

            Text(image == nil ? "Add a profile photo" : "Photo added")
                .font(.system(size: 12, weight: .medium, design: .default))
                .foregroundColor(image == nil ? CommunallyTheme.darkGray.opacity(0.55) : CommunallyTheme.primaryGreen)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Name + username

struct OnboardingNameFields: View {
    @Binding var firstName: String
    @Binding var lastName: String

    var body: some View {
        VStack(spacing: 14) {
            TextField(
                "",
                text: $firstName,
                prompt: Text("First Name").foregroundColor(Color(red: 0.45, green: 0.45, blue: 0.45))
            )
                .textFieldStyle(OnboardingOutlinedTextFieldStyle())
                .textContentType(.givenName)
            TextField(
                "",
                text: $lastName,
                prompt: Text("Last Name").foregroundColor(Color(red: 0.45, green: 0.45, blue: 0.45))
            )
                .textFieldStyle(OnboardingOutlinedTextFieldStyle())
                .textContentType(.familyName)
        }
    }
}

struct OnboardingUsernameField: View {
    @Binding var username: String
    let isChecking: Bool
    let isAvailable: Bool?
    let onUsernameChange: (String) -> Void

    /// Allowed: lowercase letters, digits, underscore, period. 3–20 chars.
    static let maxLength = 20
    static let minLength = 3
    private static let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_.")

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                Text("@")
                    .font(.system(size: 17, weight: .regular, design: .default))
                    .foregroundColor(.black)
                    .padding(.trailing, 8)
                TextField(
                    "",
                    text: $username,
                    prompt: Text("username").foregroundColor(Color(red: 0.45, green: 0.45, blue: 0.45))
                )
                    .textFieldStyle(OnboardingOutlinedTextFieldStyle())
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .textContentType(.username)
                    .onChange(of: username) { _, new in
                        let cleaned = sanitize(new)
                        if cleaned != new {
                            username = cleaned
                            return  // onChange will fire again with the cleaned value
                        }
                        onUsernameChange(cleaned)
                    }
            }

            HStack(spacing: 6) {
                if !username.isEmpty {
                    if username.count < Self.minLength {
                        Image(systemName: "info.circle.fill").foregroundColor(.gray)
                        Text("At least \(Self.minLength) characters")
                            .font(.system(size: 13, weight: .medium, design: .default))
                            .foregroundColor(.gray)
                    } else if isChecking {
                        ProgressView().scaleEffect(0.85)
                        Text("Checking…")
                            .font(.system(size: 13, weight: .medium, design: .default))
                            .foregroundColor(.gray)
                    } else if let available = isAvailable {
                        Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(available ? CommunallyTheme.primaryGreen : .red)
                        Text(available ? "Username available" : "Username taken")
                            .font(.system(size: 13, weight: .medium, design: .default))
                            .foregroundColor(available ? CommunallyTheme.primaryGreen : .red)
                    }
                }
                Spacer(minLength: 0)
                Text("\(username.count)/\(Self.maxLength)")
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .foregroundColor(username.count > Self.maxLength ? .red : Color(red: 0.55, green: 0.55, blue: 0.55))
            }
        }
    }

    /// Lowercase, strip disallowed characters, trim to maxLength.
    private func sanitize(_ raw: String) -> String {
        let lowered = raw.lowercased()
        let filtered = lowered.unicodeScalars.filter { Self.allowed.contains($0) }
        let str = String(String.UnicodeScalarView(filtered))
        return String(str.prefix(Self.maxLength))
    }
}

// MARK: - Age

struct OnboardingAgeStepperRow: View {
    @Binding var age: Int
    let minimumAge: Int
    var compact: Bool = false

    var body: some View {
        HStack {
            Text("🎂 Age:")
                .font(.system(size: compact ? 15 : 16, weight: .medium, design: .default))
                .foregroundColor(.black)
            Text("\(age)")
                .font(.system(size: compact ? 17 : 18, weight: .bold, design: .default))
                .foregroundColor(CommunallyTheme.primaryGreen)
            Spacer()
            HStack(spacing: compact ? 8 : 12) {
                Button {
                    if age > minimumAge { age -= 1 }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: compact ? 26 : 32))
                        .foregroundColor(age > minimumAge ? CommunallyTheme.primaryGreen : Color.gray.opacity(0.3))
                }
                .disabled(age <= minimumAge)

                Button {
                    if age < 100 { age += 1 }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: compact ? 26 : 32))
                        .foregroundColor(age < 100 ? CommunallyTheme.primaryGreen : Color.gray.opacity(0.3))
                }
                .disabled(age >= 100)
            }
        }
        .padding(.horizontal, compact ? 12 : 16)
        .padding(.vertical, compact ? 10 : 14)
        .background(Color.white)
        .cornerRadius(12)
    }
}

// MARK: - Date of birth (updates age automatically)

struct OnboardingDateOfBirthRow: View {
    @Binding var dateOfBirth: Date
    let minimumAge: Int
    var compact: Bool = false

    private var maxBirthDate: Date {
        Calendar.current.date(byAdding: .year, value: -minimumAge, to: Date()) ?? Date()
    }

    private var minBirthDate: Date {
        Calendar.current.date(byAdding: .year, value: -100, to: Date()) ?? Date()
    }

    private var displayedAge: Int {
        User.ageFromDateOfBirth(dateOfBirth)
    }

    var body: some View {
        // Single row: label · native compact date pill (opens iOS popover) ·
        // age chip. The full-height wheel picker was eating ~150pt and
        // forcing the screen to scroll. Compact picker collapses to ~32pt.
        HStack(alignment: .center, spacing: 10) {
            Text("🎂 Date of birth")
                .font(.system(size: compact ? 13 : 14, weight: .semibold, design: .default))
                .foregroundColor(.black)

            DatePicker(
                "",
                selection: $dateOfBirth,
                in: minBirthDate...maxBirthDate,
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .labelsHidden()
            .accentColor(CommunallyTheme.primaryGreen)
            .environment(\.colorScheme, .light)

            Spacer(minLength: 4)

            HStack(spacing: 4) {
                Text("Age")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(CommunallyTheme.darkGray.opacity(0.6))
                Text("\(displayedAge)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(CommunallyTheme.primaryGreen)
                    .monospacedDigit()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(CommunallyTheme.primaryGreen.opacity(0.10))
            )
        }
        .padding(.horizontal, compact ? 12 : 14)
        .padding(.vertical, compact ? 8 : 10)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - Info line

struct OnboardingInfoNote: View {
    let text: String
    var compact: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: compact ? 12 : 14))
                .foregroundColor(CommunallyTheme.primaryGreen)
            Text(text)
                .font(.system(size: compact ? 11 : 13, weight: .medium, design: .default))
                .foregroundColor(Color.gray)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, compact ? 2 : 6)
    }
}

// MARK: - Terms checkbox (tappable row)

struct OnboardingTermsAgreementRow: View {
    @Binding var accepted: Bool
    var onOpenTerms: () -> Void
    var onOpenPrivacy: (() -> Void)?
    var includePrivacyLinks: Bool
    /// Tighter copy and padding for seeker onboarding.
    var compact: Bool = false

    var body: some View {
        Group {
            if includePrivacyLinks {
                HStack(alignment: .top, spacing: compact ? 10 : 12) {
                    Button {
                        accepted.toggle()
                    } label: {
                        termsCheckbox
                    }
                    .buttonStyle(.plain)

                    if compact {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("15+ and I accept Terms & Privacy (incl. safety).")
                                .font(.system(size: 13, weight: .medium, design: .default))
                                .foregroundColor(.black)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 14) {
                                Button("Terms") { onOpenTerms() }
                                    .font(.system(size: 12, weight: .semibold, design: .default))
                                    .foregroundColor(CommunallyTheme.primaryGreen)
                                if let onOpenPrivacy {
                                    Button("Privacy") { onOpenPrivacy() }
                                        .font(.system(size: 12, weight: .semibold, design: .default))
                                        .foregroundColor(CommunallyTheme.primaryGreen)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            (
                                Text("I confirm I am 15 or older and accept the ")
                                    .font(.system(size: 15, weight: .regular, design: .default))
                                + Text("Terms")
                                    .font(.system(size: 15, weight: .semibold, design: .default))
                                    .foregroundColor(CommunallyTheme.primaryGreen)
                                    .underline()
                                + Text(", ")
                                    .font(.system(size: 15, weight: .regular, design: .default))
                                + Text("Privacy Policy")
                                    .font(.system(size: 15, weight: .semibold, design: .default))
                                    .foregroundColor(CommunallyTheme.primaryGreen)
                                    .underline()
                                + Text(", and safety practices.")
                                    .font(.system(size: 15, weight: .regular, design: .default))
                            )
                            .foregroundColor(.black)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                            HStack(spacing: 12) {
                                Button("View Terms") { onOpenTerms() }
                                    .font(.system(size: 13, weight: .semibold, design: .default))
                                    .foregroundColor(CommunallyTheme.primaryGreen)
                                if let onOpenPrivacy {
                                    Button("View Privacy") { onOpenPrivacy() }
                                        .font(.system(size: 13, weight: .semibold, design: .default))
                                        .foregroundColor(CommunallyTheme.primaryGreen)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, compact ? 12 : 16)
                .padding(.vertical, compact ? 10 : 14)
                .background(Color.white)
                .cornerRadius(12)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    Button {
                        accepted.toggle()
                    } label: {
                        termsCheckbox
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("I agree to the Terms of Service and Privacy Policy.")
                            .font(.system(size: 15, weight: .regular, design: .default))
                            .foregroundColor(.black)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 14) {
                            Button("Terms") { onOpenTerms() }
                                .font(.system(size: 13, weight: .semibold, design: .default))
                                .foregroundColor(CommunallyTheme.primaryGreen)
                            if let onOpenPrivacy {
                                Button("Privacy") { onOpenPrivacy() }
                                    .font(.system(size: 13, weight: .semibold, design: .default))
                                    .foregroundColor(CommunallyTheme.primaryGreen)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color.white)
                .cornerRadius(12)
            }
        }
    }

    private var termsCheckbox: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(accepted ? CommunallyTheme.primaryGreen : Color.gray.opacity(0.3), lineWidth: 2)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(accepted ? CommunallyTheme.primaryGreen : Color.clear)
                )
            if accepted {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
            }
        }
    }
}

// MARK: - Parental consent (seekers under 18)

struct OnboardingParentalConsentRow: View {
    @Binding var consentGiven: Bool
    var compact: Bool = false

    var body: some View {
        Button {
            consentGiven.toggle()
        } label: {
            HStack(alignment: .top, spacing: compact ? 10 : 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(consentGiven ? CommunallyTheme.primaryGreen : Color.gray.opacity(0.3), lineWidth: 2)
                        .frame(width: compact ? 22 : 24, height: compact ? 22 : 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(consentGiven ? CommunallyTheme.primaryGreen : Color.clear)
                        )
                    if consentGiven {
                        Image(systemName: "checkmark")
                            .font(.system(size: compact ? 10 : 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                VStack(alignment: .leading, spacing: compact ? 2 : 4) {
                    Text("My parent or guardian allows me to use Communally")
                        .font(.system(size: compact ? 13 : 15, weight: .semibold, design: .default))
                        .foregroundColor(.black)
                        .multilineTextAlignment(.leading)
                    Text("They know I may message adults about local jobs.")
                        .font(.system(size: compact ? 11 : 13, weight: .medium, design: .default))
                        .foregroundColor(.gray)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, compact ? 12 : 16)
            .padding(.vertical, compact ? 10 : 14)
            .background(Color.white)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Section title (inner steps)

struct OnboardingStepTitle: View {
    let emoji: String
    let title: String

    var body: some View {
        Text("\(emoji) \(title)")
            .font(.system(size: 26, weight: .bold, design: .default))
            .foregroundColor(.black)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
    }
}

// MARK: - Bottom bar

struct OnboardingBottomBar: View {
    let showBack: Bool
    let isLastStep: Bool
    let canProceed: Bool
    let isLoading: Bool
    let onBack: () -> Void
    let onContinue: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if showBack {
                Button(action: onBack) {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 17, weight: .semibold, design: .default))
                    }
                    .foregroundColor(Color(red: 0.3, green: 0.3, blue: 0.3))
                    .frame(height: 56)
                    .frame(maxWidth: 100)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(Color(red: 0.85, green: 0.85, blue: 0.85), lineWidth: 2)
                            )
                    )
                }
                .disabled(isLoading)
            }

            Button(action: onContinue) {
                Group {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.05)
                    } else {
                        HStack(spacing: 10) {
                            Text(isLastStep ? "Complete" : "Continue")
                                .font(.system(size: 17, weight: .bold, design: .default))
                            Image(systemName: isLastStep ? "checkmark.circle.fill" : "arrow.right")
                                .font(.system(size: 18, weight: .semibold))
                        }
                    }
                }
                .foregroundColor(.white)
                .frame(height: 56)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            canProceed && !isLoading
                                ? LinearGradient(
                                    colors: [CommunallyTheme.primaryGreen, CommunallyTheme.secondaryGreen],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                : LinearGradient(
                                    colors: [
                                        Color(red: 0.85, green: 0.85, blue: 0.85),
                                        Color(red: 0.8, green: 0.8, blue: 0.8)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                        )
                        .shadow(
                            color: (canProceed && !isLoading) ? CommunallyTheme.primaryGreen.opacity(0.3) : .clear,
                            radius: 15,
                            x: 0,
                            y: 8
                        )
                )
            }
            .disabled(!canProceed || isLoading)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(
            Color.white
                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: -5)
        )
    }
}
