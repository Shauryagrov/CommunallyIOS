# 💳 Stripe Payment Integration - Complete Guide

## 🎯 What We're Building

A complete payment system where:
- Hirers pay when they accept an application
- Money is held in escrow
- Payment released when job is marked complete
- You take a 10% platform fee
- Stripe handles all the complexity

---

## 📋 Prerequisites

### 1. Create Stripe Account
1. Go to https://stripe.com
2. Click "Start now"
3. Sign up with your business email
4. Complete verification
5. ⏱️ Time: 5 minutes

### 2. Enable Stripe Connect
1. Go to Stripe Dashboard
2. Click "Connect" in left sidebar
3. Click "Get started"
4. Choose "Platform" type
5. ⏱️ Time: 2 minutes

### 3. Get API Keys
1. Go to Developers → API keys
2. Copy "Publishable key" (starts with `pk_test_`)
3. Copy "Secret key" (starts with `sk_test_`)
4. Save securely!
5. ⏱️ Time: 1 minute

---

## 🔧 Installation

### Step 1: Add Stripe SDK

Add to `Package.swift` dependencies:
```swift
dependencies: [
    .package(url: "https://github.com/stripe/stripe-ios", from: "23.0.0")
]
```

Or in Xcode:
1. File → Add Package Dependencies
2. Paste: `https://github.com/stripe/stripe-ios`
3. Add to target "Communally"

### Step 2: Add to Info.plist

Add URL scheme for payment redirects:
```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>communally-payments</string>
        </array>
    </dict>
</array>
```

---

## 💰 Money Flow Architecture

### How Money Moves:

```
1. CHARGE (When job accepted)
   Hirer's Card → Stripe Escrow ($50)
   
2. HOLD (During job)
   Money sits in Stripe
   
3. RELEASE (When complete)
   Stripe → Your Platform Account ($5)
   Stripe → Worker's Bank ($43.25)
   Stripe → Stripe Fees ($1.75)
```

### Fee Breakdown:
- **Hirer pays**: $50.00 (100%)
- **Stripe fee**: $1.75 (3.5%)
- **Your fee**: $5.00 (10%)
- **Worker gets**: $43.25 (86.5%)

---

## 📁 Files to Create

### 1. PaymentManager.swift
```swift
import Foundation
import StripePaymentSheet

class PaymentManager: ObservableObject {
    static let shared = PaymentManager()
    
    private let publishableKey = "pk_test_YOUR_KEY_HERE"
    private let backendURL = "YOUR_BACKEND_URL"
    
    @Published var paymentSheet: PaymentSheet?
    @Published var paymentResult: PaymentSheetResult?
    
    func configure() {
        StripeAPI.defaultPublishableKey = publishableKey
    }
    
    // Create payment intent on backend
    func createPaymentIntent(
        amount: Int,
        applicationId: String,
        hirerId: String,
        workerId: String
    ) async throws -> String {
        // Call your Firebase Function
        // Returns payment intent client secret
    }
    
    // Present payment sheet
    func presentPaymentSheet(
        clientSecret: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        var configuration = PaymentSheet.Configuration()
        configuration.merchantDisplayName = "Communally"
        configuration.applePay = .init(
            merchantId: "merchant.com.communally",
            merchantCountryCode: "US"
        )
        
        self.paymentSheet = PaymentSheet(
            paymentIntentClientSecret: clientSecret,
            configuration: configuration
        )
    }
    
    // Release payment to worker
    func releasePayment(
        applicationId: String
    ) async throws {
        // Call backend to transfer funds
    }
    
    // Refund payment
    func refundPayment(
        paymentIntentId: String
    ) async throws {
        // Call backend to refund
    }
}
```

### 2. Firebase Functions (Backend)

