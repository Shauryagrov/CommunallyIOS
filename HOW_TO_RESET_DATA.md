# 🗑️ How to Delete All Account Data and Start Fresh

## Quick Reset Guide

### ⚡ **Easiest Method** (2 steps)

#### Step 1: Uncomment the Reset Line

Open `Communally/CommunallyApp.swift` and find this (around line 23):

```swift
init() {
    configureFirebase()
    
    // ⚠️ UNCOMMENT BELOW TO RESET ALL DATA (DELETE EVERYTHING) ⚠️
    // resetEverything()  ← REMOVE THE // HERE
}
```

Change it to:

```swift
init() {
    configureFirebase()
    
    // ⚠️ UNCOMMENT BELOW TO RESET ALL DATA (DELETE EVERYTHING) ⚠️
    resetEverything()  // ← UNCOMMENTED!
}
```

#### Step 2: Run the App

1. Build and run (Cmd+R)
2. Wait 2-3 seconds
3. Check console - should see:
   ```
   🗑️ Deleting collection: users...
   🗑️ Deleting collection: opportunities...
   🗑️ Deleting collection: applications...
   ✅ Deleted X documents from users
   ✅ Deleted X documents from opportunities
   🎉 Database is clean!
   ```
4. App will finish deleting

#### Step 3: Comment It Back Out!

**IMPORTANT**: Go back to `CommunallyApp.swift` and comment it out again:

```swift
// resetEverything()  // ← Comment it back!
```

Otherwise it will delete everything every time you launch the app!

#### Step 4: Restart and Test

1. Stop the app (Cmd+.)
2. Build and run again
3. You should see fresh login screen
4. All data is gone - completely clean start! ✨

## What Gets Deleted 🗑️

### From Firebase (Cloud):
- ✅ All user profiles
- ✅ All job postings
- ✅ All applications
- ✅ All messages/conversations
- ✅ All notifications
- ✅ All ratings

### From Local Device:
- ✅ Saved login sessions
- ✅ Cached user data
- ✅ All UserDefaults
- ✅ Migration flags

## Visual Guide 📸

```
Before Reset:
Firebase → users (3 documents)
        → opportunities (6 documents)
        → applications (12 documents)
        → etc.

Local → Saved user sessions
      → Cached data

After Reset:
Firebase → users (empty)
        → opportunities (empty)
        → applications (empty)
        → etc.

Local → Everything cleared
```

## Verification ✓

After reset, you should see:

1. **On App Launch**:
   - Fresh login screen
   - No "Restoring previous session" message
   - Clean slate!

2. **In Firebase Console**:
   - Go to Firestore Database
   - All collections should be empty
   - Or collections deleted entirely

3. **Test Sign In**:
   - Sign in with Google
   - Should go through full onboarding
   - No existing profile found
   - Like a brand new user!

## Alternative: Just Local Reset

If you only want to clear data on **one device** (keep Firebase intact):

### Delete App Method:
1. Long-press app icon on device
2. Delete app
3. Reinstall from Xcode
4. Fresh local data, Firebase data persists

### Code Method:
Just add this to `CommunallyApp.init()`:

```swift
// Clear local data only
UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
AuthenticationManager.shared.signOut()
```

## Safety Tips 🛡️

1. **Always comment out** `resetEverything()` after use
2. **Double-check** you're okay losing all data
3. **Consider exporting** Firebase data first (Firebase Console → Export)
4. **Test with fresh account** after reset

## Troubleshooting 🔧

### "It's not deleting everything":
- Make sure Firebase is configured
- Check console for error messages
- Verify you have internet connection
- Try increasing the delay: `.now() + 2`

### "App crashes":
- Make sure you imported DatabaseCleaner
- Check for syntax errors
- View console logs for details

### "Some collections remain":
- Large collections might need multiple batches
- Firebase has 500 document batch limit
- May need to run reset multiple times for huge datasets

## After Reset Checklist ✅

- [ ] Uncommented `resetEverything()` in CommunallyApp.swift
- [ ] Built and ran app
- [ ] Saw deletion messages in console
- [ ] **Commented out `resetEverything()` again** ⚠️
- [ ] Verified Firebase collections are empty
- [ ] Restarted app - sees fresh login screen
- [ ] Can create new account from scratch

## Ready to Start Fresh! 🎊

Once reset is complete:
1. You'll have a completely clean database
2. No existing accounts
3. No test data
4. Perfect for:
   - Starting fresh
   - Testing the new Firebase sync
   - Trying new features
   - Giving app to testers

---

**Created**: November 30, 2025  
**Warning Level**: ⚠️⚠️⚠️ DESTRUCTIVE - Use with caution!  
**Restore**: Not possible - backup first if needed

