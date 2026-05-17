# 🚀 Deploy Stripe Backend - Step by Step

## ✅ **Good News: Everything is Already Written!**

Your Firebase Functions are complete and ready to deploy. Just follow these steps:

---

## 📋 **Step 1: Install Firebase CLI**

Open Terminal and run:

```bash
npm install -g firebase-tools
```

---

## 🔐 **Step 2: Login to Firebase**

```bash
firebase login
```

This will open your browser - sign in with your Google account (the one for Firebase project).

---

## 🔑 **Step 3: Set Stripe Secret Key in .env**

Your Firebase Functions need Stripe environment variables in `firebase-functions/.env`:

```bash
cd "/Users/shauryagrover/Downloads/Communally-1 4/firebase-functions"
cp .env.example .env
# Edit .env and set:
# STRIPE_SECRET_KEY=sk_test_YOUR_SECRET_KEY_HERE
# STRIPE_WEBHOOK_SECRET=whsec_YOUR_WEBHOOK_SECRET_HERE
```

---

## 📦 **Step 4: Install Dependencies**

```bash
cd firebase-functions
npm install
cd ..
```

---

## 🚀 **Step 5: Deploy Functions**

```bash
firebase deploy --only functions
```

**This will take 2-5 minutes.** You'll see output like:

```
✔  functions: Finished running predeploy script.
i  functions: ensuring required API cloudfunctions.googleapis.com is enabled...
✔  functions: required API cloudfunctions.googleapis.com is enabled
i  functions: preparing functions directory for uploading...
i  functions: packaged functions (123.4 KB) for uploading
✔  functions: functions folder uploaded successfully
i  functions: creating Node.js 20 function createPaymentIntent...
i  functions: creating Node.js 20 function createConnectAccount...
i  functions: creating Node.js 20 function connectAccountStatus...
i  functions: creating Node.js 20 function stripeWebhook...
✔  functions[createPaymentIntent(us-central1)] Successful create operation.
✔  functions[createConnectAccount(us-central1)] Successful create operation.
✔  functions[connectAccountStatus(us-central1)] Successful create operation.
✔  functions[stripeWebhook(us-central1)] Successful create operation.

✔  Deploy complete!

Project Console: https://console.firebase.google.com/project/communally-a4cb3/overview
Functions URL: https://us-central1-communally-a4cb3.cloudfunctions.net
```

---

## ✅ **Step 6: Verify Deployment**

Check your functions are live:

```bash
firebase functions:list
```

You should see:
- ✅ createPaymentIntent
- ✅ createConnectAccount
- ✅ connectAccountStatus
- ✅ stripeWebhook

---

## 🎯 **Step 7: Update App to Use Real Backend**

Now disable test mode in your app:

1. Open Xcode
2. Open `Communally/Services/StripeConfig.swift`
3. Find line 22: `static let useMockPayments = false`
4. Make sure it says `false` (it already does!)
5. Build and run!

---

## 🧪 **Step 8: Test It!**

### **Test Bank Connection:**

1. Sign in as Job Seeker
2. Tap "Connect Bank Account"
3. **NOW** it will open Stripe's real onboarding!
4. Fill out the form with test data:
   - Name: Test User
   - DOB: 01/01/1990
   - SSN: 000-00-0000 (Stripe test SSN)
   - Address: 123 Test St, San Francisco, CA 94102
   - Phone: 555-555-5555
   - Bank: Use Stripe test bank routing: 110000000
   - Account: 000123456789
5. Submit!
6. Jobs unlock!

### **Test Payment:**

1. Apply for a job
2. Get hired
3. Complete job
4. Hirer pays with card: `4242 4242 4242 4242`
5. Payment processes through YOUR backend! 💰

---

## 🔍 **Troubleshooting**

### **If deploy fails:**

**Error: "Billing account not configured"**
```
Solution: Go to Firebase Console → Upgrade to Blaze Plan (pay-as-you-go)
Note: Free tier is VERY generous - you won't pay anything for testing
```

**Error: "Permission denied"**
```
Solution: Run `firebase login` again
```

**Error: "Region not supported"**
```
Solution: Functions are set to us-central1 (most common)
```

---

## 📊 **What Gets Deployed:**

### **4 Cloud Functions:**

1. **createPaymentIntent**
   - Creates Stripe payment for completed jobs
   - Handles customer creation
   - Transfers money to workers

2. **createConnectAccount**
   - Creates Stripe Connect account for workers
   - Generates onboarding link
   - Saves account ID to Firestore

3. **connectAccountStatus**
   - Checks if worker's bank is verified
   - Returns account status

4. **stripeWebhook**
   - Listens to Stripe events
   - Updates payment status
   - Updates account status
   - All automatic!

---

## 💰 **Cost:**

**Firebase Functions (Blaze Plan):**
- First 2 million invocations/month: FREE
- After that: $0.40 per million
- For testing: $0.00 (you won't hit limits)

**Your app is TINY compared to free limits!**

---

## 🎉 **After Deployment:**

### **Your App Will:**
- ✅ Use real Stripe Connect onboarding
- ✅ Process real payments (in test mode)
- ✅ Transfer money to workers automatically
- ✅ Track all payments in Firestore
- ✅ Handle webhooks from Stripe

### **You Can:**
- ✅ Test with real Stripe test accounts
- ✅ See money flow in Stripe Dashboard
- ✅ Test the complete user journey
- ✅ Go live when ready!

---

## 🚀 **Quick Commands Summary:**

```bash
# 1. Install Firebase CLI
npm install -g firebase-tools

# 2. Login
firebase login

# 3. Set Stripe keys in dotenv file
cd "/Users/shauryagrover/Downloads/Communally-1 4/firebase-functions"
cp .env.example .env
# then edit .env with your Stripe keys

# 4. Install dependencies
cd firebase-functions
npm install
cd ..

# 5. Deploy!
firebase deploy --only functions
```

**That's it! 5 commands and you're live!** 🎉

---

## 📱 **What Users Will See:**

### **Before (Test Mode):**
- Tap "Connect Bank" → Wait 2 seconds → Success ✅

### **After (Live Mode):**
- Tap "Connect Bank" → Opens Stripe form → Fill out info → Stripe verifies → Success ✅

**Much more professional!**

---

## ⚠️ **Important Notes:**

1. **Stripe Test Mode:** Your functions will use test keys, so all payments are fake
2. **Going Live:** When ready, switch to live Stripe keys in Firebase config
3. **Webhooks:** You'll need to set up webhook endpoint in Stripe Dashboard (I'll show you)
4. **Monitoring:** View function logs in Firebase Console

---

## 🎯 **Next Steps After Deploy:**

1. Test bank connection with real Stripe form
2. Test payment processing
3. View transactions in Stripe Dashboard
4. Set up webhook endpoint (optional for now)
5. Add more features!

---

**Ready? Open Terminal and run those 5 commands!** 🚀

Let me know when you've deployed and I'll help test it!
