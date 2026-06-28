//
//  OnboardingPrefill.swift
//  Communally
//
//  Smart-prefill helpers so users coming from Apple / Google sign-in skip as
//  much typing as possible. We already receive name + email (+ a photo URL
//  from Google) at sign-in; these turn that into a suggested username and a
//  downloaded profile photo. Everything here is best-effort and degrades
//  gracefully — a failure just leaves the field blank for manual entry.
//

import UIKit

enum OnboardingPrefill {

    /// A clean, available-looking username suggestion derived from the email
    /// local-part (preferred) or the user's name. Lowercased, alphanumerics
    /// only, 3–20 chars. Returns nil if we can't make something sensible.
    static func suggestedUsername(email: String?, firstName: String?, lastName: String?) -> String? {
        func sanitize(_ s: String) -> String {
            s.lowercased().unicodeScalars
                .filter { CharacterSet.alphanumerics.contains($0) }
                .map(String.init)
                .joined()
        }

        // 1) email local-part, e.g. "jordan.lee@gmail.com" → "jordanlee"
        if let email, let local = email.split(separator: "@").first {
            let candidate = sanitize(String(local))
            if candidate.count >= 3 { return String(candidate.prefix(20)) }
        }

        // 2) fall back to first+last name
        let combined = sanitize((firstName ?? "") + (lastName ?? ""))
        if combined.count >= 3 { return String(combined.prefix(20)) }

        return nil
    }

    /// Download a remote profile image (e.g. the Google account photo) into a
    /// UIImage. Best-effort: any failure calls back with nil on the main queue.
    static func downloadProfileImage(from urlString: String?, completion: @escaping (UIImage?) -> Void) {
        guard let urlString, let url = URL(string: urlString) else {
            completion(nil); return
        }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            let image = data.flatMap(UIImage.init(data:))
            DispatchQueue.main.async { completion(image) }
        }.resume()
    }
}
