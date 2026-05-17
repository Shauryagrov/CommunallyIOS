# ⚡️ Quick Setup - Parent Email Confirmation

## 🎯 3-Minute Setup Guide

Follow these exact steps to enable parent email confirmation:

---

## Step 1: Add Files to Xcode (2 minutes)

### Open Xcode and add the new Swift files:

1. **In Xcode**, find the `Services` folder in the left sidebar
2. **Right-click** on `Services` → **"Add Files to Communally..."**
3. Navigate to your project folder and select:
   ```
   Communally/Services/ParentalApprovalService.swift
   ```
4. **IMPORTANT**: Uncheck "Copy items if needed"
5. Click **"Add"**

6. **Find the `Views` folder** in the left sidebar
7. **Right-click** on `Views` → **"Add Files to Communally..."**
8. Select:
   ```
   Communally/Views/ParentalApprovalPendingView.swift
   ```
9. **IMPORTANT**: Uncheck "Copy items if needed"
10. Click **"Add"**

11. **Build the project** (⌘+B) - should compile successfully

---

## Step 2: Configure Gmail (1 minute)

### Get Gmail App Password:

1. Go to https://myaccount.google.com/security
2. Click **"2-Step Verification"** → Enable if not already
3. Scroll down → Click **"App passwords"**
4. Create new app password:
   - App: **Mail**
   - Device: **Other (Custom name)** → Type "Communally"
5. Click **"Generate"** → Copy the 16-character password

### Set Firebase Config:

Open Terminal in your project folder and run:

```bash
firebase functions:config:set gmail.email="your-email@gmail.com"
firebase functions:config:set gmail.password="abcd-efgh-ijkl-mnop"
```

Replace with your actual Gmail and the app password you just generated.

---

## Step 3: Deploy to Firebase (30 seconds)

```bash
firebase deploy
```

That's it! ✨

---

## 🧪 Quick Test

1. **Run the app** in simulator
2. **Sign in** with Google
3. **During onboarding:**
   - Set age to **17** (or any age under 18)
   - Enter your email as parent email
4. **Complete onboarding** → See "Waiting for Approval" screen
5. **Check your email** → Click approval link
6. **Back in app** → Tap "Check Again" → Access granted!

---

## ✅ What You Get

### For Teen Users (Under 18):
- ⏸ Blocked from app until parent approves
- 📧 Beautiful waiting screen showing parent's email
- 🔄 Auto-refresh every 30 seconds
- ✉️ Can resend approval email

### For Adult Users (18+):
- ✨ No approval needed
- 🚀 Goes directly to dashboard

### For Parents:
- 📬 Professional email with clear approval button
- 🎨 Branded web page for one-click approval
- ✅ Instant activation for their child

---

## 🎯 That's All!

The system is now fully operational. Every minor user will need parent approval before using the app.

**Pro Tip:** For testing, use your own email as the "parent email" so you can quickly approve test accounts.

---

## 📚 Need More Details?

See the full guide: **PARENT_EMAIL_CONFIRMATION.md**
