//
//  AuthenticationManager.swift
//  Communally
//
//  Created by Madhur Grover on 10/2/25.
//

import Foundation
import GoogleSignIn
import SwiftUI
import AuthenticationServices
import CoreLocation
import FirebaseAuth
import FirebaseFirestore

class AuthenticationManager: ObservableObject {
    static let shared = AuthenticationManager()
    
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var isLoading = false
    @Published var isRestoringSession = true
    
    private var isConfigured = false
    
    private init() {
        // Configure Google Sign-In only once
        if !isConfigured {
            configureGoogleSignIn()
            isConfigured = true
        }
        
        restoreSavedUserIfAvailable()
        
        // Check if user was previously signed in
        checkPreviousSignIn()
    }
    
    private func checkPreviousSignIn() {
        guard GIDSignIn.sharedInstance.hasPreviousSignIn() else {
            print("ℹ️ No previous Google session found")
            isRestoringSession = false
            return
        }
        
        GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] user, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let error = error {
                    print("⚠️ Failed to restore previous Google session: \(error.localizedDescription)")
                    self.isRestoringSession = false
                    return
                }
                
                guard let googleUser = user, let googleId = googleUser.userID else {
                    self.isRestoringSession = false
                    return
                }
                
                Task { @MainActor in
                    let sessionOk = await FirebaseAuthSessionSync.establishSessionFromGoogleUser(googleUser)
                    if !sessionOk {
                        print("⚠️ Could not restore Firebase Auth — try signing in again. Check mintCustomAuthToken / GOOGLE_IOS_CLIENT_ID.")
                        self.isRestoringSession = false
                        return
                    }
                    
                    UserDatabase.shared.fetchUserFromFirebase(byGoogleId: googleId) { fetchedUser in
                        DispatchQueue.main.async {
                            if let fetchedUser = fetchedUser {
                                self.restoreUser(fetchedUser, googleUserForAuth: googleUser)
                                self.isRestoringSession = false
                                return
                            }
                            
                            if let savedUserData = UserDefaults.standard.data(forKey: "savedUser"),
                               let decodedUser = try? JSONDecoder().decode(User.self, from: savedUserData),
                               decodedUser.id == googleId {
                                self.restoreUser(decodedUser, googleUserForAuth: googleUser)
                                self.isRestoringSession = false
                            } else {
                                print("ℹ️ No matching saved user for restored Google account")
                                self.isRestoringSession = false
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func restoreSavedUserIfAvailable() {
        guard let savedUserData = UserDefaults.standard.data(forKey: "savedUser"),
              let decodedUser = try? JSONDecoder().decode(User.self, from: savedUserData) else {
            return
        }
        
        currentUser = decodedUser
        isAuthenticated = decodedUser.hasCompletedOnboarding
        print("💾 Restored saved user immediately: \(decodedUser.fullName)")
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
                guard let self = self else { return }
                
                if let error = error {
                    self.isLoading = false
                    print("❌ Google Sign-In error: \(error.localizedDescription)")
                    print("❌ Error details: \(error)")
                    return
                }
                
                guard let user = result?.user else {
                    self.isLoading = false
                    print("❌ No user returned from Google Sign-In")
                    return
                }
                
                // Firestore rules require Firebase Auth first; mint custom token, then read `users/{googleId}`.
                Task { @MainActor in
                    let sessionOk = await FirebaseAuthSessionSync.establishSessionFromGoogleUser(user)
                    if !sessionOk {
                        self.isLoading = false
                        print("⚠️ Firebase Auth session not established — Firestore reads will fail. Check Cloud Function mintCustomAuthToken and GOOGLE_IOS_CLIENT_ID in firebase-functions/.env")
                        return
                    }
                    
                    let email = user.profile?.email ?? "user@example.com"
                    let firstName = user.profile?.givenName ?? "User"
                    let lastName = user.profile?.familyName ?? "Name"
                    let googleId = user.userID ?? UUID().uuidString
                    
                    print("✅ Profile info - Email: \(email), Name: \(firstName) \(lastName)")
                    print("🔍 Checking if user exists in database (after Firebase Auth)...")
                    
                    UserDatabase.shared.fetchUserFromFirebase(byGoogleId: googleId) { fetchedUser in
                        DispatchQueue.main.async {
                            if let fetchedUser = fetchedUser {
                                print("☁️ Found existing cloud user: \(fetchedUser.fullName)")
                                self.restoreUser(fetchedUser, googleUserForAuth: user)
                                self.isLoading = false
                                return
                            }
                            
                            if let existingUser = UserDatabase.shared.getUser(byGoogleId: googleId) {
                                print("✅ Found existing local user: \(existingUser.fullName)")
                                print("📱 Restoring account with onboarding status: \(existingUser.hasCompletedOnboarding)")
                                self.restoreUser(existingUser, googleUserForAuth: user)
                                self.isLoading = false
                                return
                            }
                            
                            print("🆕 New user detected - creating account")
                            
                            let newUser = User(
                                id: googleId,
                                email: email,
                                username: nil,
                                firstName: firstName,
                                lastName: lastName,
                                age: 0,
                                dateOfBirth: nil,
                                userType: .jobSeeker,
                                profileImageURL: user.profile?.imageURL(withDimension: 200)?.absoluteString,
                                profileImageData: nil,
                                skills: [],
                                description: nil,
                                location: nil,
                                createdAt: Date(),
                                parentalConsentGiven: nil,
                                hasCompletedOnboarding: false,
                                acceptedTermsDate: nil,
                                acceptedPrivacyDate: nil,
                                lastUsernameChange: nil,
                                lastNameChange: nil,
                                stripeCustomerId: nil,
                                stripeConnectAccountId: nil,
                                stripeConnectActive: nil,
                                stripeConnectDetailsSubmitted: nil,
                                bankAccountConnected: nil,
                                stripeConnectedAccountId: nil,
                                appleUserId: nil,
                                legalFirstNameOnId: nil,
                                legalLastNameOnId: nil,
                                identityDocumentURL: nil,
                                identityVerificationSubmittedAt: nil,
                                verifiedHomeAddress: nil,
                                verifiedHomeLatitude: nil,
                                verifiedHomeLongitude: nil,
                                stripeIdentityVerified: nil,
                                stripeIdentityVerifiedAt: nil,
                                stripeIdentityLastSessionId: nil,
                                qualificationAttachments: nil
                            )
                            
                            self.currentUser = newUser
                            self.saveUser()
                            UserDatabase.shared.saveUser(newUser)
                            print("🔧 AuthenticationManager: Created new user = \(newUser.fullName)")
                            self.isLoading = false
                        }
                    }
                }
            }
        }
    }
    
    func prepareAppleSignInRequest(_ request: ASAuthorizationAppleIDRequest) {
        isLoading = true
        request.requestedScopes = [.fullName, .email]
    }
    
    func handleAppleSignInCompletion(_ result: Result<ASAuthorization, Error>) {
        DispatchQueue.main.async {
            self.isLoading = false
        }
        
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                print("❌ Apple Sign-In returned an unexpected credential type")
                return
            }
            
            signInWithAppleCredential(credential)
            
        case .failure(let error):
            print("❌ Apple Sign-In error: \(error.localizedDescription)")
        }
    }
    
