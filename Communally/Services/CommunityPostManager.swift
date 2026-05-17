//
//  CommunityPostManager.swift
//  Communally
//
//  Snapshot listener + create flow for the city-scoped community feed.
//  Mirrors the pattern in OpportunityManager / ApplicationManager so the
//  rest of the app's listener-cleanup story stays consistent.
//

import Foundation
import SwiftUI
import FirebaseCore
import FirebaseFirestore

final class CommunityPostManager: ObservableObject {
    static let shared = CommunityPostManager()

    @Published var posts: [CommunityPost] = []
    @Published var isPosting: Bool = false

    private var db: Firestore? { FirebaseApp.app() != nil ? Firestore.firestore() : nil }
    private var listener: ListenerRegistration?
    /// Tracks the current city subscription so we can avoid redundant
    /// re-attaches when the user lands on the feed multiple times.
    private(set) var currentCityKey: String?

    private init() {}

    // MARK: - Listener
    /// Attach a snapshot listener for posts in `cityDisplay`'s normalised
    /// city. Idempotent: re-calling with the same city is a no-op.
    func startListening(forCity cityDisplay: String) {
        let key = cityDisplay.communityCityKey
        guard !key.isEmpty else {
            stopListening()
            return
        }
        if currentCityKey == key, listener != nil { return }

        stopListening()
        currentCityKey = key

        guard let db = db else {
            print("⚠️ CommunityPostManager: Firebase not configured")
            return
        }

        listener = db.collection("communityPosts")
            .whereField("cityKey", isEqualTo: key)
            .order(by: "createdAt", descending: true)
            .limit(to: 200)
            .addSnapshotListener { [weak self] snap, error in
                guard let self = self else { return }
                if let error = error {
                    print("❌ communityPosts listener error: \(error.localizedDescription)")
                    return
                }
                let docs = snap?.documents ?? []
                let parsed: [CommunityPost] = docs.compactMap { doc in
                    let data = doc.data()
                    guard let authorId = data["authorId"] as? String,
                          let authorName = data["authorName"] as? String,
                          let caption = data["caption"] as? String,
                          let cityKey = data["cityKey"] as? String,
                          let cityDisplay = data["cityDisplay"] as? String,
                          let createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
                    else { return nil }
                    let photoBase64 = data["photoBase64"] as? String
                    let photoData = photoBase64.flatMap { Data(base64Encoded: $0) }
                    let avatarBase64 = data["authorImageBase64"] as? String
                    let avatarData = avatarBase64.flatMap { Data(base64Encoded: $0) }
                    return CommunityPost(
                        id: doc.documentID,
                        authorId: authorId,
                        authorName: authorName,
                        authorImageData: avatarData,
                        photoData: photoData,
                        caption: caption,
                        cityKey: cityKey,
                        cityDisplay: cityDisplay,
                        createdAt: createdAt
                    )
                }
                DispatchQueue.main.async { self.posts = parsed }
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
        currentCityKey = nil
        posts = []
    }

    // MARK: - Create
    /// Create a post. Caption is moderated against `ContentModerationService`
    /// before the network round-trip; image moderation is intentionally not
    /// wired up for build 6 — mention image moderation explicitly to the
    /// user before going public.
    enum CreateError: LocalizedError {
        case notSignedIn
        case missingHomeCity
        case captionRejected(String)
        case imageEncodingFailed
        case server(String)

        var errorDescription: String? {
            switch self {
            case .notSignedIn:           return "You need to sign in first."
            case .missingHomeCity:       return "Verify your home address before posting to the feed."
            case .captionRejected(let s): return s
            case .imageEncodingFailed:   return "We couldn't read that photo — try another one."
            case .server(let s):         return s
            }
        }
    }

    func createPost(
        author: User,
        photoData: Data?,
        caption: String,
        completion: @escaping (Result<Void, CreateError>) -> Void
    ) {
        let trimmedCaption = caption.trimmingCharacters(in: .whitespacesAndNewlines)

        // Need EITHER a photo or a caption — empty posts blocked.
        if (photoData?.isEmpty ?? true) && trimmedCaption.isEmpty {
            completion(.failure(.captionRejected("Add a photo or write something to post.")))
            return
        }

        if !trimmedCaption.isEmpty,
           let moderationError = ContentModerationService.shared.validateProfileText(trimmedCaption) {
            completion(.failure(.captionRejected(moderationError.localizedDescription)))
            return
        }

        guard let cityDisplay = author.homeCity, !cityDisplay.isEmpty else {
            completion(.failure(.missingHomeCity))
            return
        }
        let cityKey = cityDisplay.communityCityKey

        guard let db = db else {
            completion(.failure(.server("Firebase isn't configured.")))
            return
        }

        isPosting = true
        let id = UUID().uuidString
        var payload: [String: Any] = [
            "authorId": author.id,
            "authorName": author.fullName,
            "caption": trimmedCaption,
            "cityKey": cityKey,
            "cityDisplay": cityDisplay,
            "createdAt": Timestamp(date: Date())
        ]
        if let photoData, !photoData.isEmpty {
            payload["photoBase64"] = photoData.base64EncodedString()
        }
        if let avatar = author.profileImageData {
            payload["authorImageBase64"] = avatar.base64EncodedString()
        }

        db.collection("communityPosts").document(id).setData(payload) { [weak self] error in
            DispatchQueue.main.async {
                self?.isPosting = false
                if let error = error {
                    completion(.failure(.server(error.localizedDescription)))
                } else {
                    completion(.success(()))
                }
            }
        }
    }

    /// Author-only delete. Used by the post action sheet on owned cards.
    func deletePost(_ post: CommunityPost, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let db = db else { return }
        db.collection("communityPosts").document(post.id).delete { error in
            DispatchQueue.main.async {
                if let error = error { completion(.failure(error)) }
                else { completion(.success(())) }
            }
        }
    }

    /// Wipe local state on sign-out (mirrors other managers' helpers used
    /// during account deletion).
    func clearLocalState() {
        stopListening()
    }
}
