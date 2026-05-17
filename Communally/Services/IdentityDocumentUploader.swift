//
//  IdentityDocumentUploader.swift
//  Communally
//
//  Uploads hirer ID images to Firebase Storage (path: identity_docs/{userId}/).
//  Configure Storage rules so only the authenticated user can write their own folder.
//

import Foundation
import UIKit
import FirebaseAuth
import FirebaseCore
import FirebaseStorage

enum IdentityDocumentUploadError: LocalizedError {
    case firebaseNotConfigured
    case imageEncodingFailed
    case uploadFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .firebaseNotConfigured:
            return "Cloud storage is not available. Check your connection and try again."
        case .imageEncodingFailed:
            return "Could not process the photo. Try another image."
        case .uploadFailed(let message):
            return message
        }
    }
}

enum IdentityDocumentUploader {
    private static let maxJPEGBytes = 4 * 1024 * 1024
    
    static func uploadIdentityImage(
        _ image: UIImage,
        userId: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard FirebaseApp.app() != nil else {
            completion(.failure(IdentityDocumentUploadError.firebaseNotConfigured))
            return
        }
        if Auth.auth().currentUser?.uid != userId {
            completion(.failure(IdentityDocumentUploadError.uploadFailed(
                "Your account isn’t connected for secure upload yet. Tap Complete again in a few seconds, or sign out and sign back in."
            )))
            return
        }
        
        guard var data = image.jpegData(compressionQuality: 0.82) else {
            completion(.failure(IdentityDocumentUploadError.imageEncodingFailed))
            return
        }
        
        var quality: CGFloat = 0.72
        while data.count > maxJPEGBytes && quality > 0.35 {
            guard let smaller = image.jpegData(compressionQuality: quality) else { break }
            data = smaller
            quality -= 0.08
        }
        
        let name = "id_\(UUID().uuidString.prefix(10)).jpg"
        let ref = Storage.storage().reference().child("identity_docs/\(userId)/\(name)")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        
        ref.putData(data, metadata: metadata) { _, error in
            if let error = error {
                completion(.failure(IdentityDocumentUploadError.uploadFailed(error.localizedDescription)))
                return
            }
            ref.downloadURL { url, error in
                if let error = error {
                    let msg = error.localizedDescription
                    let friendly = msg.contains("does not exist") || msg.contains("Object")
                        ? "Upload didn’t finish on the server. Check Wi‑Fi, confirm you’re still signed in with Google, then try Complete again."
                        : msg
                    completion(.failure(IdentityDocumentUploadError.uploadFailed(friendly)))
                    return
                }
                guard let url = url else {
                    completion(.failure(IdentityDocumentUploadError.uploadFailed("Missing download URL")))
                    return
                }
                completion(.success(url.absoluteString))
            }
        }
    }
}
