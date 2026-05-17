//
//  JobTypeHelper.swift
//  Communally
//
//  Centralized helper for job type icons and colors (aligned with OpportunityCategory).
//

import SwiftUI

struct JobTypeHelper {

    /// Get the emoji for a job type string (matches `OpportunityCategory.rawValue`).
    static func emoji(for jobType: String) -> String {
        if let cat = OpportunityCategory.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(jobType) == .orderedSame }) {
            return cat.emoji
        }
        switch jobType.lowercased() {
        case "gardening": return "🌿"
        case "pet care": return "🐾"
        case "tutoring": return "📚"
        case "moving help": return "📦"
        case "painting": return "🎨"
        case "babysitting": return "👶"
        case "event help": return "🎉"
        case "cleaning": return "🧹"
        case "other": return "💼"
        default: return "💼"
        }
    }

    /// SF Symbol for a job type (legacy).
    static func icon(for jobType: String) -> String {
        if let cat = OpportunityCategory.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(jobType) == .orderedSame }) {
            return cat.icon
        }
        switch jobType.lowercased() {
        case "gardening": return "leaf.fill"
        case "pet care": return "pawprint.fill"
        case "tutoring": return "book.fill"
        case "moving help": return "box.truck.fill"
        case "painting": return "paintbrush.fill"
        case "babysitting": return "figure.2.and.child.holdinghands"
        case "event help": return "calendar.badge.plus"
        case "cleaning": return "sparkles"
        case "other": return "briefcase.fill"
        default: return "briefcase.fill"
        }
    }

    static func color(for jobType: String) -> Color {
        if let cat = OpportunityCategory.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(jobType) == .orderedSame }) {
            return cat.color
        }
        switch jobType.lowercased() {
        case "gardening": return Color(red: 0.2, green: 0.7, blue: 0.3)
        case "pet care": return Color(red: 0.95, green: 0.6, blue: 0.3)
        case "tutoring": return Color(red: 0.3, green: 0.5, blue: 0.9)
        case "moving help": return Color(red: 0.6, green: 0.4, blue: 0.2)
        case "painting": return Color(red: 0.8, green: 0.3, blue: 0.5)
        case "babysitting": return Color(red: 0.95, green: 0.7, blue: 0.8)
        case "event help": return Color(red: 0.5, green: 0.3, blue: 0.8)
        case "cleaning": return Color(red: 0.3, green: 0.8, blue: 0.9)
        case "other": return Color(red: 0.5, green: 0.5, blue: 0.5)
        default: return Color(red: 0.5, green: 0.5, blue: 0.5)
        }
    }
}
