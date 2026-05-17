# Stripe Integration Setup Guide

## Overview
This guide will help you set up Stripe payments in the Communally app. The integration includes:
- **Payment Processing**: Hirers pay workers via Stripe Payment Sheet
- **Stripe Connect**: Workers connect their bank accounts to receive payouts
- **Firebase Functions**: Secure backend for handling Stripe operations

## Prerequisites
1. A Stripe account (sign up at https://stripe.com)
2. Firebase project set up and configured
3. Xcode with the Communally project

## Part 1: Stripe Account Setup

### 1.1 Get Your Stripe Keys
1. Log in to your Stripe Dashboard: https://dashboard.stripe.com
2. Go to **Developers** → **API keys**
3. Copy your **Publishable key** and **Secret key**
   - For development, use the **Test mode** keys
   - For production, use the **Live mode** keys (requires activation)

### 1.2 Enable Stripe Connect
1. In Stripe Dashboard, go to **Connect** → **Settings**
2. Click **Get started** to enable Connect
3. Under **Branding**, add your app logo and colors
4. Under **Connect settings**, set:
   - **Account type**: Express accounts
   - **Platform location**: United States (or your country)

### 1.3 Create Webhook Endpoint
1. Go to **Developers** → **Webhooks**
2. Click **Add endpoint**
3. Set the endpoint URL to: `https://us-central1-YOUR-PROJECT-ID.cloudfunctions.net/stripeWebhook`
   - Replace `YOUR-PROJECT-ID` with your Firebase project ID
4. Select events to listen to:
   - `payment_intent.succeeded`
   - `payment_intent.payment_failed`
   - `account.updated`
5. Click **Add endpoint**
6. Copy the **Signing secret** (starts with `whsec_`)

## Part 2: Firebase Functions Setup

### 2.1 Install Firebase CLI
```bash
npm install -g firebase-tools
```

### 2.2 Navigate to Functions Directory
```bash
cd "/Users/shauryagrover/Downloads/Communally-1 3/firebase-functions"
```

### 2.3 Install Dependencies
```bash
npm install
```

### 2.4 Configure Stripe Keys
Set your Stripe keys as Firebase Functions environment variables:

```bash
# Set your Stripe secret key
firebase functions:config:set stripe.secret_key="sk_test_YOUR_SECRET_KEY"

# Set your Stripe webhook secret
firebase functions:config:set stripe.webhook_secret="whsec_YOUR_WEBHOOK_SECRET"

# View your config to verify
firebase functions:config:get
```

### 2.5 Deploy Functions
```bash
firebase deploy --only functions
```

After deployment, you'll see output like:
```
✔  functions: Finished running predeploy script.
✔  functions[createPaymentIntent(us-central1)]: Successful create operation.
✔  functions[createConnectAccount(us-central1)]: Successful create operation.
✔  functions[connectAccountStatus(us-central1)]: Successful create operation.
✔  functions[stripeWebhook(us-central1)]: Successful create operation.

Functions deploy completed in 45s
```

**Note the Function URLs** - you'll need these for the iOS app configuration.

## Part 3: iOS App Configuration

### 3.1 Add Stripe SDK Package
1. Open `Communally.xcodeproj` in Xcode
2. Go to **File** → **Add Package Dependencies**
3. Enter the URL: `https://github.com/stripe/stripe-ios`
4. Select version: **24.3.0** or later
5. Click **Add Package**
6. Select the following libraries to add:
   - **StripePaymentSheet**
   - **StripeCore**
   - **StripeUICore**

### 3.2 Update StripeConfig.swift
Open `Communally/Services/StripeConfig.swift` and update:

```swift
struct StripeConfig {
    // Replace with your actual publishable key
    static let publishableKey = "pk_test_YOUR_PUBLISHABLE_KEY"
    
    // Replace with your Firebase Functions URL
    static let backendURL = "https://us-central1-YOUR-PROJECT-ID.cloudfunctions.net"
    
    // Set to false to use real Stripe payments
    static let useMockPayments = false
    
    // Keep the fee structure as is
    static let platformFeePercentage: Double = 0.05
    // ... rest of the file
}
```

### 3.3 Enable Stripe SDK Code
Open `Communally/Services/StripeService.swift` and:
1. **Uncomment** the import statements at the top:
   ```swift
   import StripePaymentSheet
   import StripeCore
   ```

2. **Uncomment** the SDK initialization in `init()`:
   ```swift
   StripeAPI.defaultPublishableKey = StripeConfig.publishableKey
   ```

3. **Uncomment** the Payment Sheet presentation code (lines 139-169)
4. **Remove** the mock payment simulation code (lines 171-176)

### 3.4 Update URL Scheme for Stripe Connect
1. In Xcode, select the **Communally** target
2. Go to the **Info** tab
3. Expand **URL Types**
4. Add a new URL Type:
   - **Identifier**: `communally`
   - **URL Schemes**: `communally`
5. This allows Stripe Connect to redirect back to your app

### 3.5 Update User Model
Open `Communally/Models/User.swift` and add these properties if not already present:

```swift
struct User: Identifiable, Codable {
    // ... existing properties ...
    
    // Stripe fields
    var stripeCustomerId: String? = nil
    var stripeConnectAccountId: String? = nil
    var stripeConnectActive: Bool = false
    var stripeConnectDetailsSubmitted: Bool = false
}
```

## Part 4: Testing

### 4.1 Test Stripe Connect (Worker Side)
1. Run the app and sign in as a **Job Seeker**
2. Go to your profile
3. Tap **Connect Bank Account**
4. Complete the Stripe Connect onboarding flow
5. Use test data:
   - **SSN**: `000-00-0000`
   - **Bank Account**: `000123456789` (routing: `110000000`)
   - **Date of Birth**: Any date making you 18+

### 4.2 Test Payment (Hirer Side)
1. Sign in as a **Job Hirer**
2. Create a new job opportunity
3. Have a worker apply to it
4. Accept the application
5. Proceed to payment
6. Use test card:
   - **Card Number**: `4242 4242 4242 4242`
   - **Expiry**: Any future date
   - **CVC**: Any 3 digits
   - **ZIP**: Any 5 digits

### 4.3 Verify Payment in Stripe Dashboard
1. Go to Stripe Dashboard → **Payments**
2. You should see the test payment
3. Go to **Connect** → **Accounts**
4. You should see the worker's Connect account
5. Check **Balance** to see platform fees collected

## Part 5: Production Checklist

Before going live with real payments:

- [ ] Switch from Stripe Test mode to Live mode keys
- [ ] Update webhook endpoint to use production Firebase Functions URL
- [ ] Set `useMockPayments = false` in StripeConfig.swift
- [ ] Complete Stripe account activation (provide business details)
- [ ] Set up proper error handling and logging
- [ ] Test with small real payments first
- [ ] Set up payout schedule in Stripe Dashboard
- [ ] Review and accept Stripe's Terms of Service
- [ ] Enable fraud detection (Stripe Radar)
- [ ] Set up email receipts in Stripe Dashboard

## Troubleshooting

### "Invalid API Key" Error
- Verify you've set the correct publishable key in StripeConfig.swift
- Make sure you're using the Test key for testing, not the Live key
- Check that the key starts with `pk_test_` for test mode

### Firebase Functions Not Working
- Verify functions deployed successfully: `firebase deploy --only functions`
- Check function logs: `firebase functions:log`
- Ensure Stripe secret key is set: `firebase functions:config:get`

### Payment Sheet Not Appearing
- Make sure you uncommented the Stripe SDK imports
- Verify Stripe SDK was added as a package dependency
- Check Xcode build logs for any missing imports

### Connect Onboarding Fails
- Verify URL scheme is configured correctly in Xcode
- Check that returnURL and refreshURL match your URL scheme
- Review Stripe Dashboard → Connect → Settings

## Support

For Stripe-specific issues:
- Stripe Documentation: https://stripe.com/docs
- Stripe Support: https://support.stripe.com

For Firebase Functions issues:
- Firebase Documentation: https://firebase.google.com/docs/functions
- Firebase Console: https://console.firebase.google.com

## Fee Structure

Current configuration:
- **Platform Fee**: 5% (configurable in StripeConfig.swift)
- **Stripe Fee**: 2.9% + $0.30 per transaction
- **Worker Payout**: 100% of agreed job amount
- **Hirer Pays**: Job amount + Platform fee + Stripe fee

Example for a $50 job:
- Job Amount: $50.00
- Platform Fee (5%): $2.50
- Subtotal: $52.50
- Stripe Fee: $1.82
- **Total Charged to Hirer**: $54.32
- **Worker Receives**: $50.00

## Next Steps

1. Complete this setup guide in order
2. Test thoroughly in Stripe Test mode
3. Review all payment flows end-to-end
4. When ready, switch to production keys
5. Start processing real payments!

Good luck! 🚀💳

