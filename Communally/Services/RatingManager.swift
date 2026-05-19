//
//  RatingManager.swift
//  Communally
//
//  Manages user ratings and reviews
//

import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore

class RatingManager: ObservableObject {
    static let shared = RatingManager()

    @Published var ratings: [Rating] = []
    @Published var userStats: [String: UserRatingStats] = [:] // userId -> stats

    private var db: Firestore? {
        guard FirebaseApp.app() != nil else {
            return nil
        }
        return Firestore.firestore()
    }
    private var listener: ListenerRegistration?
    private var authHandle: AuthStateDidChangeListenerHandle?

    private init() {}

    deinit {
        listener?.remove()
        if let handle = authHandle { Auth.auth().removeStateDidChangeListener(handle) }
    }

    /// Wipes in-memory state + listener. Used after account deletion.
    func clearLocalState() {
        listener?.remove()
        listener = nil
        DispatchQueue.main.async {
            self.ratings = []
            self.userStats = [:]
        }
    }

    // MARK: - Firestore Sync

    /// Wires up an auth state observer that attaches/detaches the ratings
    /// snapshot listener as the user signs in/out. Idempotent. Same pattern
    /// as `OpportunityManager.initialize()` — without the auth gate the
    /// listener would attach pre-auth, get permission-denied, and never
    /// recover until app relaunch.
    func startListening() {
        guard authHandle == nil else { return }
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self = self else { return }
            if user != nil {
                self.attachListener()
            } else {
                self.listener?.remove()
                self.listener = nil
                DispatchQueue.main.async {
                    self.ratings = []
                    self.userStats = [:]
                }
            }
        }
    }

    private func attachListener() {
        guard let db = db else {
            print("⚠️ RatingManager: Firebase not configured")
            return
        }

        listener?.remove()

        listener = db.collection("ratings")
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                
                if let error = error {
                    print("❌ Error listening to ratings: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    print("ℹ️ No ratings found")
                    return
                }
                
                self.ratings = documents.compactMap { doc -> Rating? in
                    try? doc.data(as: Rating.self)
                }
                
                print("✅ Synced \(self.ratings.count) ratings from Firebase")
                
                // Update user stats
                self.calculateUserStats()
            }
    }
    
    // MARK: - Rating Operations
    
    /// Submit a rating for a job seeker
    func submitRating(
        opportunityId: String,
        applicationId: String,
        raterId: String,
        raterName: String,
        ratedUserId: String,
        ratedUserName: String,
        score: Double,
        review: String?,
        jobTitle: String,
        completion: @escaping (Bool) -> Void
    ) {
        // Validate score range. Without this guard, a UI bug or a forged
        // client write could submit -1 / 6.5 / 999 stars, poisoning the
        // userStats trigger's average + bucket counts. The server-side
        // trigger truncates to 1-5 buckets but doesn't reject out-of-range
        // values, so client-side rejection is the gate.
        guard score >= 1.0, score <= 5.0 else {
            Log.debug("⚠️ Invalid rating score: \(score) — must be 1.0-5.0")
            completion(false)
            return
        }

        // Check if already rated
        if hasRated(opportunityId: opportunityId, raterId: raterId) {
            Log.debug("⚠️ User already rated this opportunity")
            completion(false)
            return
        }
        
        let ratingId = UUID().uuidString
        let rating = Rating(
            id: ratingId,
            opportunityId: opportunityId,
            applicationId: applicationId,
            raterId: raterId,
            raterName: raterName,
            ratedUserId: ratedUserId,
            ratedUserName: ratedUserName,
            score: score,
            review: review,
            createdAt: Date(),
            jobTitle: jobTitle
        )
        
        guard let db = db else {
            print("⚠️ RatingManager: Firebase not configured")
            completion(false)
            return
        }
        
        do {
            try db.collection("ratings").document(ratingId).setData(from: rating)
            print("✅ Rating submitted: \(score) stars for \(ratedUserName)")

            // userStats is now updated server-side by the
            // `recomputeUserStatsOnRatingWrite` Cloud Function trigger on
            // /ratings. Direct client writes to /userStats are blocked by
            // firestore.rules (was a tampering vector — any signed-in
            // user could overwrite anyone else's stats).

            // Send notification to rated user
            NotificationManager.shared.sendRatingReceivedNotification(
                rating: rating,
                recipientId: ratedUserId
            )

            completion(true)
        } catch {
            print("❌ Error submitting rating: \(error.localizedDescription)")
            completion(false)
        }
    }
    
    /// Check if user has already rated an opportunity
    func hasRated(opportunityId: String, raterId: String) -> Bool {
        return ratings.contains { rating in
            rating.opportunityId == opportunityId && rating.raterId == raterId
        }
    }
    
    /// Get ratings for a specific user
    func getRatings(forUser userId: String) -> [Rating] {
        return ratings.filter { $0.ratedUserId == userId }
    }
    
    /// Get rating for a specific opportunity
    func getRating(forOpportunity opportunityId: String) -> Rating? {
        return ratings.first { $0.opportunityId == opportunityId }
    }
    
    /// Get rating stats for a user (new users start with 4.0 stars)
    func getStats(forUser userId: String) -> UserRatingStats {
        if let stats = userStats[userId] {
            return stats
        } else {
            // New users start with 4.0 stars to give them a fair chance
            return UserRatingStats(
                userId: userId,
                totalRatings: 0,
                averageScore: 4.0, // Default 4 stars for new users
                fiveStarCount: 0,
                fourStarCount: 0,
                threeStarCount: 0,
                twoStarCount: 0,
                oneStarCount: 0
            )
        }
    }
    
    // MARK: - Stats Calculation
    
    private func calculateUserStats() {
        var statsDict: [String: UserRatingStats] = [:]
        
        // Group ratings by user
        let groupedRatings = Dictionary(grouping: ratings) { $0.ratedUserId }
        
        for (userId, userRatings) in groupedRatings {
            let totalRatings = userRatings.count
            let totalScore = userRatings.reduce(0.0) { $0 + $1.score }
            let averageScore = totalScore / Double(totalRatings)
            
            var fiveStarCount = 0
            var fourStarCount = 0
            var threeStarCount = 0
            var twoStarCount = 0
            var oneStarCount = 0
            
            for rating in userRatings {
                switch Int(rating.score) {
                case 5: fiveStarCount += 1
                case 4: fourStarCount += 1
                case 3: threeStarCount += 1
                case 2: twoStarCount += 1
                case 1: oneStarCount += 1
                default: break
                }
            }
            
            statsDict[userId] = UserRatingStats(
                userId: userId,
                totalRatings: totalRatings,
                averageScore: averageScore,
                fiveStarCount: fiveStarCount,
                fourStarCount: fourStarCount,
                threeStarCount: threeStarCount,
                twoStarCount: twoStarCount,
                oneStarCount: oneStarCount
            )
        }
        
        self.userStats = statsDict
    }
    
    // MARK: - Smart Ranking
    
    /// Rank applicants by rating and other factors
    func rankApplicants(
        _ applications: [JobApplication],
        opportunity: Opportunity
    ) -> [JobApplication] {
        return applications.sorted { app1, app2 in
            let stats1 = getStats(forUser: app1.applicantId)
            let stats2 = getStats(forUser: app2.applicantId)
            
            // Calculate ranking score (0-100)
            let score1 = calculateRankingScore(
                stats: stats1,
                application: app1,
                opportunity: opportunity
            )
            let score2 = calculateRankingScore(
                stats: stats2,
                application: app2,
                opportunity: opportunity
            )
            
            return score1 > score2
        }
    }
    
    private func calculateRankingScore(
        stats: UserRatingStats,
        application: JobApplication,
        opportunity: Opportunity
    ) -> Double {
        var score: Double = 0
        
        // Rating component (0-50 points)
        // All users (including new ones with 4.0 default) get points based on average
        score += (stats.averageScore / 5.0) * 50.0
        
        // Experience component (0-20 points)
        // More completed jobs = more points
        let experienceScore = min(Double(stats.totalRatings) * 2.0, 20.0)
        score += experienceScore
        
        // Reliability component (0-15 points)
        // High percentage of 5-star ratings = reliable
        if stats.hasRatings {
            let fiveStarPercentage = stats.percentage(for: 5)
            score += (fiveStarPercentage / 100.0) * 15.0
        } else {
            // New users get 8.0 points (slightly above neutral) as benefit of the doubt
            score += 8.0
        }
        
        // Recency component (0-10 points)
        // More recent applications get slight boost
        let hoursSinceApplication = Date().timeIntervalSince(application.appliedAt) / 3600
        let recencyScore = max(0, 10.0 - (hoursSinceApplication / 24.0))
        score += recencyScore
        
        // Price competitiveness component (0-5 points) - could be added later
        // For now, just add base points
        score += 2.5
        
        return score
    }
    
    /// Get ranking badge for an applicant
    func getRankingBadge(for application: JobApplication, in applications: [JobApplication], opportunity: Opportunity) -> String? {
        let rankedApps = rankApplicants(applications, opportunity: opportunity)
        
        guard let index = rankedApps.firstIndex(where: { $0.id == application.id }) else {
            return nil
        }
        
        switch index {
        case 0: return "Top Match"
        case 1: return "Great Match"
        case 2: return "Good Match"
        default: return nil
        }
    }
}


