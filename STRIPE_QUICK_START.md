# Stripe Quick Start Guide

🚀 Get Stripe payments working in **5 steps**!

## Step 1: Get Stripe Keys (5 min)

1. Go to https://dashboard.stripe.com
2. Sign up/log in
3. Click **Developers** → **API keys**
4. Copy your **Test Mode** keys:
   - `pk_test_...` (Publishable key)
   - `sk_test_...` (Secret key)

## Step 2: Deploy Firebase Functions (10 min)

```bash
cd "/Users/shauryagrover/Downloads/Communally-1 3/firebase-functions"

# Install dependencies
npm install

# Set Stripe keys
firebase functions:config:set stripe.secret_key="sk_test_YOUR_SECRET_KEY_HERE"
firebase functions:config:set stripe.webhook_secret="whsec_YOUR_WEBHOOK_SECRET_HERE"

# Deploy
firebase deploy --only functions
```

Or use the automated script:
```bash
cd "/Users/shauryagrover/Downloads/Communally-1 3"
./deploy-stripe-functions.sh
```

## Step 3: Add Stripe SDK to Xcode (5 min)

1. Open `Communally.xcodeproj` in Xcode
2. **File** → **Add Package Dependencies**
3. Paste: `https://github.com/stripe/stripe-ios`
4. Click **Add Package**
5. Select these products:
   - ✅ StripePaymentSheet
   - ✅ StripeCore
   - ✅ StripeUICore

## Step 4: Configure the App (5 min)

### A. Update `StripeConfig.swift`:
```swift
static let publishableKey = "pk_test_YOUR_KEY_HERE"  // ← Add your key
static let useMockPayments = false  // ← Change to false
```

### B. Uncomment in `StripeService.swift`:
Find these lines and **uncomment them**:

Line ~16-17:
```swift
import StripePaymentSheet
import StripeCore
```

Line ~28:
```swift
StripeAPI.defaultPublishableKey = StripeConfig.publishableKey
```

Lines ~139-169 (the whole PaymentSheet block):
```swift
var configuration = PaymentSheet.Configuration()
// ... uncomment entire block
```

Remove lines ~171-176 (the mock simulation).

## Step 5: Set Up Webhook (5 min)

1. Go to Stripe Dashboard → **Developers** → **Webhooks**
2. Click **Add endpoint**
3. URL: `https://us-central1-communally-a4cb3.cloudfunctions.net/stripeWebhook`
4. Select events:
   - ✅ `payment_intent.succeeded`
   - ✅ `payment_intent.payment_failed`
   - ✅ `account.updated`
5. Click **Add endpoint**
6. Copy the **Signing secret** (starts with `whsec_`)
7. Update your Firebase config:
   ```bash
   firebase functions:config:set stripe.webhook_secret="whsec_YOUR_SIGNING_SECRET"
   firebase deploy --only functions
   ```

## Test It Out! 🎉

### Test as Worker (Receive Money):
1. Sign in as Job Seeker
2. Go to Profile
3. Tap **Connect Bank Account**
4. Complete onboarding (use test data):
   - SSN: `000-00-0000`
   - Bank: `000123456789` (routing: `110000000`)

### Test as Hirer (Send Money):
1. Sign in as Job Hirer
2. Post a job
3. Accept an application
4. Go to payment
5. Use test card:
   - Card: `4242 4242 4242 4242`
   - Expiry: `12/34`
   - CVC: `123`

## Verify in Stripe Dashboard

- **Payments**: See all test transactions
- **Connect**: See connected worker accounts
- **Balance**: See your platform fees

## Common Issues

### "Invalid API Key"
- Double-check your publishable key in `StripeConfig.swift`
- Make sure you're using the **Test** key (starts with `pk_test_`)

### Functions Not Working
- Check deployment: `firebase deploy --only functions`
- View logs: `firebase functions:log`
- Verify config: `firebase functions:config:get`

### Payment Sheet Doesn't Appear
- Make sure you uncommented the import statements
- Verify Stripe SDK is added in Xcode
- Check you set `useMockPayments = false`

## Production Checklist

Before going live:

- [ ] Switch to **Live** mode keys in Stripe
- [ ] Update `publishableKey` and `secret_key` with live keys
- [ ] Update webhook URL to production
- [ ] Complete Stripe account activation
- [ ] Test with real small amounts first
- [ ] Enable Stripe Radar (fraud protection)
- [ ] Set up payout schedule

## Need Help?

- Full Guide: `STRIPE_SETUP_GUIDE.md`
- Stripe Docs: https://stripe.com/docs
- Firebase Docs: https://firebase.google.com/docs/functions

---

**That's it!** Stripe should now be fully functional in your app. 💳✨

