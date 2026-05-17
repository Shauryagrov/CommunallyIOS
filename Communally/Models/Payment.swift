//
//  Payment.swift
//  Communally
//
//  Payment models for Stripe integration
//

import Foundation
import FirebaseFirestore

enum PaymentStatus: String, Codable {
    case pending = "pending"           // Not yet charged
    case processing = "processing"     // Payment in progress
    case held = "held"                // Charged, held in escrow
    case payable = "payable"          // Job completed by both — sitting in worker's in-app balance, awaiting cash out
    case released = "released"        // Paid to worker
    case refunded = "refunded"        // Returned to hirer
    case failed = "failed"            // Payment failed
    case cancelled = "cancelled"      // Job cancelled before payment
}

struct Payment: Identifiable, Codable {
    @DocumentID var id: String?
    
    // Related entities
    let applicationId: String
    let opportunityId: String
    let opportunityTitle: String
    
    // Parties involved
    let hirerId: String
    let hirerName: String
    let workerId: String
    let workerName: String
    
    // Amount breakdown
    let jobAmount: Double          // e.g., 50.00 (headline rate, what worker is told)
    let platformFee: Double        // e.g., 2.50 (5% hirer-side fee, added to charge)
    /// 5% worker-side fee deducted from the payout. Optional for backwards
    /// compatibility — pre-2026-05-09 Payment docs had no worker fee.
    var workerFee: Double?         // e.g., 2.50 (5% worker-side fee, deducted from payout)
    let stripeFee: Double          // e.g., 1.88 (Stripe processing, charged on total)
    let totalCharged: Double       // e.g., 54.38 (what hirer pays)
    let workerPayout: Double       // e.g., 47.50 (jobAmount - workerFee)
    
    // Stripe identifiers
    var stripePaymentIntentId: String?
    var stripeTransferId: String?
    var stripeCustomerId: String?
    
    // Status and timestamps
    var status: PaymentStatus
    let createdAt: Date
    var chargedAt: Date?
    var releasedAt: Date?
    var refundedAt: Date?
    
    // Optional metadata
    var failureReason: String?
    var refundReason: String?
    
    var safeId: String {
        id ?? UUID().uuidString
    }
    
    var formattedJobAmount: String {
        return String(format: "$%.2f", jobAmount)
    }
    
    var formattedTotalCharged: String {
        return String(format: "$%.2f", totalCharged)
    }
    
    var formattedWorkerPayout: String {
        return String(format: "$%.2f", workerPayout)
    }
    
    var formattedPlatformFee: String {
        return String(format: "$%.2f", platformFee)
    }
    
    var statusDisplay: String {
        switch status {
        case .pending: return "Pending"
        case .processing: return "Processing..."
        case .held: return "Payment Held"
        case .payable: return "Ready to Cash Out"
        case .released: return "Paid"
        case .refunded: return "Refunded"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }

    var statusColor: String {
        switch status {
        case .pending: return "gray"
        case .processing: return "blue"
        case .held: return "orange"
        case .payable: return "green"
        case .released: return "green"
        case .refunded: return "purple"
        case .failed: return "red"
        case .cancelled: return "gray"
        }
    }
}

