//
//  QualificationDocumentUploader.swift
//  Communally
//
//  Uploads optional résumé / certificate files to Firebase Storage (`qualifications/{userId}/`).
//

import Foundation
import FirebaseAuth
import FirebaseCore
import FirebaseStorage

enum QualificationDocumentUploadError: LocalizedError {
    case firebaseNotConfigured
    case fileTooLarge
    case uploadFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .firebaseNotConfigured:
            return "Cloud storage is not available. Check your connection and try again."
        case .fileTooLarge:
            return "That file is too large. Try a file under 6 MB."
        case .uploadFailed(let message):
            return message
        }
    }
}

enum QualificationDocumentUploader {
    private static let maxBytes = 6 * 1024 * 1024
    
    static func upload(
        data: Data,
        userId: String,
        originalFileName: String,
        contentType: String,
        completion: @escaping (Result<QualificationAttachment, Error>) -> Void
    ) {
        guard FirebaseApp.app() != nil else {
            completion(.failure(QualificationDocumentUploadError.firebaseNotConfigured))
            return
        }
        if Auth.auth().currentUser?.uid != userId {
            completion(.failure(QualificationDocumentUploadError.uploadFailed(
                "Sign in again, then try adding the file."
            )))
            return
        }
        guard data.count <= maxBytes else {
            completion(.failure(QualificationDocumentUploadError.fileTooLarge))
            return
        }
        
        let trimmedName = originalFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmedName.isEmpty ? "document" : trimmedName
        let safeName = base
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
        let short = String(safeName.prefix(96))
        let objectName = "\(UUID().uuidString.prefix(8))_\(short)"
        let ref = Storage.storage().reference().child("qualifications/\(userId)/\(objectName)")
        
        let metadata = StorageMetadata()
        metadata.contentType = contentType
        
        ref.putData(data, metadata: metadata) { _, error in
            if let error = error {
                completion(.failure(QualificationDocumentUploadError.uploadFailed(error.localizedDescription)))
                return
            }
            ref.downloadURL { url, error in
                if let error = error {
                    completion(.failure(QualificationDocumentUploadError.uploadFailed(error.localizedDescription)))
                    return
                }
                guard let url = url else {
                    completion(.failure(QualificationDocumentUploadError.uploadFailed("Missing download URL")))
                    return
                }
                let attachment = QualificationAttachment(
                    fileName: base,
                    downloadURL: url.absoluteString,
                    uploadedAt: Date()
                )
                completion(.success(attachment))
            }
        }
    }
}
