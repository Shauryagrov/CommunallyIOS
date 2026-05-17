//
//  CommunityPost.swift
//  Communally
//
//  Photo + caption posts shared with neighbors in the same home city.
//  Modeled the same way as Opportunity / JobApplication: image stored as
//  base64-encoded `Data` directly on the document so we don't need a
//  separate Storage SDK setup for build 6.
//

import Foundation

struct CommunityPost: Identifiable, Codable {
    let id: String
    let authorId: String
    let authorName: String
    let authorImageData: Data?
    /// Nil for text-only posts. Card UI hides the photo block when missing.
    let photoData: Data?
    let caption: String
    /// Lower-cased, whitespace-collapsed city used for the Firestore
    /// `whereField` query. Display the original-case city string from the
    /// author's address for UI.
    let cityKey: String
    let cityDisplay: String
    let createdAt: Date

    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }
}

extension String {
    /// Normalises a city name for Firestore equality queries — lower-cases,
    /// collapses whitespace, strips punctuation that varies between geocoders
    /// (apostrophes, hyphens, periods). Empty string for empty input.
    var communityCityKey: String {
        let lower = self.lowercased()
        let allowed = lower.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || $0 == " "
        }
        let collapsed = String(String.UnicodeScalarView(allowed))
            .split(separator: " ")
            .joined(separator: " ")
        return collapsed
    }
}
