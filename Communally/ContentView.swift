//
//  ContentView.swift
//  Communally
//
//  Created by Madhur Grover on 10/2/25.
//

import SwiftUI
import GoogleSignIn
import FirebaseCore

struct ContentView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var isFirebaseConfigured = false
    
    var body: some View {
        Group {
            // Check authentication first - allow development mode without Firebase
            if authManager.isAuthenticated {
                DashboardView()
                    .environmentObject(authManager)
                    .onAppear {
                        print("🏠 ContentView: Showing DashboardView")
                        print("🏠 ContentView: isAuthenticated = \(authManager.isAuthenticated)")
                        print("🏠 ContentView: currentUser = \(authManager.currentUser?.fullName ?? "nil")")
                        if !isFirebaseConfigured {
                            print("⚠️ Running in DEVELOPMENT MODE (No Firebase)")
                        }
                    }
            } else if !isFirebaseConfigured {
                // Only show Firebase setup if user is NOT authenticated
                FirebaseSetupRequiredView()
            } else {
                AuthenticationView()
                    .environmentObject(authManager)
                    .onAppear {
                        print("🔐 ContentView: Showing AuthenticationView")
                        print("🔐 ContentView: isAuthenticated = \(authManager.isAuthenticated)")
                        print("🔐 ContentView: currentUser = \(authManager.currentUser?.fullName ?? "nil")")
                    }
            }
        }
        .onAppear {
            checkFirebaseConfiguration()
        }
        .onReceive(authManager.$isAuthenticated) { isAuth in
            print("📡 ContentView: isAuthenticated changed to \(isAuth)")
        }
        .onReceive(authManager.$currentUser) { user in
            print("📡 ContentView: currentUser changed to \(user?.fullName ?? "nil")")
        }
    }
    
    private func checkFirebaseConfiguration() {
        isFirebaseConfigured = FirebaseApp.app() != nil
    }
}

// MARK: - Firebase Setup Required View

struct FirebaseSetupRequiredView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.97, green: 0.99, blue: 0.95),
                    Color.white,
                    Color(red: 0.98, green: 1.0, blue: 0.96)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 30) {
                Spacer()
                
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 120, height: 120)
                    
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 60, weight: .medium))
                        .foregroundColor(.orange)
                }
                
                // Title
                Text("Firebase Setup Required")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 0.15, green: 0.15, blue: 0.15))
                    .multilineTextAlignment(.center)
                
                // Message
                VStack(spacing: 16) {
                    Text("The app needs a valid Firebase configuration to run.")
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    
                    // Steps
                    VStack(alignment: .leading, spacing: 12) {
                        SetupStep(number: "1", text: "Go to Firebase Console")
                        SetupStep(number: "2", text: "Download GoogleService-Info.plist")
                        SetupStep(number: "3", text: "Replace the placeholder file")
                        SetupStep(number: "4", text: "Rebuild the app")
                    }
                    .padding(.horizontal, 40)
                    .padding(.top, 10)
                }
                
                // Documentation button
                VStack(spacing: 12) {
                    Text("See Documentation:")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(Color(red: 0.6, green: 0.6, blue: 0.6))
                    
                    HStack(spacing: 12) {
                        DocumentButton(title: "IMPORTANT_FIREBASE_SETUP.md")
                        DocumentButton(title: "APP_WONT_OPEN_FIX.md")
                    }
                }
                .padding(.top, 20)
                
                Spacer()
                
                // Console log notice
                Text("Check Xcode Console for detailed instructions")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Color(red: 0.7, green: 0.7, blue: 0.7))
                    .padding(.bottom, 40)
            }
        }
    }
}

struct SetupStep: View {
    let number: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.6, green: 0.4, blue: 1.0))
                    .frame(width: 28, height: 28)
                
                Text(number)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            Text(text)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(Color(red: 0.3, green: 0.3, blue: 0.3))
            
            Spacer()
        }
    }
}

struct DocumentButton: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundColor(Color(red: 0.6, green: 0.4, blue: 1.0))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(red: 0.6, green: 0.4, blue: 1.0).opacity(0.1))
            )
    }
}

#Preview {
    ContentView()
}