    private func restoreUser(
        _ user: User,
        googleUserForAuth: GIDGoogleUser? = nil,
        appleIdentityToken: Data? = nil
    ) {
        currentUser = user
        isAuthenticated = user.hasCompletedOnboarding
        saveUser()
        UserDatabase.shared.saveUser(user)
        print("✅ Account restored successfully!")
        Task {
            await FirebaseAuthSessionSync.signInWithMintedTokenIfNeeded(
                userId: user.id,
                googleIDToken: googleUserForAuth?.idToken?.tokenString,
                appleIdentityToken: appleIdentityToken
            )
        }
    }
    
    private func signInWithAppleCredential(_ credential: ASAuthorizationAppleIDCredential) {
        let appleUserId = credential.user
        let email = credential.email?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullName = credential.fullName
        let appleToken = credential.identityToken
        
        if let localAppleUser = UserDatabase.shared.getUser(byAppleUserId: appleUserId) {
            restoreUser(linkAppleIdentityIfNeeded(for: localAppleUser, appleUserId: appleUserId), appleIdentityToken: appleToken)
            return
        }
        
        UserDatabase.shared.fetchUserFromFirebase(byAppleUserId: appleUserId) { [weak self] appleUser in
            guard let self = self else { return }
            
            if let appleUser = appleUser {
                self.restoreUser(self.linkAppleIdentityIfNeeded(for: appleUser, appleUserId: appleUserId), appleIdentityToken: appleToken)
                return
            }
            
            self.restoreAppleUserByEmailOrCreate(
                appleUserId: appleUserId,
                email: email,
                fullName: fullName,
                appleIdentityToken: appleToken
            )
        }
    }
    
