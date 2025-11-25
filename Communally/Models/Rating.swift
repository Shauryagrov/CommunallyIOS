//
//  Rating.swift
//  Communally
//
//  Rating model for user reviews
//

import Foundation
import FirebaseFirestore

struct Rating: Identifiable, Codable {
    @DocumentID var id: String?
    let opportunityId: String
    let applicationId: String
    let raterId: String           // Person giving the rating (hirer)
    let raterName: String
    let ratedUserId: String       // Person being rated (job seeker)
    let ratedUserName: String
    let score: Double             // 1-5 stars
    let review: String?           // Optional text review
    let createdAt: Date
    let jobTitle: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case opportunityId
        case applicationId
        case raterId
        case raterName
        case ratedUserId
        case ratedUserName
        case score
        case review
        case createdAt
        case jobTitle
    }
    
    var safeId: String {
        return id ?? UUID().uuidString
    }
    
    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }
    
    var scoreDisplay: String {
        return String(format: "%.1f", score)
    }
}

struct UserRatingStats: Codable {
    let userId: String
    var totalRatings: Int
    var averageScore: Double
    var fiveStarCount: Int
    var fourStarCount: Int
    var threeStarCount: Int
    var twoStarCount: Int
    var oneStarCount: Int
    
    var scoreDisplay: String {
        return String(format: "%.1f", averageScore)
    }
    
    var hasRatings: Bool {
        return totalRatings > 0
    }
    
    // Calculate percentages for each star rating
    func percentage(for stars: Int) -> Double {
        guard totalRatings > 0 else { return 0 }
        let count: Int
        switch stars {
        case 5: count = fiveStarCount
        case 4: count = fourStarCount
        case 3: count = threeStarCount
        case 2: count = twoStarCount
        case 1: count = oneStarCount
        default: return 0
        }
        return Double(count) / Double(totalRatings) * 100
    }
}

