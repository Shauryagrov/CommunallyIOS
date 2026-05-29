//
//  OpportunityCategory.swift
//  Communally
//
//  Single source of truth for job/opportunity categories (posting, filters, onboarding).
//

import SwiftUI

enum OpportunityCategory: String, CaseIterable, Identifiable {
    case gardening = "Gardening"
    case petCare = "Pet Care"
    case tutoring = "Tutoring"
    case moving = "Moving Help"
    case painting = "Painting"
    case babysitting = "Babysitting"
    case eventHelp = "Event Help"
    case cleaning = "Cleaning"
    case other = "Other"

    var id: String { rawValue }

    /// Titles shown in hirer/seeker onboarding and filters (same as posting).
    static var allTitles: [String] {
        allCases.map(\.rawValue)
    }

    var emoji: String {
        switch self {
        case .gardening: return "🌿"
        case .petCare: return "🐾"
        case .tutoring: return "📚"
        case .moving: return "📦"
        case .painting: return "🎨"
        case .babysitting: return "👶"
        case .eventHelp: return "🎉"
        case .cleaning: return "🧹"
        case .other: return "💼"
        }
    }

    var icon: String {
        switch self {
        case .gardening: return "leaf.fill"
        case .petCare: return "pawprint.fill"
        case .tutoring: return "book.fill"
        case .moving: return "box.truck.fill"
        case .painting: return "paintbrush.fill"
        case .babysitting: return "figure.2.and.child.holdinghands"
        case .eventHelp: return "calendar.badge.plus"
        case .cleaning: return "sparkles"
        case .other: return "briefcase.fill"
        }
    }

    var color: Color {
        switch self {
        case .gardening: return Color(red: 0.2, green: 0.7, blue: 0.3)
        case .petCare: return Color(red: 0.95, green: 0.6, blue: 0.3)
        case .tutoring: return Color(red: 0.3, green: 0.5, blue: 0.9)
        case .moving: return Color(red: 0.6, green: 0.4, blue: 0.2)
        case .painting: return Color(red: 0.8, green: 0.3, blue: 0.5)
        case .babysitting: return Color(red: 0.95, green: 0.7, blue: 0.8)
        case .eventHelp: return CommunallyTheme.primaryGreen
        case .cleaning: return Color(red: 0.3, green: 0.8, blue: 0.9)
        case .other: return Color(red: 0.5, green: 0.5, blue: 0.5)
        }
    }

    // MARK: - Pay guidance (whole USD per hour)
    //
    // Pay on Communally is per-hour. The job's total is hourly rate × duration
    // (start/end times set at posting). Floors are teen-friendly entry rates;
    // skilled work (e.g. tutoring) gets a higher ceiling.

    /// Platform-wide hourly bounds for any job post.
    /// ⚠️ TEMPORARY: minimum lowered to $1/hr for testing + cheap demo
    /// seeding (so a 1-hour job costs ~$1 to fund instead of $20+).
    /// REVERT to 20 before public launch — $1/hr is below any real wage
    /// floor and not a sane production minimum.
    static let platformPayMinimumUSD: Int = 1
    static let platformPayMaximumUSD: Int = 50

    /// Suggested default $/hr when the hirer picks this category.
    var suggestedPayUSD: Int {
        switch self {
        case .gardening: return 25
        case .petCare: return 18
        case .tutoring: return 30
        case .moving: return 30
        case .painting: return 30
        case .babysitting: return 20
        case .eventHelp: return 25
        case .cleaning: return 22
        case .other: return 20
        }
    }

    /// Category-specific $/hr minimum (clamped to platform bounds).
    /// ⚠️ TEMPORARY: forced to the platform minimum ($1/hr) so every
    /// category allows cheap test/demo jobs. To RESTORE per-category
    /// floors before launch, delete the early `return` line below — the
    /// original switch is preserved underneath it.
    var categoryPayMinimumUSD: Int {
        return Self.platformPayMinimumUSD   // TEMP — remove this line to restore floors

        let n: Int
        switch self {
        case .gardening: n = 18
        case .petCare: n = 15
        case .tutoring: n = 20
        case .moving: n = 22
        case .painting: n = 22
        case .babysitting: n = 15
        case .eventHelp: n = 18
        case .cleaning: n = 18
        case .other: n = Self.platformPayMinimumUSD
        }
        return min(max(n, Self.platformPayMinimumUSD), Self.platformPayMaximumUSD)
    }

    /// Category-specific $/hr maximum (clamped to platform bounds).
    var categoryPayMaximumUSD: Int {
        let n: Int
        switch self {
        case .gardening: n = 80
        case .petCare: n = 60
        case .tutoring: n = 100
        case .moving: n = 80
        case .painting: n = 80
        case .babysitting: n = 60
        case .eventHelp: n = 80
        case .cleaning: n = 70
        case .other: n = 80
        }
        return min(max(n, Self.platformPayMinimumUSD), Self.platformPayMaximumUSD)
    }
}