    private func restoreAppleUserByEmailOrCreate(
        appleUserId: String,
        email: String?,
        fullName: PersonNameComponents?,
        appleIdentityToken: Data?
    ) {
        if let email, let localUser = UserDatabase.shared.getUser(byEmail: email) {
            restoreUser(linkAppleIdentityIfNeeded(for: localUser, appleUserId: appleUserId), appleIdentityToken: appleIdentityToken)
            return
        }
        
        if let email {
            UserDatabase.shared.fetchUserFromFirebase(byEmail: email) { [weak self] cloudUser in
                guard let self = self else { return }
                
                if let cloudUser = cloudUser {
                    self.restoreUser(self.linkAppleIdentityIfNeeded(for: cloudUser, appleUserId: appleUserId), appleIdentityToken: appleIdentityToken)
                    return
                }
                
                self.restoreAppleSavedUserOrCreate(
                    appleUserId: appleUserId,
                    email: email,
                    fullName: fullName,
                    appleIdentityToken: appleIdentityToken
                )
            }
            return
        }
        
        restoreAppleSavedUserOrCreate(
            appleUserId: appleUserId,
            email: email,
            fullName: fullName,
            appleIdentityToken: appleIdentityToken
        )
    }
    
    private func restoreAppleSavedUserOrCreate(
        appleUserId: String,
        email: String?,
        fullName: PersonNameComponents?,
        appleIdentityToken: Data?
    ) {
        if let savedUserData = UserDefaults.standard.data(forKey: "savedUser"),
           let decodedUser = try? JSONDecoder().decode(User.self, from: savedUserData),
           decodedUser.appleUserId == appleUserId || (email != nil && decodedUser.email == email) {
            restoreUser(linkAppleIdentityIfNeeded(for: decodedUser, appleUserId: appleUserId), appleIdentityToken: appleIdentityToken)
            return
        }
        
        let firstName = fullName?.givenName?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Apple"
        let lastName = fullName?.familyName?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "User"
        let resolvedEmail = email?.nonEmpty ?? "appleuser-\(appleUserId.prefix(8))@privaterelay.appleid.com"
        
        let newUser = User(
            id: appleUserId,
            email: resolvedEmail,
            username: nil,
            firstName: firstName,
            lastName: lastName,
            age: 0,
            dateOfBirth: nil,
            userType: .jobSeeker,
            profileImageURL: nil,
            profileImageData: nil,
            skills: [],
            description: nil,
            location: nil,
            createdAt: Date(),
            parentalConsentGiven: nil,
            hasCompletedOnboarding: false,
            acceptedTermsDate: nil,
            acceptedPrivacyDate: nil,
            lastUsernameChange: nil,
            lastNameChange: nil,
            stripeCustomerId: nil,
            stripeConnectAccountId: nil,
            stripeConnectActive: nil,
            stripeConnectDetailsSubmitted: nil,
            bankAccountConnected: nil,
            stripeConnectedAccountId: nil,
            appleUserId: appleUserId,
            legalFirstNameOnId: nil,
            legalLastNameOnId: nil,
            identityDocumentURL: nil,
            identityVerificationSubmittedAt: nil,
            verifiedHomeAddress: nil,
            verifiedHomeLatitude: nil,
            verifiedHomeLongitude: nil,
            stripeIdentityVerified: nil,
            stripeIdentityVerifiedAt: nil,
            stripeIdentityLastSessionId: nil,
            qualificationAttachments: nil
        )
        
        currentUser = newUser
        saveUser()
        UserDatabase.shared.saveUser(newUser)
        
        print("🍎 AuthenticationManager: Created new Apple user = \(newUser.fullName)")
        
        Task {
            await FirebaseAuthSessionSync.signInWithMintedTokenIfNeeded(
                userId: appleUserId,
                googleIDToken: nil,
                appleIdentityToken: appleIdentityToken
            )
        }
    }
    
