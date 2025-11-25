//
//  Notification.swift
//  Communally
//
//  Notification model for in-app and push notifications
//

import Foundation
import FirebaseFirestore

enum NotificationType: String, Codable {
    case newOpportunity = "new_opportunity"
    case newApplication = "new_application"
    case applicationAccepted = "application_accepted"
    case applicationRejected = "application_rejected"
    case newMessage = "new_message"
    case paymentReceived = "payment_received"
    case paymentSent = "payment_sent"
    case paymentReleased = "payment_released"
    case paymentRefunded = "payment_refunded"
    case ratingReceived = "rating_received"
}

struct AppNotification: Identifiable, Codable {
    @DocumentID var id: String?
    let type: NotificationType
    let title: String
    let message: String
    let userId: String // Recipient user ID
    let relatedId: String? // Opportunity ID or Application ID
    let senderName: String?
    let senderImageData: Data?
    let createdAt: Date
    var isRead: Bool
    
    // Safe id access
    var safeId: String {
        return id ?? UUID().uuidString
    }
    
    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }
    
    var iconName: String {
        switch type {
        case .newOpportunity: return "briefcase.fill"
        case .newApplication: return "person.fill.badge.plus"
        case .applicationAccepted: return "checkmark.seal.fill"
        case .applicationRejected: return "xmark.circle.fill"
        case .newMessage: return "message.fill"
        case .paymentReceived: return "arrow.down.circle.fill"
        case .paymentSent: return "arrow.up.circle.fill"
        case .paymentReleased: return "checkmark.circle.fill"
        case .paymentRefunded: return "arrow.uturn.backward.circle.fill"
        case .ratingReceived: return "star.fill"
        }
    }
    
    var iconColor: String {
        switch type {
        case .newOpportunity: return "blue"
        case .newApplication: return "purple"
        case .applicationAccepted: return "green"
        case .applicationRejected: return "red"
        case .newMessage: return "orange"
        case .paymentReceived: return "green"
        case .paymentSent: return "blue"
        case .paymentReleased: return "green"
        case .paymentRefunded: return "orange"
        case .ratingReceived: return "yellow"
        }
    }
}

