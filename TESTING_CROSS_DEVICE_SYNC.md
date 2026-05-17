# 📱 Testing Cross-Device Sync

## What You Should See

When you sign in with the same Google account on multiple devices, your profile should automatically sync:

- ✅ Same name
- ✅ Same profile photo
- ✅ Same age
- ✅ Same user type (job seeker/hirer)
- ✅ Same bio/skills
- ✅ All applications
- ✅ All job postings
- ✅ All messages
- ✅ Skip onboarding (go straight to dashboard)

## Test Plan 🧪

### Step 1: Reset Everything (Optional - Fresh Start)

If you want to test from scratch:

1. Uncomment `resetEverything()` in `CommunallyApp.swift`
2. Run app once on any device
3. Wait 3 seconds for deletion to complete
4. Comment out `resetEverything()` again
5. All devices now have clean slate

### Step 2: Create Account on Device 1

**Phone 1 (or Mac Simulator):**

1. Build and run the app
2. Click "Sign in with Google"
3. Choose your Google account (e.g., `yourname@gmail.com`)
4. Complete onboarding:
   - Select "I'm looking for work" or "I'm hiring"
   - Enter age: `18`
   - Take/choose profile photo 📸
   - Enter name: `John Doe`
   - Add skills: `iOS Development, SwiftUI`
   - Accept terms
5. Reach dashboard ✅

**What happens in Firebase:**
```
Firebase → users collection → {
  googleId: "112102740338933641281"
  name: "John Doe"
  profilePhotoURL: "..."
  age: 18
  skills: ["iOS Development", "SwiftUI"]
  hasCompletedOnboarding: true
  userType: "jobSeeker"
}
```

### Step 3: Test on Device 2

**Phone 2 (Different device, same Google account):**

1. Build and run the app on second device
2. Click "Sign in with Google"
3. **Choose SAME Google account** (`yourname@gmail.com`)
4. **Expected Result:**
   - ✅ **Skips onboarding completely**
   - ✅ **Goes straight to dashboard**
   - ✅ **Shows "John Doe" as name**
   - ✅ **Shows same profile photo**
   - ✅ **Has same user type**

**Console should show:**
```
✅ Profile info - Email: yourname@gmail.com, Name: John Doe
🔍 Checking if user exists in database...
✅ Found existing user: John Doe
📱 Restoring account with onboarding status: true
✅ Account restored successfully!
```

### Step 4: Verify Data Sync

**Test that changes sync both ways:**

**On Phone 1:**
1. Post a job or apply to one
2. Check notifications
3. Send a message

**On Phone 2:**
1. Pull to refresh
2. **Should see same applications** ✅
3. **Should see same messages** ✅
4. **Should see same notifications** ✅

## What Gets Synced? ☁️

### User Profile (Firebase → users collection):
- ✅ Name
- ✅ Profile photo
- ✅ Age
- ✅ Email
- ✅ Phone (optional)
- ✅ Bio
- ✅ Skills
- ✅ User type (seeker/hirer)
- ✅ Onboarding completion status
- ✅ Terms acceptance dates

### Application Data (Firebase → other collections):
- ✅ Job postings (`opportunities`)
- ✅ Applications (`applications`)
- ✅ Messages (`conversations`, `messages`)
- ✅ Notifications (`notifications`)
- ✅ Ratings (`ratings`)

## Troubleshooting 🔧

### "It's showing onboarding again on Device 2"

**Possible causes:**
1. Different Google account used
2. Firebase not connected
3. User data didn't save to Firebase

**Check:**
```
1. Look at console logs on Device 1 after onboarding:
   Should see: "💾 UserDatabase: Saved user..."
   
2. Verify in Firebase Console:
   - Go to Firestore Database
   - Check "users" collection
   - Should see your user document

3. On Device 2, check console:
   Should see: "✅ Found existing user: ..."
   NOT: "🆕 New user detected"
```

### "Profile photo is missing on Device 2"

**Issue:** Profile photos are stored as base64 in Firebase. Large images might take a moment to sync.

**Solution:**
- Wait a few seconds after login
- Pull to refresh
- Check internet connection
- Verify photo saved on Device 1 (check Firebase Console)

### "Applications/Messages not showing"

**Issue:** Make sure you're looking at the right tab and that Firebase indexes are created.

**Solution:**
1. Check Firebase Console for index errors
2. Create required indexes (see earlier fix)
3. Wait for indexes to finish building
4. Restart app

### "Onboarding showing even though I completed it"

**Check in code:**
```swift
// In AuthenticationManager, after signing in:
print("🔍 User: \(currentUser?.name)")
print("✅ Onboarding complete: \(currentUser?.hasCompletedOnboarding)")

// Should print:
// 🔍 User: John Doe
// ✅ Onboarding complete: true
```

If `hasCompletedOnboarding = false`, the user wasn't saved properly.

## Expected Console Output 📋

### Device 1 (First Time - New User):
```
✅ Firebase configured successfully
✅ Profile info - Email: yourname@gmail.com, Name: John Doe
🔍 Checking if user exists in database...
🆕 New user detected - creating account
💾 Saved user data for: John Doe
🔧 AuthenticationManager: Created new user = John Doe
🔧 AuthenticationManager: hasCompletedOnboarding = false
[User completes onboarding...]
💾 Onboarding completed for: John Doe
✅ Saved to Firebase
```

### Device 2 (Same Account - Existing User):
```
✅ Firebase configured successfully
✅ Profile info - Email: yourname@gmail.com, Name: John Doe
🔍 Checking if user exists in database...
✅ Found existing user: John Doe
📱 Restoring account with onboarding status: true
✅ Account restored successfully!
🏠 ContentView: Showing DashboardView
```

## Verification Checklist ✓

After testing, verify:

**Device 1:**
- [ ] Created account successfully
- [ ] Completed onboarding
- [ ] Reached dashboard
- [ ] Profile shows correct name/photo
- [ ] Can post jobs/apply to jobs

**Device 2:**
- [ ] Signed in with same Google account
- [ ] **Skipped onboarding** ⚠️ (most important!)
- [ ] Went straight to dashboard
- [ ] Shows **same name** as Device 1
- [ ] Shows **same profile photo** as Device 1
- [ ] Shows **same applications/jobs**

**Firebase Console:**
- [ ] User document exists in "users" collection
- [ ] Document ID matches Google ID
- [ ] `hasCompletedOnboarding` = true
- [ ] Name and photo data present
- [ ] All fields populated correctly

## Success Criteria ✅

You've successfully tested cross-device sync when:

1. ✅ Create account on Device 1
2. ✅ Sign in on Device 2 with same Google account
3. ✅ **Device 2 skips onboarding completely**
4. ✅ Device 2 shows same profile as Device 1
5. ✅ All data syncs between devices
6. ✅ No need to re-enter name, photo, etc.

## Real-World Use Case 🌍

```
Monday (iPhone):
  - Sign in
  - Complete onboarding
  - Apply to 3 jobs
  
Tuesday (iPad):
  - Sign in with same Google account
  - ✅ Goes straight to dashboard
  - ✅ See 3 applications from yesterday
  - Send messages to employers
  
Wednesday (iPhone):
  - Open app
  - ✅ See messages from iPad
  - ✅ Everything synced!
```

---

**Test Status:** Ready to test!  
**Expected Behavior:** Cross-device sync working perfectly  
**Key Feature:** Skip onboarding on second device  
**Created:** November 30, 2025

