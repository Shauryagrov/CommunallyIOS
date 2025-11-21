//
//  AuthenticationView.swift
//  Communally
//
//  Created by Madhur Grover on 10/2/25.
//

import SwiftUI
import GoogleSignIn
import Combine

struct AuthenticationView: View {
    @ObservedObject private var authManager = AuthenticationManager.shared
    @State private var showOnboarding = false
    
    var body: some View {
        ZStack {
            CommunallyTheme.backgroundGradient
                .ignoresSafeArea()
            
            VStack(spacing: 40) {
                Spacer()
                
                // App Logo/Title
                VStack(spacing: 20) {
                    Image("CommunallyLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 100, height: 100)
                    
                    Text("Communally")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(CommunallyTheme.darkGray)
                    
                    Text("Connect locally. Help globally.")
                        .font(CommunallyTheme.subtitleFont)
                        .foregroundColor(CommunallyTheme.darkGray.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .padding(30)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                )
                
                Spacer()
                
                // Sign In Section
                VStack(spacing: 20) {
                    Text("Get Started")
                        .font(CommunallyTheme.subtitleFont)
                        .foregroundColor(CommunallyTheme.darkGray)
                    
                    Button(action: {
                        authManager.signInWithGoogle()
                    }) {
                        HStack(spacing: 15) {
                            Image(systemName: "globe")
                                .font(.system(size: 20))
                            
                            Text("Continue with Google")
                                .font(CommunallyTheme.bodyFont)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: CommunallyTheme.buttonHeight)
                        .background(CommunallyTheme.buttonGradient)
                        .cornerRadius(CommunallyTheme.cornerRadius)
                    }
                    .interactiveButton(scale: 0.95, haptic: .medium)
                    .disabled(authManager.isLoading)
                    
                    if authManager.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: CommunallyTheme.primaryGreen))
                    }
                }
                
                Spacer()
                
                // Footer
                VStack(spacing: 10) {
                    Text("By continuing, you agree to our")
                        .font(CommunallyTheme.captionFont)
                        .foregroundColor(CommunallyTheme.darkGray.opacity(0.7))
                    
                    HStack(spacing: 20) {
                        Button("Terms of Service") {
                            // Show terms
                        }
                        .font(CommunallyTheme.captionFont)
                        .foregroundColor(CommunallyTheme.primaryGreen)
                        .smoothButton()
                        
                        Button("Privacy Policy") {
                            // Show privacy policy
                        }
                        .font(CommunallyTheme.captionFont)
                        .foregroundColor(CommunallyTheme.primaryGreen)
                        .smoothButton()
                    }
                }
                .padding(.bottom, 30)
            }
            .padding(.horizontal, CommunallyTheme.padding)
        }
        .onAppear {
            print("🔍 AuthenticationView: onAppear called")
            print("🔍 AuthenticationView: authManager.currentUser = \(authManager.currentUser?.fullName ?? "nil")")
            print("🔍 AuthenticationView: authManager.isAuthenticated = \(authManager.isAuthenticated)")
            print("🔍 AuthenticationView: showOnboarding = \(showOnboarding)")
            
            // Check if we need to show onboarding immediately
            if let user = authManager.currentUser, !user.hasCompletedOnboarding {
                print("🔍 AuthenticationView: onAppear - Setting showOnboarding = true")
                showOnboarding = true
            }
        }
        .onReceive(authManager.$currentUser) { user in
            print("🔍 AuthenticationView: onReceive currentUser = \(user?.fullName ?? "nil")")
            print("🔍 AuthenticationView: user?.hasCompletedOnboarding = \(user?.hasCompletedOnboarding ?? false)")
            print("🔍 AuthenticationView: showOnboarding = \(showOnboarding)")
            
            // When a user signs in, check if they need onboarding
            if let user = user, !user.hasCompletedOnboarding {
                print("🔍 AuthenticationView: Setting showOnboarding = true")
                showOnboarding = true
            } else if let user = user, user.hasCompletedOnboarding {
                // If user has completed onboarding, dismiss the onboarding flow
                print("🔍 AuthenticationView: Setting showOnboarding = false")
                showOnboarding = false
            }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            UserTypeSelectionView()
                .environmentObject(authManager)
        }
    }
}

#Preview {
    AuthenticationView()
}