    private func linkAppleIdentityIfNeeded(for user: User, appleUserId: String) -> User {
        guard user.appleUserId != appleUserId else { return user }
        
        return User(
            id: user.id,
            email: user.email,
            username: user.username,
            firstName: user.firstName,
            lastName: user.lastName,
            age: user.age,
            dateOfBirth: user.dateOfBirth,
            userType: user.userType,
            profileImageURL: user.profileImageURL,
            profileImageData: user.profileImageData,
            skills: user.skills,
            description: user.description,
            location: user.location,
            createdAt: user.createdAt,
            parentalConsentGiven: user.parentalConsentGiven,
            hasCompletedOnboarding: user.hasCompletedOnboarding,
            acceptedTermsDate: user.acceptedTermsDate,
            acceptedPrivacyDate: user.acceptedPrivacyDate,
            lastUsernameChange: user.lastUsernameChange,
            lastNameChange: user.lastNameChange,
            stripeCustomerId: user.stripeCustomerId,
            stripeConnectAccountId: user.stripeConnectAccountId,
            stripeConnectActive: user.stripeConnectActive,
            stripeConnectDetailsSubmitted: user.stripeConnectDetailsSubmitted,
            bankAccountConnected: user.bankAccountConnected,
            stripeConnectedAccountId: user.stripeConnectedAccountId,
            appleUserId: appleUserId,
            legalFirstNameOnId: user.legalFirstNameOnId,
            legalLastNameOnId: user.legalLastNameOnId,
            identityDocumentURL: user.identityDocumentURL,
            identityVerificationSubmittedAt: user.identityVerificationSubmittedAt,
            verifiedHomeAddress: user.verifiedHomeAddress,
            verifiedHomeLatitude: user.verifiedHomeLatitude,
            verifiedHomeLongitude: user.verifiedHomeLongitude,
            stripeIdentityVerified: user.stripeIdentityVerified,
            stripeIdentityVerifiedAt: user.stripeIdentityVerifiedAt,
            stripeIdentityLastSessionId: user.stripeIdentityLastSessionId,
            qualificationAttachments: user.qualificationAttachments,
            profileBannerImageData: user.profileBannerImageData,
            pronouns: user.pronouns,
            bioAttachmentData: user.bioAttachmentData
        )
    }

    func signOut() {
        // Wipe in-memory singleton state BEFORE flipping auth flags. Without
        // this, the next account that signs in inherits the previous user's
        // jobs / applications / notifications / chats / live locations until
        // the app is killed — singletons survive sign-out otherwise.
        clearAllManagerCaches()
        GIDSignIn.sharedInstance.signOut()
        try? Auth.auth().signOut()
        isAuthenticated = false
        currentUser = nil
        isRestoringSession = false
        clearSavedUser() // Clear saved credentials from UserDefaults
        // NOTE: User data is still preserved in UserDatabase for re-login
    }

