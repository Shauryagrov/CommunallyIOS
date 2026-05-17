//
//  SeekerRank.swift
//  Communally
//
//  Tier system for seekers based on completed jobs.
//

import SwiftUI

enum SeekerRank: String, CaseIterable, Codable {
    case bronze   = "Bronze"
    case silver   = "Silver"
    case gold     = "Gold"
    case platinum = "Platinum"

    /// Inclusive lower bound of completed jobs to reach this rank.
    var threshold: Int {
        switch self {
        case .bronze:   return 1
        case .silver:   return 10
        case .gold:     return 30
        case .platinum: return 75
        }
    }

    /// SF Symbol name for the rank badge.
    var iconName: String {
        switch self {
        case .bronze:   return "medal.fill"
        case .silver:   return "medal.fill"
        case .gold:     return "trophy.fill"
        case .platinum: return "crown.fill"
        }
    }

    /// Primary color for the badge fill.
    var primaryColor: Color {
        switch self {
        case .bronze:   return Color(red: 0.80, green: 0.50, blue: 0.20)
        case .silver:   return Color(red: 0.70, green: 0.72, blue: 0.78)
        case .gold:     return Color(red: 0.96, green: 0.78, blue: 0.20)
        case .platinum: return Color(red: 0.62, green: 0.78, blue: 0.92)
        }
    }

    /// Slightly darker accent for the gradient/border.
    var accentColor: Color {
        switch self {
        case .bronze:   return Color(red: 0.60, green: 0.36, blue: 0.10)
        case .silver:   return Color(red: 0.50, green: 0.52, blue: 0.58)
        case .gold:     return Color(red: 0.78, green: 0.58, blue: 0.10)
        case .platinum: return Color(red: 0.36, green: 0.46, blue: 0.78)
        }
    }

    /// Returns the highest rank earned for the given number of completed jobs.
    /// Returns nil if no rank earned yet (i.e., zero jobs).
    static func rank(forCompletedJobs jobs: Int) -> SeekerRank? {
        let earned = SeekerRank.allCases.filter { jobs >= $0.threshold }
        return earned.last
    }

    /// The next rank to aim for, and how many jobs remain to reach it.
    static func nextRank(afterCompletedJobs jobs: Int) -> (rank: SeekerRank, jobsRemaining: Int)? {
        if let next = SeekerRank.allCases.first(where: { jobs < $0.threshold }) {
            return (next, next.threshold - jobs)
        }
        return nil
    }
}

// MARK: - Badge

/// Rank medallion shown on profile + share poster. Larger and more visually
/// prominent than the previous capsule pill — leads with a glowing tier
/// medal, "RANK" label, and the tier name as a subtitle.
/// Use `compact` for dense rows; default for profile headers / posters.
struct SeekerRankBadge: View {
    let rank: SeekerRank
    var compact: Bool = false

    private var medalSize: CGFloat   { compact ? 28 : 44 }
    private var iconFontSize: CGFloat { compact ? 14 : 22 }
    private var rankFontSize: CGFloat { compact ? 9  : 11 }
    private var tierFontSize: CGFloat { compact ? 11 : 14 }

    var body: some View {
        HStack(spacing: compact ? 8 : 12) {
            // Glowing tier medal
            ZStack {
                Circle()
                    .fill(rank.accentColor.opacity(0.35))
                    .frame(width: medalSize + 8, height: medalSize + 8)
                    .blur(radius: 6)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [rank.primaryColor, rank.accentColor],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: medalSize, height: medalSize)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.55), lineWidth: compact ? 1 : 1.5)
                    )

                Image(systemName: rank.iconName)
                    .font(.system(size: iconFontSize, weight: .black))
                    .foregroundColor(.white)
                    .shadow(color: rank.accentColor.opacity(0.6), radius: 2, x: 0, y: 1)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("RANK")
                    .font(.system(size: rankFontSize, weight: .heavy, design: .rounded))
                    .tracking(1.6)
                    .foregroundColor(rank.accentColor.opacity(0.85))
                Text(rank.rawValue)
                    .font(.system(size: tierFontSize, weight: .heavy, design: .rounded))
                    .tracking(0.4)
                    .foregroundColor(rank.accentColor)
            }
        }
        .padding(.horizontal, compact ? 10 : 14)
        .padding(.vertical, compact ? 6 : 10)
        .background(
            RoundedRectangle(cornerRadius: compact ? 16 : 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: compact ? 16 : 22, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    rank.primaryColor.opacity(0.12),
                                    rank.accentColor.opacity(0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: compact ? 16 : 22, style: .continuous)
                .stroke(rank.accentColor.opacity(0.30), lineWidth: 1)
        )
        .shadow(color: rank.accentColor.opacity(0.25), radius: compact ? 6 : 12, x: 0, y: 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rank \(rank.rawValue)")
    }
}

#Preview {
    VStack(spacing: 16) {
        SeekerRankBadge(rank: .bronze)
        SeekerRankBadge(rank: .silver)
        SeekerRankBadge(rank: .gold)
        SeekerRankBadge(rank: .platinum)
        Divider()
        SeekerRankBadge(rank: .bronze, compact: true)
        SeekerRankBadge(rank: .platinum, compact: true)
    }
    .padding()
}
