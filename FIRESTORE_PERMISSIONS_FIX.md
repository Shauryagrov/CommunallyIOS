# Firestore Permissions Issue - CRITICAL FIX NEEDED

## Problem
Jobs are being posted in the app but **Firebase is rejecting them** due to security rules. You're seeing these errors:

```
❌ Error fetching opportunities: Missing or insufficient permissions.
✅ Posted opportunity to Firestore: Cleaning Needed
12.8.0 - [FirebaseFirestore][I-FST000001] Write at opportunities/... failed: Missing or insufficient permissions.
```

## Root Cause
Your Firestore security rules are blocking all reads and writes to the database.

## SOLUTION: Update Firestore Security Rules

### Step 1: Go to Firebase Console
1. Open: https://console.firebase.google.com/project/communally-a4cb3/firestore/rules
2. Sign in with your Google account

### Step 2: Replace Security Rules
Copy and paste these rules (for development):

```javascript
rules_version = '2';

service cloud.firestore {
  match /databases/{database}/documents {
    // Users collection
    match /users/{userId} {
      allow read: if true;
      allow write: if request.auth != null;
    }
    
    // Opportunities collection
    match /opportunities/{opportunityId} {
      allow read: if true;
      allow write: if request.auth != null;
    }
    
    // Applications collection
    match /applications/{applicationId} {
      allow read: if true;
      allow write: if request.auth != null;
    }
    
    // Messages/Conversations
    match /conversations/{conversationId} {
      allow read: if true;
      allow write: if request.auth != null;
      
      match /messages/{messageId} {
        allow read: if true;
        allow write: if request.auth != null;
      }
    }
    
    // Notifications
    match /notifications/{notificationId} {
      allow read: if true;
      allow write: if request.auth != null;
    }
    
    // Ratings
    match /ratings/{ratingId} {
      allow read: if true;
      allow write: if request.auth != null;
    }
    
    // Payments
    match /payments/{paymentId} {
      allow read: if true;
      allow write: if request.auth != null;
    }
    
    // Blocked users
    match /blockedUsers/{blockId} {
      allow read: if true;
      allow write: if request.auth != null;
    }
    
    // User stats
    match /userStats/{userId} {
      allow read: if true;
      allow write: if request.auth != null;
    }
  }
}
```

### Step 3: Publish the Rules
Click the **"Publish"** button in Firebase Console

### Alternative: Open Access for Testing (NOT RECOMMENDED FOR PRODUCTION)
If you just want to test quickly, you can use these rules (WARNING: anyone can read/write your data):

```javascript
rules_version = '2';

service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} {
      allow read, write: if true;
    }
  }
}
```

## Additional Fix Applied: Bundle ID

I also fixed your Bundle ID mismatch:
- **Old**: `com.arnavmehta.communally`
- **New**: `shaurlabs.communally` (matches your Firebase config)

This will eliminate the warning about inconsistent Bundle IDs.

## Testing After Fix

1. **Update Firestore rules** in Firebase Console
2. **Clean and rebuild** the app in Xcode (Cmd + Shift + K, then Cmd + B)
3. **Run the app**
4. **Post a job** - it should now appear immediately!

## Expected Console Output (After Fix)

```
✅ Firebase configured successfully
✅ Firestore listeners initialized
✅ Loaded X opportunities from Firestore  <-- Should show actual count now
✅ Posted opportunity to Firestore: [Job Title]
✅ Loaded X opportunities from Firestore  <-- Job appears immediately
```

## Why This Happened

Firebase Firestore has security rules that control who can read and write data. By default, new projects have strict rules that block everything. You need to configure rules that allow authenticated users to access your app's data.

## Production Security Rules (Use Later)

For production, you'll want more restrictive rules. Here's an example:

```javascript
rules_version = '2';

service cloud.firestore {
  match /databases/{database}/documents {
    // Helper functions
    function isSignedIn() {
      return request.auth != null;
    }
    
    function isOwner(userId) {
      return request.auth.uid == userId;
    }
    
    // Users
    match /users/{userId} {
      allow read: if true;
      allow create: if isSignedIn();
      allow update, delete: if isOwner(userId);
    }
    
    // Opportunities
    match /opportunities/{opportunityId} {
      allow read: if true;
      allow create: if isSignedIn();
      allow update, delete: if isSignedIn() && resource.data.hirerId == request.auth.uid;
    }
    
    // Applications
    match /applications/{applicationId} {
      allow read: if true;
      allow create: if isSignedIn();
      allow update: if isSignedIn() && 
        (resource.data.applicantId == request.auth.uid || 
         resource.data.hirerId == request.auth.uid);
      allow delete: if isSignedIn() && resource.data.applicantId == request.auth.uid;
    }
    
    // Other collections...
  }
}
```

## Next Steps

1. ✅ **Update Firestore rules** (most important!)
2. ✅ Bundle ID already fixed
3. Run the app and test job posting
4. Check console for success messages
5. Verify jobs appear on map and browse tabs

After you update the Firestore rules, the app should work perfectly!
