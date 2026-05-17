//
//  FirebaseAuthSessionSync.swift
//  Communally
//
//  Signs into Firebase Auth with a custom token from `mintCustomAuthToken` so Firestore/Storage
//  rules can use request.auth.uid (matches User.id from Google or Apple).
//

import Foundation
import FirebaseAuth
import FirebaseCore
import GoogleSignIn

enum FirebaseAuthSessionSync {

    private static func mintEndpointURL() -> URL? {
        guard let projectId = FirebaseApp.app()?.options.projectID, !projectId.isEmpty else { return nil }
        return URL(string: "https://us-central1-\(projectId).cloudfunctions.net/mintCustomAuthToken")
    }

    /// Outcome when the app needs Firebase Auth before Storage/Firestore rules apply.
    enum EnsureAuthOutcome: Equatable {
        case ready
        /// Mint or sign-in failed; `detail` is safe to show when we know the cause (e.g. IAM).
        case blocked(detail: String?)
    }

    /// Keeps Firebase Auth aligned with the app user so Firestore/Storage rules apply.
    ///
    /// `appleRawNonce` MUST be supplied for Apple Sign-In since C8 — the backend
    /// rejects Apple mints without it. Google ignores the field.
    static func signInWithMintedTokenIfNeeded(
        userId: String,
        googleIDToken: String?,
        appleIdentityToken: Data?,
        appleRawNonce: String? = nil
    ) async {
        guard FirebaseApp.app() != nil else { return }
        if Auth.auth().currentUser?.uid == userId { return }
        _ = await mintAndSignIn(
            googleIDToken: googleIDToken,
            appleIdentityToken: appleIdentityToken,
            appleRawNonce: appleRawNonce
        )
    }

    /// Call **before** `users/{id}` or other Firestore reads: rules require `request.auth != null`.
    /// Returns whether Firebase Auth is signed in with a custom token after mint.
    static func establishSessionAfterGoogleSignIn(googleIDToken: String?) async -> Bool {
        guard FirebaseApp.app() != nil else { return false }
        guard let googleIDToken, !googleIDToken.isEmpty else {
            print("⚠️ FirebaseAuthSessionSync: no Google ID token for mint")
            return false
        }
        let result = await mintAndSignIn(googleIDToken: googleIDToken, appleIdentityToken: nil, appleRawNonce: nil)
        if case .success = result {
            return Auth.auth().currentUser != nil
        }
        return false
    }

    /// Refresh Google tokens, then mint Firebase Auth session (use after `signIn` / `restorePreviousSignIn`).
    static func establishSessionFromGoogleUser(_ googleUser: GIDGoogleUser?) async -> Bool {
        guard let googleUser else { return false }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            googleUser.refreshTokensIfNeeded { _, _ in
                cont.resume()
            }
        }
        return await establishSessionAfterGoogleSignIn(googleIDToken: googleUser.idToken?.tokenString)
    }

    /// Call before Firebase Storage uploads so `request.auth.uid` matches `userId` (required by Storage rules).
    static func ensureFirebaseAuthForStorage(userId: String) async -> EnsureAuthOutcome {
        guard FirebaseApp.app() != nil else {
            return .blocked(detail: nil)
        }
        if Auth.auth().currentUser?.uid == userId { return .ready }

        if let googleUser = GIDSignIn.sharedInstance.currentUser, googleUser.userID == userId {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                googleUser.refreshTokensIfNeeded { _, _ in
                    cont.resume()
                }
            }
            let token = GIDSignIn.sharedInstance.currentUser?.idToken?.tokenString
            let mint = await mintAndSignIn(googleIDToken: token, appleIdentityToken: nil, appleRawNonce: nil)
            switch mint {
            case .success:
                return Auth.auth().currentUser?.uid == userId ? .ready : .blocked(detail: nil)
            case .failure(let reason):
                return .blocked(detail: reason.userFacingMessage)
            }
        }

        // Apple: expect prior mint; if missing, user should sign in again.
        return Auth.auth().currentUser?.uid == userId ? .ready : .blocked(detail: nil)
    }

    private enum MintFailure {
        case missingProject
        case missingProviderToken
        case http(status: Int, body: String)
        case noTokenInResponse
        case signIn(Error)

        var userFacingMessage: String? {
            switch self {
            case .missingProject, .missingProviderToken, .noTokenInResponse, .signIn:
                return nil
            case .http(let status, let body):
                if status == 401, body.range(of: "signBlob", options: .caseInsensitive) != nil {
                    return "This isn’t your internet. In Google Cloud → IAM, grant the Cloud Functions runtime service account “Service Account Token Creator” on the firebase-adminsdk service account (Firebase: custom token troubleshooting)."
                }
                if status == 401 {
                    return "Secure sign-in was rejected (HTTP 401). Check mintCustomAuthToken logs and Cloud IAM."
                }
                return nil
            }
        }
    }

    private enum MintResult {
        case success
        case failure(MintFailure)
    }

    private static func mintAndSignIn(
        googleIDToken: String?,
        appleIdentityToken: Data?,
        appleRawNonce: String?
    ) async -> MintResult {
        guard let url = mintEndpointURL() else {
            print("⚠️ FirebaseAuthSessionSync: missing Firebase project id")
            return .failure(.missingProject)
        }

        let payload: [String: Any]
        if let googleIDToken, !googleIDToken.isEmpty {
            payload = ["provider": "google", "idToken": googleIDToken]
        } else if let appleIdentityToken,
                  let tokenString = String(data: appleIdentityToken, encoding: .utf8),
                  !tokenString.isEmpty {
            // C8: Backend requires `rawNonce` so it can verify SHA256(rawNonce)
            // matches the `nonce` claim in Apple's identity token — without
            // this, the mint will be rejected. If the caller forgot to pass
            // one, bail out loudly rather than silently sending a request that
            // the backend will 401.
            guard let appleRawNonce, !appleRawNonce.isEmpty else {
                print("⚠️ FirebaseAuthSessionSync: Apple mint missing rawNonce — refusing (sign in again)")
                return .failure(.missingProviderToken)
            }
            payload = [
                "provider": "apple",
                "identityToken": tokenString,
                "rawNonce": appleRawNonce
            ]
        } else {
            print("⚠️ FirebaseAuthSessionSync: no ID token available for mint (sign in again if Firestore fails)")
            return .failure(.missingProviderToken)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .failure(.http(status: -1, body: "")) }
            let text = String(data: data, encoding: .utf8) ?? ""
            guard http.statusCode == 200 else {
                print("⚠️ FirebaseAuthSessionSync mint HTTP \(http.statusCode): \(text)")
                return .failure(.http(status: http.statusCode, body: text))
            }
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let custom = obj?["token"] as? String else { return .failure(.noTokenInResponse) }
            do {
                try await Auth.auth().signIn(withCustomToken: custom)
                print("🔐 Firebase Auth custom token OK (uid=\(Auth.auth().currentUser?.uid ?? "?"))")
                return .success
            } catch {
                print("⚠️ FirebaseAuthSessionSync: \(error.localizedDescription)")
                return .failure(.signIn(error))
            }
        } catch {
            print("⚠️ FirebaseAuthSessionSync: \(error.localizedDescription)")
            return .failure(.signIn(error))
        }
    }
}
