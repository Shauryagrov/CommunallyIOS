//
//  AuthenticationView.swift
//  Communally
//
//  Created by Madhur Grover on 10/2/25.
//

import SwiftUI
import GoogleSignIn
import AuthenticationServices

struct AuthenticationView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var showOnboarding = false
    @State private var showTerms = false
    @State private var showPrivacy = false

    // Entry animations — sheet is deliberately delayed so hero lands first
    @State private var heroVisible  = false
    @State private var sheetVisible = false

    var body: some View {
        ZStack(alignment: .bottom) {

            // ── Background ──────────────────────────────────────
            CommunallyTheme.heroGradient.ignoresSafeArea()

            Circle()
                .fill(RadialGradient(
                    colors: [CommunallyTheme.heroMutedLime.opacity(0.55), Color.clear],
                    center: .center, startRadius: 0, endRadius: 200
                ))
                .frame(width: 400, height: 400)
                .blur(radius: 40)
                .offset(x: 20, y: -180)
                .ignoresSafeArea()

            // ── Hero image — top-aligned, absolutely positioned.
            //   In its OWN layer so the image's height doesn't squeeze the
            //   text or push the sign-in sheet around. Tap-through enabled.
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Image("WelcomeHero")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 520, height: 880)
                        .clipped()
                        .offset(x: 70)
                }
                .padding(.top, 60)
                Spacer(minLength: 0)
            }
            .opacity(heroVisible ? 1 : 0)
            .offset(y: heroVisible ? 0 : 14)
            .animation(.easeOut(duration: 0.48).delay(0.05), value: heroVisible)
            .allowsHitTesting(false)

            // ── Headline + subtext — bottom-anchored above the sheet.
            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 8) {
                    Text("Your community is hiring.")
                        .font(.system(size: 26, weight: .bold, design: .default))
                        .tracking(-0.5)
                        .foregroundStyle(Color.white)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 24)
                        .shadow(color: .black.opacity(0.20), radius: 8, x: 0, y: 2)

                    Text("Same day. Same town. Real people.")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(CommunallyTheme.darkGray.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }
                .padding(.bottom, 350)   // clearance above the sign-in sheet
            }
            .opacity(heroVisible ? 1 : 0)
            .animation(.easeOut(duration: 0.48).delay(0.05), value: heroVisible)
            .allowsHitTesting(false)

            // ── Bottom sheet (delayed so hero is seen first) ──────
            VStack(spacing: 10) {
                // Apple — primary (filled black)
                SignInWithAppleButton(
                    .signIn,
                    onRequest: authManager.prepareAppleSignInRequest,
                    onCompletion: authManager.handleAppleSignInCompletion
                )
                .signInWithAppleButtonStyle(.black)
                .frame(height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .disabled(authManager.isLoading)

                // Google — secondary (outlined)
                Button { authManager.signInWithGoogle() } label: {
                    HStack(spacing: 10) {
                        GoogleLogoView(size: 18)
                        Text("Continue with Google")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(red: 0.13, green: 0.15, blue: 0.18))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.10), lineWidth: 1)
                    )
                }
                .buttonStyle(InteractiveButtonStyle(scaleAmount: 0.97, hapticStyle: .medium))
                .disabled(authManager.isLoading)

                if authManager.isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: CommunallyTheme.primaryGreen))
                            .scaleEffect(0.85)
                        Text("Signing in…")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color(red: 0.50, green: 0.52, blue: 0.54))
                    }
                    .frame(maxWidth: .infinity)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

                HStack(spacing: 4) {
                    Text("By continuing you agree to our")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Color(red: 0.42, green: 0.44, blue: 0.46))
                    Button("Terms") { showTerms = true }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CommunallyTheme.accentGreen)
                    Text("·")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(red: 0.65, green: 0.66, blue: 0.68))
                    Button("Privacy") { showPrivacy = true }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CommunallyTheme.accentGreen)
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: Color(red: 0.18, green: 0.22, blue: 0.16).opacity(0.16),
                            radius: 22, x: 0, y: 8)
            )
            .padding(.horizontal, 56)
            .padding(.bottom, 96)
            .offset(y: sheetVisible ? 0 : 80)
            .opacity(sheetVisible ? 1 : 0)
            .animation(.spring(response: 0.55, dampingFraction: 0.82).delay(1.1), value: sheetVisible)
        }
        .onAppear {
            heroVisible  = true
            sheetVisible = true

            if let user = authManager.currentUser, !user.hasCompletedOnboarding {
                showOnboarding = true
            }
        }
        .onReceive(authManager.$currentUser) { user in
            guard let user else { showOnboarding = false; return }
            showOnboarding = !user.hasCompletedOnboarding
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            UserTypeSelectionView().environmentObject(authManager)
        }
        .sheet(isPresented: $showTerms) {
            NavigationView { TermsAndConditionsView() }
        }
        .sheet(isPresented: $showPrivacy) {
            NavigationView { PrivacyPolicyView() }
        }
    }
}

#Preview {
    AuthenticationView()
        .environmentObject(AuthenticationManager.shared)
}
