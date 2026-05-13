//
//  StripeConfig.swift
//  Communally
//
//  Stripe API configuration
//

import Foundation

struct StripeConfig {
    /// **Live publishable key** from Stripe Dashboard → Developers → API keys (`pk_live_…`).
    /// It must be from the **same Stripe account** as `STRIPE_SECRET_KEY` in `firebase-functions/.env`.
    /// Publishable keys are designed to be shipped in client code — they can only create
    /// payment intents and tokenize cards, never read account data or move money.
    static let publishableKey = "pk_live_51TQYrgFVwvjPmeGMochQKpM6fb7g7ZlK2DPRH8fc8yZy8ZQ9wvgHlPh2ND2UhAYWqVUohNrTAIE164Jt1OFbYFfA00W7BA0txO"
    // Secret keys must never be bundled in the app. Configure them only in Firebase Functions.
    
    // Backend URL for payment processing
    static let backendURL = "https://us-central1-communally-a4cb3.cloudfunctions.net"
    
    // Development mode - uses mock responses when true
    // Set to false once Firebase Functions are deployed and Stripe is configured
    static let useMockPayments = false
    
    /// When `true`, hirers must pass Stripe Identity before posting paid listings.
    /// Set to `false` so verification becomes a visible trust signal (badge)
    /// instead of a hard gate. Flip back to `true` to re-enable the pre-post block.
    static let requireStripeIdentityForPaidPosts = false
    
    // Platform take rate is split across both sides so neither side feels
    // gouged: the hirer sees a 5% fee added to their charge, and the worker
    // sees a 5% fee deducted from their payout. Communally keeps both
    // pieces, for a 10% effective platform take.
    static let hirerFeePercentage: Double  = 0.05   // added to charge
    static let workerFeePercentage: Double = 0.05   // deducted from payout

    /// Backwards-compat alias — older call sites still reference
    /// `platformFeePercentage` as "the fee added to the hirer's bill."
    static var platformFeePercentage: Double { hirerFeePercentage }

    // Stripe fee calculation (2.9% + $0.30) - Based on total amount charged
    static func calculateStripeFee(totalCharged: Double) -> Double {
        return (totalCharged * 0.029) + 0.30
    }

    /// 5% added to the hirer's bill (sits on top of `jobAmount`).
    static func calculatePlatformFee(jobAmount: Double) -> Double {
        return jobAmount * hirerFeePercentage
    }

    /// 5% deducted from the worker's payout. Stays in Communally's Stripe
    /// balance after the `stripe.transfers.create(...)` step in
    /// `releasePayment` (Cloud Function transfers `workerPayout`, not the
    /// full `jobAmount`).
    static func calculateWorkerFee(jobAmount: Double) -> Double {
        return jobAmount * workerFeePercentage
    }

    // Total amount to charge hirer (job amount + platform fee + Stripe fee).
    // Stripe's 2.9% + $0.30 applies to the final charge, so we solve for the
    // total algebraically: total = (subtotal + 0.30) / (1 - 0.029)
    static func calculateTotalCharge(jobAmount: Double) -> Double {
        let platformFee = calculatePlatformFee(jobAmount: jobAmount)
        let subtotal = jobAmount + platformFee
        return (subtotal + 0.30) / (1.0 - 0.029)
    }

    /// Worker receives `jobAmount` minus the 5% worker-side fee.
    static func calculateWorkerPayout(jobAmount: Double) -> Double {
        return jobAmount - calculateWorkerFee(jobAmount: jobAmount)
    }

    // Get full breakdown. Total is solved algebraically so Stripe's fee is
    // exact: total = (subtotal + 0.30) / (1 - 0.029)
    static func getPaymentBreakdown(amount: Double) -> PaymentBreakdown {
        let platformFee = calculatePlatformFee(jobAmount: amount)
        let workerFee = calculateWorkerFee(jobAmount: amount)
        let subtotal = amount + platformFee
        let totalCharged = (subtotal + 0.30) / (1.0 - 0.029)
        let stripeFee = totalCharged - subtotal

        return PaymentBreakdown(
            jobAmount: amount,
            platformFee: platformFee,
            workerFee: workerFee,
            stripeFee: stripeFee,
            totalCharged: totalCharged,
            workerPayout: amount - workerFee
        )
    }
}

struct PaymentBreakdown {
    let jobAmount: Double          // Headline rate (e.g., $50)
    let platformFee: Double        // 5% hirer-side fee (e.g., $2.50)
    let workerFee: Double          // 5% worker-side fee (e.g., $2.50)
    let stripeFee: Double          // Stripe's processing fee (e.g., $1.88)
    let totalCharged: Double       // What hirer actually pays (e.g., $54.38)
    let workerPayout: Double       // What worker actually receives (e.g., $47.50)

    /// Combined Communally take (both halves of the split).
    var combinedPlatformFee: Double { platformFee + workerFee }

    var formattedJobAmount: String {
        return String(format: "$%.2f", jobAmount)
    }

    var formattedPlatformFee: String {
        return String(format: "$%.2f", platformFee)
    }

    var formattedWorkerFee: String {
        return String(format: "$%.2f", workerFee)
    }

    var formattedStripeFee: String {
        return String(format: "$%.2f", stripeFee)
    }

    var formattedTotalCharged: String {
        return String(format: "$%.2f", totalCharged)
    }

    var formattedWorkerPayout: String {
        return String(format: "$%.2f", workerPayout)
    }
}
