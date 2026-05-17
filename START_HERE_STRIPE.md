# 🚀 START HERE - Get Stripe Working in 3 Steps!

I've set up 90% of the Stripe integration for you. Here's what you need to do to finish:

## ✅ What's Already Done

- ✅ Firebase Functions backend (all payment logic)
- ✅ iOS app code (fully integrated)
- ✅ Stripe Connect support (workers get paid)
- ✅ Payment breakdown (transparent fees)
- ✅ Documentation (comprehensive guides)

## 🎯 What You Need To Do (30 minutes total)

### 1️⃣ Add Stripe SDK to Xcode (5 min)

Open your Xcode project and:
1. **File** → **Add Package Dependencies**
2. Paste this URL: `https://github.com/stripe/stripe-ios`
3. Click **Add Package**
4. Select these 3 products:
   - StripePaymentSheet ✅
   - StripeCore ✅  
   - StripeUICore ✅
5. Click **Add Package** again

### 2️⃣ Get Stripe Keys & Deploy Backend (15 min)

```bash
# 1. Get your Stripe keys
# Go to: https://dashboard.stripe.com/apikeys
# Copy your Test mode keys (pk_test_... and sk_test_...)

# 2. Deploy the Firebase Functions
cd "/Users/shauryagrover/Downloads/Communally-1 4/firebase-functions"
npm install

# 3. Configure backend secrets in .env (required)
cp .env.example .env
# edit .env and set STRIPE_SECRET_KEY + STRIPE_WEBHOOK_SECRET

# 4. Deploy to Firebase
cd ..
firebase deploy --only functions

# ✅ Done! The functions are live.
```

### 3️⃣ Add Your Publishable Key (1 min)

Open `Communally/Services/StripeConfig.swift` and change line 12:

```swift
// Change this:
static let publishableKey = "pk_test_51SZLJPCIwT72dLp9TDdUu9geIdC7w4SkfWFjEjBJOHv9h022oGc4OeFrgh8ictWUBfe95ycVWhXg8Ny5i8e7ojUQ00dFF2nZSx"

// To your actual key:
static let publishableKey = "pk_test_YOUR_PUBLISHABLE_KEY_HERE"
```

---

## 🎉 That's It! You're Done!

Build and run the app. Stripe is now fully working!

### Test It:

**As a Worker:**
- Complete a job
- Tap "Connect Bank Account"
- Use test SSN: `000-00-0000`
- Use test bank: `000123456789`

**As a Hirer:**
- Post a job
- Accept an application  
- Pay the worker
- Use test card: `4242 4242 4242 4242`

---

## 📚 More Help?

- **Quick Start**: `STRIPE_QUICK_START.md` (5-step guide)
- **Full Guide**: `STRIPE_SETUP_GUIDE.md` (everything explained)
- **Implementation**: `STRIPE_IMPLEMENTATION_COMPLETE.md` (technical details)

---

## 🔧 Optional: Set Up Webhooks (10 min)

This makes payment events work automatically:

1. Go to: https://dashboard.stripe.com/webhooks
2. Click **Add endpoint**
3. URL: `https://us-central1-communally-a4cb3.cloudfunctions.net/stripeWebhook`
4. Select events:
   - `payment_intent.succeeded` ✅
   - `payment_intent.payment_failed` ✅
   - `account.updated` ✅
5. Copy the signing secret (starts with `whsec_`)
6. Run:
   ```bash
   # update firebase-functions/.env with webhook secret:
   # STRIPE_WEBHOOK_SECRET=whsec_YOUR_SECRET
   firebase deploy --only functions
   ```

---

## ❓ Need Help?

If step 1 or 2 doesn't work:
- Check `STRIPE_QUICK_START.md` for detailed instructions
- Run `./deploy-stripe-functions.sh` for automated deployment
- See `STRIPE_SETUP_GUIDE.md` for troubleshooting

---

**You're literally 3 steps away from working payments! Let's go! 💪💳**

