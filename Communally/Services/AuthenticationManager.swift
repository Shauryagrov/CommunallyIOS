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
import CryptoKit
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore

class AuthenticationManager: ObservableObject {
    static let shared = AuthenticationManager()
    
    @Published var isAuthenticated = false
    /// Setting/clearing currentUser also updates the Crashlytics user
    /// ID so we can correlate a field crash with a Firestore user.
    /// We don't pass email or any PII — only the opaque user id.
    @Published var currentUser: User? {
        didSet {
            if let id = currentUser?.id, !id.isEmpty {
                CrashReporter.shared.setUser(userId: id)
            } else {
                CrashReporter.shared.clearUser()
            }
        }
    }
    @Published var isLoading = false
    @Published var isRestoringSession = true

    private var isConfigured = false

    /// Raw (un-hashed) nonce for the in-flight Apple Sign-In. Set in
    /// `prepareAppleSignInRequest`, read in `signInWithAppleCredential`,
    /// then passed to the backend so it can verify SHA256(rawNonce)
    /// equals the `nonce` claim in Apple's identity token. Without this,
    /// an attacker who intercepts an identity token (debug log, MitM)
    /// could replay it to mint a Firebase session as the victim →
    /// full account takeover.
    private var pendingAppleRawNonce: String?
    
    private init() {
        // Configure Google Sign-In only once
        if !isConfigured {
            configureGoogleSignIn()
            isConfigured = true
        }

        // C8 stale-session purge — runs ONCE per device after the
        // Apple-Sign-In nonce fix shipped. Pre-fix Apple users have a
        // Firebase Auth custom token that was minted from an
        // identity-token whose nonce was never verified. That session
        // can still be replayed with the intercepted token, so we
        // force them to re-sign in with the new nonce-verified flow.
        purgeStalePreNonceAppleSessionIfNeeded()

        restoreSavedUserIfAvailable()

        // Check if user was previously signed in
        checkPreviousSignIn()
    }

    /// One-time eviction for users who signed in via Apple BEFORE the
    /// C8 nonce verification shipped. The saved blob is wiped and the
    /// Firebase Auth session torn down — the user is prompted to
    /// re-sign in on next launch and gets a fresh nonce-verified
    /// session. Google users are untouched (their flow was always
    /// signature-verified).
    ///
    /// Defensive against init order: `Auth.auth().signOut()` is only
    /// called if Firebase is already configured. If we run before
    /// `FirebaseApp.configure()` in AppDelegate, the UserDefaults wipe
    /// alone is enough — restoreSavedUserIfAvailable will then find
    /// nothing and the user will be forced through fresh sign-in.
    private func purgeStalePreNonceAppleSessionIfNeeded() {
        let key = "c8AppleNoncePurgeDoneV1"
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: key) { return }
        defaults.set(true, forKey: key)

