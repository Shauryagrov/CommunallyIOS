//
//  EmailAuthView.swift
//  Communally
//
//  Email/password sign-in + create-account sheet.
//  Added to satisfy App Store Review Guideline 2.1(a) — reviewers need a way
//  to sign in without using a real Google/Apple ID.
//
//  Flow:
//    - Tap "Continue with email" on AuthenticationView → this sheet presents
//    - Mode toggles between Sign In and Create Account
//    - Sign In:   Auth.auth().signIn(withEmail:password:)
//    - Create:    Auth.auth().createUser(withEmail:password:) then routes
//                 through the existing onboarding flow (UserTypeSelectionView).
//    - Forgot password: Auth.auth().sendPasswordReset(withEmail:)
//
//  All three paths are wrapped in `AuthenticationManager.signInWithEmail` /
//  `createAccountWithEmail` / `sendPasswordReset` so the side-effects
//  (currentUser, isAuthenticated, Firestore sync) mirror Google/Apple sign-in.
//

import SwiftUI

struct EmailAuthView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) private var dismiss

    enum Mode { case signIn, createAccount }
    @State private var mode: Mode = .signIn

    @State private var email = ""
    @State private var password = ""
    @State private var firstName = ""
    @State private var lastName = ""

    @State private var errorMessage: String?
    @State private var infoMessage: String?
    @State private var isSubmitting = false

    @FocusState private var focusedField: Field?
    private enum Field { case firstName, lastName, email, password }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    header

                    if mode == .createAccount {
                        nameFields
                    }
                    emailField
                    passwordField

                    if let errorMessage = errorMessage {
                        errorBanner(errorMessage)
                    }
                    if let infoMessage = infoMessage {
                        infoBanner(infoMessage)
                    }

                    primaryButton

                    if mode == .signIn {
                        Button(action: forgotPassword) {
                            Text("Forgot password?")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(CommunallyTheme.accentGreen)
                        }
                        .padding(.top, 4)
                        .disabled(isSubmitting)
                    }

                    modeToggle
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color(red: 0.985, green: 0.99, blue: 0.985).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(CommunallyTheme.darkGray.opacity(0.7))
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(CommunallyTheme.accentGreen.opacity(0.12))
                    .frame(width: 56, height: 56)
                Image(systemName: "envelope.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(CommunallyTheme.primaryGreen)
            }
            Text(mode == .signIn ? "Welcome back" : "Create your account")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(CommunallyTheme.darkGray)
                .padding(.top, 4)
            Text(mode == .signIn
                 ? "Sign in with the email you used to create your Communally account."
                 : "Sign up with your email — same account works on iOS and the web.")
                .font(.system(size: 13))
                .foregroundStyle(CommunallyTheme.darkGray.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    // MARK: - Form fields

    private var nameFields: some View {
        HStack(spacing: 12) {
            field(label: "First name",
                  text: $firstName,
                  contentType: .givenName,
                  capitalization: .words,
                  focus: .firstName,
                  next: .lastName)
            field(label: "Last name",
                  text: $lastName,
                  contentType: .familyName,
                  capitalization: .words,
                  focus: .lastName,
                  next: .email)
        }
    }

    private var emailField: some View {
        field(label: "Email",
              text: $email,
              contentType: .emailAddress,
              keyboard: .emailAddress,
              capitalization: .never,
              focus: .email,
              next: .password)
    }

    private var passwordField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Password").font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CommunallyTheme.darkGray.opacity(0.55))
                .textCase(.uppercase)
                .tracking(0.5)
            SecureField("At least 6 characters", text: $password)
                .textContentType(mode == .signIn ? .password : .newPassword)
                .focused($focusedField, equals: .password)
                .submitLabel(.go)
                .onSubmit { submit() }
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(borderColor(for: .password), lineWidth: 1)
                )
        }
    }

    private func field(
        label: String,
        text: Binding<String>,
        contentType: UITextContentType,
        keyboard: UIKeyboardType = .default,
        capitalization: TextInputAutocapitalization,
        focus: Field,
        next: Field?
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CommunallyTheme.darkGray.opacity(0.55))
                .textCase(.uppercase)
                .tracking(0.5)
            TextField("", text: text)
                .textContentType(contentType)
                .keyboardType(keyboard)
                .textInputAutocapitalization(capitalization)
                .autocorrectionDisabled(contentType == .emailAddress)
                .focused($focusedField, equals: focus)
                .submitLabel(next == nil ? .go : .next)
                .onSubmit {
                    if let next = next { focusedField = next } else { submit() }
                }
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(borderColor(for: focus), lineWidth: 1)
                )
        }
    }

    private func borderColor(for f: Field) -> Color {
        if focusedField == f {
            return CommunallyTheme.accentGreen.opacity(0.6)
        }
        return Color.black.opacity(0.08)
    }

    // MARK: - Banners

    private func errorBanner(_ msg: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Color(red: 0.82, green: 0.27, blue: 0.27))
            Text(msg)
                .font(.system(size: 13))
                .foregroundStyle(Color(red: 0.45, green: 0.16, blue: 0.16))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(red: 0.99, green: 0.92, blue: 0.92))
        )
    }

    private func infoBanner(_ msg: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(CommunallyTheme.primaryGreen)
            Text(msg)
                .font(.system(size: 13))
                .foregroundStyle(CommunallyTheme.darkGray)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(CommunallyTheme.accentGreen.opacity(0.12))
        )
    }

    // MARK: - Primary action

    private var primaryButton: some View {
        Button(action: submit) {
            HStack(spacing: 8) {
                if isSubmitting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.85)
                }
                Text(mode == .signIn ? "Sign in" : "Create account")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(CommunallyTheme.primaryGreen.opacity(isSubmitting ? 0.7 : 1.0))
            )
        }
        .disabled(isSubmitting)
        .padding(.top, 6)
    }

    private var modeToggle: some View {
        HStack(spacing: 4) {
            Text(mode == .signIn ? "New to Communally?" : "Already have an account?")
                .font(.system(size: 13))
                .foregroundStyle(CommunallyTheme.darkGray.opacity(0.6))
            Button(action: {
                withAnimation(.easeInOut(duration: 0.18)) {
                    mode = (mode == .signIn) ? .createAccount : .signIn
                    errorMessage = nil
                    infoMessage = nil
                }
            }) {
                Text(mode == .signIn ? "Create account" : "Sign in")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CommunallyTheme.accentGreen)
            }
            .disabled(isSubmitting)
        }
        .padding(.top, 10)
    }

    // MARK: - Submit / forgot

    private func submit() {
        errorMessage = nil
        infoMessage  = nil
        isSubmitting = true

        switch mode {
        case .signIn:
            authManager.signInWithEmail(email: email, password: password) { result in
                handle(result, successDismiss: true)
            }
        case .createAccount:
            authManager.createAccountWithEmail(
                email: email,
                password: password,
                firstName: firstName,
                lastName: lastName
            ) { result in
                handle(result, successDismiss: true)
            }
        }
    }

    private func forgotPassword() {
        errorMessage = nil
        infoMessage  = nil
        guard !email.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Enter your email above first, then tap Forgot password."
            return
        }
        isSubmitting = true
        authManager.sendPasswordReset(email: email) { result in
            isSubmitting = false
            switch result {
            case .success:
                infoMessage = "Password reset link sent to \(email)."
            case .failure(let err):
                errorMessage = err.localizedDescription
            }
        }
    }

    private func handle(_ result: Result<Void, Error>, successDismiss: Bool) {
        isSubmitting = false
        switch result {
        case .success:
            if successDismiss { dismiss() }
        case .failure(let err):
            errorMessage = err.localizedDescription
        }
    }
}

#Preview {
    EmailAuthView().environmentObject(AuthenticationManager.shared)
}