Create `functions/index.js`:
```javascript
const functions = require('firebase-functions');
const stripe = require('stripe')(process.env.STRIPE_SECRET_KEY);

// Create payment intent
exports.createPaymentIntent = functions.https.onCall(async (data, context) => {
    const { amount, applicationId, workerId } = data;
    
    // Create Stripe customer for hirer
    const customer = await stripe.customers.create({
        metadata: { userId: context.auth.uid }
    });
    
    // Create payment intent
    const paymentIntent = await stripe.paymentIntents.create({
        amount: amount * 100, // Convert to cents
        currency: 'usd',
        customer: customer.id,
        metadata: {
            applicationId: applicationId,
            workerId: workerId
        },
        capture_method: 'manual' // Hold, don't capture yet
    });
    
    return { clientSecret: paymentIntent.client_secret };
});

// Release payment to worker
exports.releasePayment = functions.https.onCall(async (data, context) => {
    const { paymentIntentId, workerId, workerAmount, platformFee } = data;
    
    // Capture the payment intent
    await stripe.paymentIntents.capture(paymentIntentId);
    
    // Transfer to worker (via Stripe Connect)
    await stripe.transfers.create({
        amount: workerAmount * 100,
        currency: 'usd',
        destination: workerId, // Worker's Stripe Connect account
        description: 'Job payment'
    });
    
    // Platform fee stays in your account automatically
    
    return { success: true };
});

// Refund payment
exports.refundPayment = functions.https.onCall(async (data, context) => {
    const { paymentIntentId } = data;
    
    await stripe.refunds.create({
        payment_intent: paymentIntentId
    });
    
    return { success: true };
});
```

### 3. Payment Model
```swift
struct Payment: Identifiable, Codable {
    @DocumentID var id: String?
    
    let applicationId: String
    let opportunityId: String
    let opportunityTitle: String
    
    let hirerId: String
    let hirerName: String
    let workerId: String
    let workerName: String
    
    let totalAmount: Double        // e.g., 50.00
    let platformFee: Double         // e.g., 5.00
    let stripeFee: Double          // e.g., 1.75
    let workerPayout: Double       // e.g., 43.25
    
    let stripePaymentIntentId: String?
    let stripeTransferId: String?
    let stripeCustomerId: String?
    
    var status: PaymentStatus
    let createdAt: Date
    var chargedAt: Date?
    var releasedAt: Date?
    var refundedAt: Date?
    
    var safeId: String {
        id ?? UUID().uuidString
    }
}

enum PaymentStatus: String, Codable {
    case pending        // Not yet charged
    case held          // Charged, in escrow
    case released      // Paid to worker
    case refunded      // Returned to hirer
    case failed        // Payment failed
}
```

### 4. PaymentSheet View
```swift
struct PaymentCheckoutView: View {
    let opportunity: Opportunity
    let application: JobApplication
    @StateObject private var paymentManager = PaymentManager.shared
    @State private var paymentCompleted = false
    
    var body: some View {
        VStack {
            // Payment details
            PaymentSummaryCard(
                amount: opportunity.payAmount,
                platformFee: calculatePlatformFee(opportunity.payAmount)
            )
            
            // Apple Pay button
            if let paymentSheet = paymentManager.paymentSheet {
                PaymentSheet.PaymentButton(
                    paymentSheet: paymentSheet
                ) {
                    paymentSheet.present(from: getRootViewController()) { result in
                        switch result {
                        case .completed:
                            paymentCompleted = true
                        case .failed(let error):
                            print("Payment failed: \(error)")
                        case .canceled:
                            print("Payment canceled")
                        }
                    }
                }
            }
        }
    }
}
```

---

## 🔄 Integration with Existing Code

### Modify ApplicationManager.swift

When accepting application:
```swift
func acceptApplication(applicationId: String) {
    // ... existing code ...
    
    // Create payment intent
    Task {
        let amount = opportunity.payAmount
        let clientSecret = try await PaymentManager.shared.createPaymentIntent(
            amount: Int(amount),
            applicationId: applicationId,
            hirerId: opportunity.hirerId,
            workerId: application.applicantId
        )
        
        // Present payment sheet
        await PaymentManager.shared.presentPaymentSheet(
            clientSecret: clientSecret
        ) { result in
            switch result {
            case .success:
                // Payment held successfully
                // Continue with acceptance
            case .failure:
                // Payment failed
                // Show error, don't accept
            }
        }
    }
}
```

### Modify JobCompletionView.swift