        guard let saved = defaults.data(forKey: "savedUser"),
              let decoded = try? JSONDecoder().decode(User.self, from: saved),
              let appleId = decoded.appleUserId, !appleId.isEmpty else {
            return
        }
        print("🧹 C8: evicting pre-nonce Apple session for \(appleId)")
        if FirebaseApp.app() != nil {
            try? Auth.auth().signOut()
        }
        defaults.removeObject(forKey: "savedUserId")
        defaults.removeObject(forKey: "savedUser")
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
        Log.debug("💾 Restored saved user immediately: \(decodedUser.fullName)")
    }
    
    private func saveUser() {
        if let user = currentUser,
           let encodedUser = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(user.id, forKey: "savedUserId")
            UserDefaults.standard.set(encodedUser, forKey: "savedUser")
            Log.debug("💾 Saved user data for: \(user.fullName)")
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
        
        Log.debug("✅ Google Sign-In configured with CLIENT_ID: \(clientId)")
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
                    
                    Log.debug("✅ Profile info - Email: \(email), Name: \(firstName) \(lastName)")
                    Log.debug("🔍 Checking if user exists in database (after Firebase Auth)...")
                    
                    UserDatabase.shared.fetchUserFromFirebase(byGoogleId: googleId) { fetchedUser in
                        DispatchQueue.main.async {
                            if let fetchedUser = fetchedUser {
                                Log.debug("☁️ Found existing cloud user: \(fetchedUser.fullName)")
                                self.restoreUser(fetchedUser, googleUserForAuth: user)
                                self.isLoading = false
                                return
                            }

                            if let existingUser = UserDatabase.shared.getUser(byGoogleId: googleId) {
                                Log.debug("✅ Found existing local user: \(existingUser.fullName)")
                                Log.debug("📱 Restoring account with onboarding status: \(existingUser.hasCompletedOnboarding)")
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
                            Log.debug("🔧 AuthenticationManager: Created new user = \(newUser.fullName)")
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
        // Generate a fresh cryptographic nonce for this sign-in attempt.
        // Apple embeds the SHA256 hash of `request.nonce` into the
        // resulting identity token's `nonce` claim, which the backend
        // verifies before minting a Firebase session. One-time per
        // sign-in → blocks identity-token replay attacks.
        let raw = Self.randomNonceString()
        pendingAppleRawNonce = raw
        request.nonce = Self.sha256(raw)
    }

    func handleAppleSignInCompletion(_ result: Result<ASAuthorization, Error>) {
        DispatchQueue.main.async {
            self.isLoading = false
        }

        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                print("❌ Apple Sign-In returned an unexpected credential type")
                pendingAppleRawNonce = nil
                return
            }

            // Consume the pending nonce here so it's never reused.
            let rawNonce = pendingAppleRawNonce
            pendingAppleRawNonce = nil
            if rawNonce == nil {
                print("⚠️ Apple Sign-In completed without a pending nonce — refusing for safety")
                return
            }

            signInWithAppleCredential(credential, rawNonce: rawNonce)

        case .failure(let error):
            print("❌ Apple Sign-In error: \(error.localizedDescription)")
            pendingAppleRawNonce = nil
        }
    }

    // MARK: - Apple Sign-In nonce helpers

    /// 32-char URL-safe random nonce — at least 128 bits of entropy.
    ///
    /// The charset is the standard 64-char URL-safe set: 0-9, A-Z, a-z, `-`,
    /// `.`, `_`. (Earlier revisions dropped `W` accidentally — that didn't
    /// bias the output but did make the alphabet 63 chars, weakening
    /// entropy slightly and looking suspicious in code review.) Bytes
    /// outside `[0, charset.count)` are rejected to avoid modulo bias.
    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            let randoms: [UInt8] = (0..<16).map { _ in
                var random: UInt8 = 0
                let status = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                if status != errSecSuccess {
                    // SecRandomCopyBytes failure is effectively impossible
                    // on iOS, but we don't want to crash the app right
                    // before sign-in if it ever does. Fall back to Swift's
                    // SystemRandomNumberGenerator — slightly weaker entropy
                    // than the secure-enclave-backed path but still
                    // cryptographically reasonable, and the user gets
                    // through Apple Sign-In instead of a force-close.
                    return UInt8.random(in: 0...255)
                }
                return random
            }
            randoms.forEach { byte in
                if remaining == 0 { return }
                if byte < charset.count {
                    result.append(charset[Int(byte)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    /// Lowercase-hex SHA256 of the raw nonce. Matches how the backend
    /// (Node `crypto.createHash('sha256').digest('hex')`) computes the
    /// expected hash — comparison must be byte-for-byte identical.
    private static func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.map { String(format: "%02x", $0) }.joined()
    }
    
    private func restoreUser(
        _ user: User,
        googleUserForAuth: GIDGoogleUser? = nil,
        appleIdentityToken: Data? = nil,
        appleRawNonce: String? = nil
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
                appleIdentityToken: appleIdentityToken,
                appleRawNonce: appleRawNonce
            )
        }
    }

    private func signInWithAppleCredential(
        _ credential: ASAuthorizationAppleIDCredential,
        rawNonce: String?
    ) {
        let appleUserId = credential.user
        let email = credential.email?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullName = credential.fullName
        let appleToken = credential.identityToken

        if let localAppleUser = UserDatabase.shared.getUser(byAppleUserId: appleUserId) {
            restoreUser(linkAppleIdentityIfNeeded(for: localAppleUser, appleUserId: appleUserId), appleIdentityToken: appleToken, appleRawNonce: rawNonce)
            return
        }

        UserDatabase.shared.fetchUserFromFirebase(byAppleUserId: appleUserId) { [weak self] appleUser in
            guard let self = self else { return }

            if let appleUser = appleUser {
                self.restoreUser(self.linkAppleIdentityIfNeeded(for: appleUser, appleUserId: appleUserId), appleIdentityToken: appleToken, appleRawNonce: rawNonce)
                return
            }

            self.restoreAppleUserByEmailOrCreate(
                appleUserId: appleUserId,
                email: email,
                fullName: fullName,
                appleIdentityToken: appleToken,
                appleRawNonce: rawNonce
            )
        }
    }

    private func restoreAppleUserByEmailOrCreate(
        appleUserId: String,
        email: String?,
        fullName: PersonNameComponents?,
        appleIdentityToken: Data?,
        appleRawNonce: String?
    ) {
        if let email, let localUser = UserDatabase.shared.getUser(byEmail: email) {
            restoreUser(linkAppleIdentityIfNeeded(for: localUser, appleUserId: appleUserId), appleIdentityToken: appleIdentityToken, appleRawNonce: appleRawNonce)
            return
        }

        if let email {
            UserDatabase.shared.fetchUserFromFirebase(byEmail: email) { [weak self] cloudUser in
                guard let self = self else { return }

                if let cloudUser = cloudUser {
                    self.restoreUser(self.linkAppleIdentityIfNeeded(for: cloudUser, appleUserId: appleUserId), appleIdentityToken: appleIdentityToken, appleRawNonce: appleRawNonce)
                    return
                }

                self.restoreAppleSavedUserOrCreate(
                    appleUserId: appleUserId,
                    email: email,
                    fullName: fullName,
                    appleIdentityToken: appleIdentityToken,
                    appleRawNonce: appleRawNonce
                )
            }
            return
        }

        restoreAppleSavedUserOrCreate(
            appleUserId: appleUserId,
            email: email,
            fullName: fullName,
            appleIdentityToken: appleIdentityToken,
            appleRawNonce: appleRawNonce
        )
    }

    private func restoreAppleSavedUserOrCreate(
        appleUserId: String,
        email: String?,
        fullName: PersonNameComponents?,
        appleIdentityToken: Data?,
        appleRawNonce: String?
    ) {
        if let savedUserData = UserDefaults.standard.data(forKey: "savedUser"),
           let decodedUser = try? JSONDecoder().decode(User.self, from: savedUserData),
           decodedUser.appleUserId == appleUserId || (email != nil && decodedUser.email == email) {
            restoreUser(linkAppleIdentityIfNeeded(for: decodedUser, appleUserId: appleUserId), appleIdentityToken: appleIdentityToken, appleRawNonce: appleRawNonce)
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
        
        Log.debug("🍎 AuthenticationManager: Created new Apple user = \(newUser.fullName)")

        Task {
            await FirebaseAuthSessionSync.signInWithMintedTokenIfNeeded(
                userId: appleUserId,
                googleIDToken: nil,
                appleIdentityToken: appleIdentityToken,
                appleRawNonce: appleRawNonce
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

    /// SEEKER-SAFE: Save only the city + state portion of a picked
    /// address. Used by the community feed's address gate for seekers
    /// (mostly teens) who don't go through home verification during
    /// onboarding. The feed only ever filters by `homeCity`, so we
    /// throw away the street, ZIP, and precise GPS coordinates before
    /// writing — those would be readable by every other signed-in
    /// user under the existing `users/{uid}` rule, and a teen's exact
    /// house has no business being on a public doc.
    ///
    /// Input "123 Main St, Brooklyn, NY 11211, USA" → stored as
    /// "Brooklyn, NY" with nil lat/lon. The existing `homeCity`
    /// parser on `User` picks "Brooklyn" out of that for the feed key.
    func setHomeCityFromPickedAddress(_ fullAddressLine: String) {
        guard let user = currentUser else { return }
        let cityState = Self.extractCityState(from: fullAddressLine) ?? fullAddressLine
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
            verifiedHomeAddress: cityState,
            // Precise coords intentionally NOT saved — feed doesn't
            // need them and they shouldn't sit on the public doc.
            verifiedHomeLatitude: nil,
            verifiedHomeLongitude: nil,
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

    /// Pull "City, ST" out of a full postal-format address. Returns nil
    /// if the address doesn't have a recognizable "STATE ZIP" segment.
    /// Mirrors the parsing strategy used by `User.homeCity` but stops
    /// at the city+state pair instead of returning just the city.
    private static func extractCityState(from address: String) -> String? {
        let parts = address.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        for (i, part) in parts.enumerated() {
            let tokens = part.split(separator: " ").map(String.init)
            let firstIsState = tokens.first.map {
                $0.count == 2 && $0.allSatisfy { $0.isLetter }
            } ?? false
            if firstIsState, i > 0 {
                let city = parts[i - 1]
                let state = tokens[0].uppercased()
                return "\(city), \(state)"
            }
        }
        return nil
    }

    /// HIRER-ONLY: Save a verified home address WITH precise coordinates.
    /// Hirers go through identity verification and need their exact
    /// location for distance-based opportunity matching; seekers should
    /// use `setHomeCityFromPickedAddress` instead.
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
