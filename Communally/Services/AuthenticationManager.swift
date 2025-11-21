//
//  AuthenticationManager.swift
//  Communally
//
//  Created by Madhur Grover on 10/2/25.
//

import Foundation
import GoogleSignIn
import SwiftUI

class AuthenticationManager: ObservableObject {
    static let shared = AuthenticationManager()
    
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var isLoading = false
    
    private var isConfigured = false
    
    private init() {
        // Configure Google Sign-In only once
        if !isConfigured {
            configureGoogleSignIn()
            isConfigured = true
        }
        
        // Check if user was previously signed in
        checkPreviousSignIn()
    }
    
    private func checkPreviousSignIn() {
        // Check if we have a saved user
        if let _ = UserDefaults.standard.string(forKey: "savedUserId"),
           let savedUserData = UserDefaults.standard.data(forKey: "savedUser"),
           let decodedUser = try? JSONDecoder().decode(User.self, from: savedUserData) {
            
            // Restore the user
            currentUser = decodedUser
            isAuthenticated = decodedUser.hasCompletedOnboarding
            
            print("✅ Restored previous session for user: \(decodedUser.fullName)")
            print("📱 IsAuthenticated: \(isAuthenticated)")
        } else {
            print("ℹ️ No previous session found")
        }
    }
    
    private func saveUser() {
        if let user = currentUser,
           let encodedUser = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(user.id, forKey: "savedUserId")
            UserDefaults.standard.set(encodedUser, forKey: "savedUser")
            print("💾 Saved user data for: \(user.fullName)")
        }
    }
    
    private func clearSavedUser() {
        UserDefaults.standard.removeObject(forKey: "savedUserId")
        UserDefaults.standard.removeObject(forKey: "savedUser")
        print("🗑️ Cleared saved user data")
    }
    
    private func configureGoogleSignIn() {
        // Check if already configured
        if GIDSignIn.sharedInstance.configuration != nil {
            print("✅ Google Sign-In already configured")
            return
        }
        
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let plist = NSDictionary(contentsOfFile: path),
              let clientId = plist["CLIENT_ID"] as? String else {
            print("❌ GoogleService-Info.plist not found or CLIENT_ID missing")
            return
        }
        
        print("✅ Google Sign-In configured with CLIENT_ID: \(clientId)")
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: clientId,
            serverClientID: nil,
            hostedDomain: nil,
            openIDRealm: nil
        )
    }
    
    func signInWithGoogle() {
        isLoading = true
        
        guard let presentingViewController = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow })?.rootViewController else {
            isLoading = false
            return
        }
        
        GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController, hint: nil, additionalScopes: ["https://www.googleapis.com/auth/userinfo.email", "https://www.googleapis.com/auth/userinfo.profile"]) { [weak self] result, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    print("❌ Google Sign-In error: \(error.localizedDescription)")
                    print("❌ Error details: \(error)")
                    return
                }
                
                guard let user = result?.user else {
                    print("❌ No user returned from Google Sign-In")
                    return
                }
                
                // Try to get profile information with fallbacks
                let email = user.profile?.email ?? "user@example.com"
                let firstName = user.profile?.givenName ?? "User"
                let lastName = user.profile?.familyName ?? "Name"
                let googleId = user.userID ?? UUID().uuidString
                
                print("✅ Profile info - Email: \(email), Name: \(firstName) \(lastName)")
                print("🔍 Checking if user exists in database...")
                
                // Check if this Google account already exists in our database
                if let existingUser = UserDatabase.shared.getUser(byGoogleId: googleId) {
                    // User exists! Restore their account
                    print("✅ Found existing user: \(existingUser.fullName)")
                    print("📱 Restoring account with onboarding status: \(existingUser.hasCompletedOnboarding)")
                    
                    self?.currentUser = existingUser
                    self?.isAuthenticated = existingUser.hasCompletedOnboarding
                    self?.saveUser() // Save to current session
                    
                    print("✅ Account restored successfully!")
                } else {
                    // New user - create temporary user for onboarding
                    print("🆕 New user detected - creating account")
                    
                    let newUser = User(
                        id: googleId,
                        email: email,
                        firstName: firstName,
                        lastName: lastName,
                        age: 0, // Will be set during onboarding
                        userType: .jobSeeker, // Default, will be updated during onboarding
                        profileImageURL: user.profile?.imageURL(withDimension: 200)?.absoluteString,
                        profileImageData: nil, // Will be set during onboarding
                        skills: [],
                        description: nil,
                        location: nil,
                        createdAt: Date(),
                        isParentalApproved: nil,
                        hasCompletedOnboarding: false
                    )
                    
                    self?.currentUser = newUser
                    self?.saveUser() // Save to UserDefaults
                    UserDatabase.shared.saveUser(newUser) // Save to database
                    
                    print("🔧 AuthenticationManager: Created new user = \(newUser.fullName)")
                    print("🔧 AuthenticationManager: hasCompletedOnboarding = \(newUser.hasCompletedOnboarding)")
                    // Don't set isAuthenticated = true yet - wait for onboarding completion
                }
            }
        }
    }
    
    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        isAuthenticated = false
        currentUser = nil
        clearSavedUser() // Clear saved credentials from UserDefaults
        // NOTE: User data is still preserved in UserDatabase for re-login
    }
    
    func updateUser(_ user: User) {
        currentUser = user
        saveUser() // Save to current session
        UserDatabase.shared.saveUser(user) // Save to database
    }
    
    func completeOnboarding(user: User) {
        print("🔄 Starting completeOnboarding for user: \(user.fullName)")
        print("🔄 Current isAuthenticated: \(isAuthenticated)")
        print("🔄 User hasCompletedOnboarding: \(user.hasCompletedOnboarding)")
        
        currentUser = user
        isAuthenticated = true
        saveUser() // Save to current session
        UserDatabase.shared.saveUser(user) // Save to database
        
        print("✅ Onboarding completed for user: \(user.fullName)")
        print("✅ New isAuthenticated: \(isAuthenticated)")
        print("✅ New currentUser hasCompletedOnboarding: \(currentUser?.hasCompletedOnboarding ?? false)")
        print("💾 User saved to database for future logins")
    }
    
    // End of class
}
