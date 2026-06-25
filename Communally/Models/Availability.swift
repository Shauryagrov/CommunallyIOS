//
//  Availability.swift
//  Communally
//
//  Seeker-posted "I'm available" listing — the marketplace mirror of
//  Opportunity. Hirers within 5 miles can see it on the map / in browse
//  and reach out. Pay rate is hourly only (matches the platform rule).
//

import Foundation
import SwiftUI
import FirebaseFirestore

enum AvailabilityStatus: String, Codable {
    case open = "open"
    case taken = "taken"
    case cancelled = "cancelled"
}

struct Availability: Identifiable, Codable {
    @DocumentID var id: String?
    let seekerId: String
    let seekerName: String
    let seekerImageData: Data?
    let location: Location
    let locationName: String
    /// One or more `OpportunityCategory` raw values the seeker is offering.
    /// Multi-select so a single post can cover e.g. ["Gardening", "Moving Help"].
    let categories: [String]
    /// Hourly rate the seeker is asking. Validated against the highest of
    /// the selected categories' minimums at post time.
    let hourlyRate: Int
    let scheduledDate: Date
    let scheduledTime: String
    let scheduledEndTime: String
    /// Optional pitch the seeker can attach — "I've done 20+ moves" etc.
    let note: String?
    let createdAt: Date
    var isActive: Bool
    var status: AvailabilityStatus

    enum CodingKeys: String, CodingKey {
        case id
        case seekerId
        case seekerName
        case seekerImageData
        case location
        case locationName
        case categories
        case hourlyRate
        case scheduledDate
        case scheduledTime
        case scheduledEndTime
        case note
        case createdAt
        case isActive
        case status
    }

    var safeId: String { id ?? UUID().uuidString }

    var displayPay: String { "$\(hourlyRate)/hr" }

    /// Pretty list of category emojis + names for the card row, e.g.
    /// "🌿 Gardening · 📦 Moving Help".
    var displayCategories: String {
        categories.compactMap { raw in
            if let cat = OpportunityCategory(rawValue: raw) {
                return "\(cat.emoji) \(cat.rawValue)"
            }
            return raw
        }.joined(separator: " · ")
    }

    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }

    /// Same one-day expiry rule as Opportunity so the feed stays fresh.
    var expiresIn: TimeInterval {
        scheduledDate.addingTimeInterval(86400).timeIntervalSinceNow
    }

    var isExpired: Bool { status == .open && expiresIn <= 0 }
}
