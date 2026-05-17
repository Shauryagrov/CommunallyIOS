//
//  StripeIdentityVerificationService.swift
//  Communally
//

import Foundation
import FirebaseAuth

enum StripeIdentityVerificationServiceError: LocalizedError {
    case notSignedIn
    case invalidURL
    case noData
    case serverError(String)
    
    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Sign in again to verify your ID."
        case .invalidURL:
            return "Verification service URL is not configured."
        case .noData:
            return "No response from verification service."
        case .serverError(let message):
            return message
        }
    }
}

enum StripeIdentityVerificationService {
    /// Requests a `VerificationSession` from Cloud Functions; returns the **client secret** for `IdentityVerificationSheet`.
    static func fetchVerificationClientSecret(completion: @escaping (Result<String, Error>) -> Void) {
        guard Auth.auth().currentUser != nil else {
            completion(.failure(StripeIdentityVerificationServiceError.notSignedIn))
            return
        }
        
        guard let url = URL(string: "\(StripeConfig.backendURL)/createIdentityVerificationSession") else {
            completion(.failure(StripeIdentityVerificationServiceError.invalidURL))
            return
        }
        
        Auth.auth().currentUser?.getIDTokenForcingRefresh(true) { token, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let token = token else {
                completion(.failure(StripeIdentityVerificationServiceError.notSignedIn))
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["idToken": token])
            
            URLSession.shared.dataTask(with: request) { data, response, err in
                if let err = err {
                    DispatchQueue.main.async { completion(.failure(err)) }
                    return
                }
                guard let data = data, !data.isEmpty else {
                    DispatchQueue.main.async { completion(.failure(StripeIdentityVerificationServiceError.noData)) }
                    return
                }
                
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                if let secret = json?["clientSecret"] as? String, !secret.isEmpty {
                    DispatchQueue.main.async { completion(.success(secret)) }
                    return
                }
                
                let message: String
                if let errStr = json?["error"] as? String {
                    message = errStr
                } else if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                    message = "Verification service error (\(http.statusCode))."
                } else {
                    message = "Could not start ID verification."
                }
                DispatchQueue.main.async {
                    completion(.failure(StripeIdentityVerificationServiceError.serverError(message)))
                }
            }.resume()
        }
    }
}