    /// Permanently delete the current user. Wipes their Firestore docs,
    /// owned content, conversations, storage, and Firebase Auth account, then
    /// clears every local cache and signs them out.
    /// Backed by the `deleteUserAccount` Cloud Function — see
    /// `firebase-functions/index.js`.
    func deleteAccount(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let firebaseUser = Auth.auth().currentUser else {
            completion(.failure(NSError(domain: "AuthenticationManager", code: 401,
                                        userInfo: [NSLocalizedDescriptionKey: "Not signed in."])))
            return
        }

        let uid = firebaseUser.uid

        // Get a fresh ID token so the function can verify identity.
        firebaseUser.getIDTokenForcingRefresh(true) { [weak self] idToken, error in
            guard let self = self else { return }
            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let idToken = idToken else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "AuthenticationManager", code: 401,
                                                userInfo: [NSLocalizedDescriptionKey: "Could not refresh sign-in. Sign out and back in, then try again."])))
                }
                return
            }

            let urlString = "\(StripeConfig.backendURL)/deleteUserAccount"
            guard let url = URL(string: urlString) else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "AuthenticationManager", code: 500,
                                                userInfo: [NSLocalizedDescriptionKey: "Invalid backend URL"])))
                }
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["idToken": idToken])

            URLSession.shared.dataTask(with: request) { data, response, error in
                DispatchQueue.main.async {
                    if let error = error {
                        completion(.failure(error)); return
                    }
                    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                        let serverMsg: String = {
                            if let json = try? JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any],
                               let msg = json["error"] as? String, !msg.isEmpty { return msg }
                            return "Server error \(http.statusCode)"
                        }()
                        completion(.failure(NSError(domain: "AuthenticationManager", code: http.statusCode,
                                                    userInfo: [NSLocalizedDescriptionKey: serverMsg])))
                        return
                    }

                    // Backend succeeded. Now nuke every trace on this device:
                    //   1. UserDatabase (local user cache)
                    //   2. Singleton manager in-memory arrays + listeners
                    //   3. Firebase Auth + Google Sign-In sessions
                    //   4. UserDefaults saved user blob
                    //   5. Firestore offline persistence (so the next sign-in
                    //      doesn't show ghost data from the on-disk cache)
                    UserDatabase.shared.deleteUser(byId: uid)
                    UserDatabase.shared.clearAll()
                    self.clearAllManagerCaches()
                    GIDSignIn.sharedInstance.signOut()
                    try? Auth.auth().signOut()
                    self.isAuthenticated = false
                    self.currentUser = nil
                    self.clearSavedUser()
                    self.wipeFirestorePersistence()
                    completion(.success(()))
                }
            }.resume()
        }
    }
    
    /// Empties the in-memory state of every singleton manager and stops their
    /// snapshot listeners. Used right after account deletion so the user
    /// doesn't see stale jobs/chats lingering from listener caches before
    /// fresh snapshots arrive.
    private func clearAllManagerCaches() {
        OpportunityManager.shared.clearLocalState()
        ApplicationManager.shared.clearLocalState()
        MessageManager.shared.clearLocalState()
        NotificationManager.shared.clearLocalState()
        RatingManager.shared.clearLocalState()
        SafetyManager.shared.clearLocalState()
        PaymentManager.shared.clearLocalState()
        EvidenceRecordingService.shared.clearLocalState()
        CommunityPostManager.shared.clearLocalState()
    }

    /// Best-effort wipe of Firestore's on-disk cache. Has to happen after
    /// signing out (Firestore can't clear persistence while a session is
    /// active). Errors are non-fatal — the cache will get overwritten by
    /// new snapshots either way.
    private func wipeFirestorePersistence() {
        let db = Firestore.firestore()
        // terminate first so any in-flight listeners release the cache lock.
        db.terminate { _ in
            db.clearPersistence { error in
                if let error {
                    print("⚠️ Firestore clearPersistence failed: \(error.localizedDescription)")
                } else {
                    print("✅ Firestore on-disk cache cleared")
                }
            }
        }
    }

    /// Save a freshly-picked home address onto the signed-in user. Used by
    /// the community feed's address gate for seekers (who don't go through
    /// home verification during onboarding the way hirers do). Pure copy-
    /// init since `User` is a struct — mirror the field list in the existing
    /// `withAppleUserId` builder (line ~442).
    func setHomeAddress(_ addressLine: String, coordinate: CLLocationCoordinate2D) {
        guard let user = currentUser else { return }
        let updated = User(
            id: user.id,
            email: user.email,
            username: user.username,
            firstName: user.firstName,
            lastName: user.lastName,
            age: user.age,
            dateOfBirth: user.dateOfBirth,
            userType: user.userType,
            profileImageURL: user.profileImageURL,
            profileImageData: user.profileImageData,
            skills: user.skills,
            description: user.description,
            location: user.location,
            createdAt: user.createdAt,
            parentalConsentGiven: user.parentalConsentGiven,
            hasCompletedOnboarding: user.hasCompletedOnboarding,
            acceptedTermsDate: user.acceptedTermsDate,
            acceptedPrivacyDate: user.acceptedPrivacyDate,
            lastUsernameChange: user.lastUsernameChange,
            lastNameChange: user.lastNameChange,
            stripeCustomerId: user.stripeCustomerId,
            stripeConnectAccountId: user.stripeConnectAccountId,
            stripeConnectActive: user.stripeConnectActive,
            stripeConnectDetailsSubmitted: user.stripeConnectDetailsSubmitted,
            bankAccountConnected: user.bankAccountConnected,
            stripeConnectedAccountId: user.stripeConnectedAccountId,
            appleUserId: user.appleUserId,
            legalFirstNameOnId: user.legalFirstNameOnId,
            legalLastNameOnId: user.legalLastNameOnId,
            identityDocumentURL: user.identityDocumentURL,
            identityVerificationSubmittedAt: user.identityVerificationSubmittedAt,
            verifiedHomeAddress: addressLine,
            verifiedHomeLatitude: coordinate.latitude,
            verifiedHomeLongitude: coordinate.longitude,
            stripeIdentityVerified: user.stripeIdentityVerified,
            stripeIdentityVerifiedAt: user.stripeIdentityVerifiedAt,
            stripeIdentityLastSessionId: user.stripeIdentityLastSessionId,
            qualificationAttachments: user.qualificationAttachments,
            profileBannerImageData: user.profileBannerImageData,
            pronouns: user.pronouns,
            bioAttachmentData: user.bioAttachmentData
        )
        updateUser(updated)
    }

    func updateUser(_ user: User, shouldSyncProfile: Bool = true) {
        currentUser = user
        saveUser() // Save to current session
        UserDatabase.shared.saveUser(user) // Save to database

        guard shouldSyncProfile else { return }

        // Sync profile updates to all jobs, chats, and applications
        Task {
            await syncProfileUpdates(user)
        }
    }

    /// Re-fetch the current user from Firestore and replace the local copy.
    /// Used when an out-of-band write (e.g., a Cloud Function flipping
    /// `isParentalApproved`) needs to be picked up immediately.
    func refreshCurrentUserFromCloud() {
        guard let userId = currentUser?.id else { return }
        UserDatabase.shared.fetchUserFromFirebase(byUserId: userId) { [weak self] freshUser in
            guard let self = self, let freshUser else { return }
            self.currentUser = freshUser
            self.saveUser()
            UserDatabase.shared.saveUser(freshUser)
        }
    }
    
    // MARK: - Profile Sync
    
    private func syncProfileUpdates(_ user: User) async {
        print("🔄 Syncing profile updates for: \(user.fullName)")
        
        // Update all opportunities where this user is the hirer
        await OpportunityManager.shared.updateHirerProfile(
            userId: user.id,
            name: user.fullName,
            imageData: user.profileImageData
        )
        
        // Update all conversations where this user is a participant
        await MessageManager.shared.updateUserProfile(
            userId: user.id,
            name: user.fullName,
            imageData: user.profileImageData
        )
        
        // Update all applications where this user is the applicant
        await ApplicationManager.shared.updateApplicantProfile(
            userId: user.id,
            name: user.fullName,
            imageData: user.profileImageData
        )
        
        print("✅ Profile sync complete for: \(user.fullName)")
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
    
    // MARK: - Username Detection
    
    func checkForMissingUsername() {
        guard let user = currentUser, user.hasCompletedOnboarding else { return }
        
        if !user.hasUsername {
            print("⚠️ User missing username - should set one up")
            // User can set username in Edit Profile view
        }
    }
    
    // End of class
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