When marking complete:
```swift
private func completeJob() {
    // ... existing code ...
    
    // Release payment
    Task {
        do {
            try await PaymentManager.shared.releasePayment(
                applicationId: application.id
            )
            
            print("✅ Payment released to worker")
        } catch {
            print("❌ Payment release failed: \(error)")
        }
    }
}
```

---

## 🧪 Testing

### Test Cards:
- **Success**: `4242 4242 4242 4242`
- **Decline**: `4000 0000 0000 0002`
- **3D Secure**: `4000 0027 6000 3184`
- **Any future date**: `12/34`
- **Any CVC**: `123`

### Test Flow:
```
1. Create test job ($20)
2. Apply as test user
3. Accept application
4. Payment sheet shows
5. Enter test card 4242...
6. Payment held in Stripe
7. Mark job complete
8. Payment released
9. Check Stripe dashboard
10. Verify transfer
```

---

## 💵 Fee Calculations

```swift
func calculateFees(amount: Double) -> (platform: Double, stripe: Double, worker: Double) {
    let stripeFee = amount * 0.029 + 0.30  // 2.9% + $0.30
    let platformFee = amount * 0.10         // 10%
    let workerPayout = amount - stripeFee - platformFee
    
    return (platformFee, stripeFee, workerPayout)
}

// Example:
calculateFees(50.00)
// Returns: (5.00, 1.75, 43.25)
```

---

## 🔐 Security

### Environment Variables:
```swift
// Never commit keys to git!
// Use build configurations

#if DEBUG
let stripePublishableKey = "pk_test_..."
#else
let stripePublishableKey = "pk_live_..."
#endif
```

### Backend Security:
- Use Firebase Authentication
- Verify user identity
- Validate amounts
- Log all transactions
- Rate limiting

---

## 📊 What You'll Earn

### Revenue Projections:

| Jobs/Day | Avg Price | Your 10% | Monthly |
|----------|-----------|----------|---------|
| 10 | $30 | $30/day | $900 |
| 50 | $40 | $200/day | $6,000 |
| 100 | $50 | $500/day | $15,000 |
| 500 | $50 | $2,500/day | $75,000 |
| 1000 | $50 | $5,000/day | $150,000 |

*Note: Subtract ~3.5% Stripe fees*

---

## 🚀 Launch Checklist

- [ ] Stripe account created
- [ ] Connect enabled
- [ ] API keys obtained
- [ ] SDK installed
- [ ] Backend functions deployed
- [ ] Payment testing complete
- [ ] Error handling added
- [ ] Refund flow tested
- [ ] Worker onboarding tested
- [ ] Production keys configured
- [ ] Terms updated (payment terms)
- [ ] Support docs created

---

## ⚠️ Important Notes

### For Workers (Getting Paid):
1. Must complete Stripe Connect onboarding
2. Provide bank account details
3. Verify identity (required by law)
4. Can choose payout schedule
5. Get Stripe debit card (optional, instant access)

### For Hirers (Paying):
1. Save payment method
2. Or use Apple Pay (one-tap)
3. Auto-charge on job acceptance
4. View payment history
5. Get receipts

### Legal Requirements:
- Terms must mention payment processing
- Privacy policy must mention Stripe
- Collect 1099 info for workers (US)
- Comply with local payment laws
- PCI compliance (handled by Stripe)

---

## 📞 Support & Resources

- Stripe Docs: https://stripe.com/docs/payments/accept-a-payment
- Connect Guide: https://stripe.com/docs/connect
- iOS SDK: https://stripe.com/docs/mobile/ios
- Test Cards: https://stripe.com/docs/testing
- Support: support@stripe.com

---

## 🎯 Next Steps

1. **Sign up for Stripe** (5 min)
2. **Get API keys** (2 min)
3. **Add SDK to project** (5 min)
4. **Create PaymentManager** (1 hour)
5. **Deploy Firebase Functions** (30 min)
6. **Test with test cards** (1 hour)
7. **Integrate with completion flow** (1 hour)
8. **Go live!** 🚀

---

**Total Implementation Time**: 1-2 days  
**Difficulty**: Moderate  
**Revenue Potential**: Unlimited! 💰

Ready to add payments and start earning? Let's do it! 🎉

