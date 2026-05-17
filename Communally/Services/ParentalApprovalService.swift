//
//  ParentalApprovalService.swift
//  Communally
//
//  Sends parental-approval emails via the existing Cloud Function and observes
//  the seeker's user doc for `isParentalApproved` to flip when the parent clicks
//  the approval link.
//

import Foundation
import FirebaseFirestore
import FirebaseCore

class ParentalApprovalService: ObservableObject {
    static let shared = ParentalApprovalService()

    @Published var isSending = false
    @Published var isApproved = false
    @Published var lastError: String?

    private var listener: ListenerRegistration?
    private var observedUserId: String?

    private init() {}

    private var db: Firestore? {
        guard FirebaseApp.app() != nil else { return nil }
        return Firestore.firestore()
    }

    private var sendEndpoint: String {
        "\(StripeConfig.backendURL)/sendParentalApproval"
    }

    /// Send the parental approval email. Writes `parentEmail`, `parentName`,
    /// and `parentApprovalToken` to the seeker's user doc *before* invoking the
    /// Cloud Function so the parent's approve link can validate the token.
    func requestApproval(
        userId: String,
        childName: String,
        parentEmail: String,
        parentName: String?,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let db = db else {
            DispatchQueue.main.async {
                completion(.failure(NSError(domain: "ParentalApprovalService", code: 1,
                                            userInfo: [NSLocalizedDescriptionKey: "Firebase not configured"])))
            }
            return
        }

        let cleanedEmail = parentEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard cleanedEmail.contains("@"), cleanedEmail.contains(".") else {
            DispatchQueue.main.async {
                completion(.failure(NSError(domain: "ParentalApprovalService", code: 2,
                                            userInfo: [NSLocalizedDescriptionKey: "Enter a valid parent email."])))
            }
            return
        }

        let token = UUID().uuidString

        DispatchQueue.main.async { self.isSending = true; self.lastError = nil }

        // Note: never clear `isParentalApproved` here — see prepareShareableLink for context.
        var userUpdate: [String: Any] = [
            "parentEmail": cleanedEmail,
            "parentApprovalToken": token
        ]
        if let parentName, !parentName.trimmingCharacters(in: .whitespaces).isEmpty {
            userUpdate["parentName"] = parentName.trimmingCharacters(in: .whitespaces)
        }

        db.collection("users").document(userId).setData(userUpdate, merge: true) { [weak self] error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.isSending = false
                    self?.lastError = error.localizedDescription
                    completion(.failure(error))
                }
                return
            }
            self?.invokeSendEndpoint(
                parentEmail: cleanedEmail,
                childName: childName,
                userId: userId,
                token: token,
                completion: completion
            )
        }
    }

    private func invokeSendEndpoint(
        parentEmail: String,
        childName: String,
        userId: String,
        token: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let url = URL(string: sendEndpoint) else {
            DispatchQueue.main.async {
                self.isSending = false
                completion(.failure(NSError(domain: "ParentalApprovalService", code: 3,
                                            userInfo: [NSLocalizedDescriptionKey: "Invalid backend URL"])))
            }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "parentEmail": parentEmail,
            "childName": childName,
            "userId": userId,
            "token": token
        ]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            DispatchQueue.main.async {
                self.isSending = false
                completion(.failure(error))
            }
            return
        }

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isSending = false
                if let error = error {
                    self?.lastError = error.localizedDescription
                    completion(.failure(error))
                    return
                }
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    let bodyText = String(data: data ?? Data(), encoding: .utf8) ?? "Unknown server error"
                    let serverMessage: String
                    if let json = try? JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any],
                       let errorText = json["error"] as? String, !errorText.isEmpty {
                        serverMessage = errorText
                    } else {
                        serverMessage = bodyText
                    }
                    self?.lastError = serverMessage
                    completion(.failure(NSError(domain: "ParentalApprovalService", code: http.statusCode,
                                                userInfo: [NSLocalizedDescriptionKey: serverMessage])))
                    return
                }
                completion(.success(()))
            }
        }.resume()
    }

    /// Prepare a shareable approval URL the seeker can send via Messages /
    /// WhatsApp / etc. Writes a fresh token + parent name to the user doc so
    /// the page can verify it. Doesn't send any email.
    func prepareShareableLink(
        userId: String,
        childFirstName: String,
        parentName: String?,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        guard let db = db else {
            DispatchQueue.main.async {
                completion(.failure(NSError(domain: "ParentalApprovalService", code: 1,
                                            userInfo: [NSLocalizedDescriptionKey: "Firebase not configured"])))
            }
            return
        }
        let token = UUID().uuidString
        // Important: do NOT clear `isParentalApproved` here. If the parent
        // already approved on a previous link, generating a fresh link must
        // not wipe that approval — otherwise the seeker can re-trigger this
        // path (e.g. after a stale-cache gate flash) and lock themselves out.
        var update: [String: Any] = [
            "parentApprovalToken": token
        ]
        if let parentName, !parentName.trimmingCharacters(in: .whitespaces).isEmpty {
            update["parentName"] = parentName.trimmingCharacters(in: .whitespaces)
        }

        db.collection("users").document(userId).setData(update, merge: true) { error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }
                var components = URLComponents(string: "https://communally-a4cb3.web.app/approve")
                components?.queryItems = [
                    URLQueryItem(name: "userId", value: userId),
                    URLQueryItem(name: "token", value: token),
                    URLQueryItem(name: "name", value: childFirstName)
                ]
                guard let url = components?.url else {
                    completion(.failure(NSError(domain: "ParentalApprovalService", code: 4,
                                                userInfo: [NSLocalizedDescriptionKey: "Could not build link"])))
                    return
                }
                completion(.success(url))
            }
        }
    }

    /// Watch the seeker's user doc for `isParentalApproved` to flip true.
    /// Updates `isApproved` on the main thread; safe to bind in SwiftUI.
    func startObserving(userId: String) {
        guard let db = db, observedUserId != userId else { return }
        stopObserving()
        observedUserId = userId
        listener = db.collection("users").document(userId).addSnapshotListener { [weak self] snapshot, _ in
            guard let data = snapshot?.data() else { return }
            let approved = (data["isParentalApproved"] as? Bool) ?? false
            DispatchQueue.main.async {
                self?.isApproved = approved
            }
        }
    }

    func stopObserving() {
        listener?.remove()
        listener = nil
        observedUserId = nil
    }

    #if DEBUG
    /// DEV ONLY — flips `isParentalApproved: true` on the user doc directly,
    /// bypassing the email approval. Used to unstick legacy accounts during
    /// development before the Gmail SMTP credentials are configured.
    /// Compiled out of release builds.
    func devForceApprove(userId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let db = db else {
            DispatchQueue.main.async {
                completion(.failure(NSError(domain: "ParentalApprovalService", code: 1,
                                            userInfo: [NSLocalizedDescriptionKey: "Firebase not configured"])))
            }
            return
        }
        db.collection("users").document(userId).setData([
            "isParentalApproved": true,
            "parentApprovalDate": FieldValue.serverTimestamp()
        ], merge: true) { error in
            DispatchQueue.main.async {
                if let error = error { completion(.failure(error)) }
                else { completion(.success(())) }
            }
        }
    }
    #endif
}
