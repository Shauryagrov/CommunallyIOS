# How to Reset Database and Start Fresh

## ⚠️ WARNING
This will delete **ALL** data from both your device and Firebase:
- All user accounts
- All job postings
- All applications
- All messages
- All notifications
- All ratings

**This cannot be undone!**

## Method 1: Using Code (Recommended)

### Step 1: Add the Reset Code

Open `CommunallyApp.swift` and add this function:

```swift
// Add this inside the CommunallyApp struct
private func resetEverything() {
    DatabaseCleaner.shared.deleteEverything { success in
        if success {
            print("🎉 Database reset complete! Restart the app.")
            exit(0)
        }
    }
}
```

### Step 2: Trigger the Reset

Add this to the `init()` function:

```swift
init() {
    // Configure Firebase with error handling
    configureFirebase()
    
    // UNCOMMENT THIS LINE TO RESET EVERYTHING:
    // resetEverything()
}
```

### Step 3: Run the App
1. Uncomment the `resetEverything()` line
2. Build and run (Cmd+R)
3. App will delete everything and exit
4. Check console for confirmation messages
5. **Comment out the line again** before next run!

## Method 2: Quick Code Snippet

Add this **temporary** code anywhere in your app that runs on launch:

```swift
// Add to CommunallyApp.init() - DELETE AFTER USE!
DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
    DatabaseCleaner.shared.deleteEverything { success in
        print(success ? "✅ All data deleted!" : "⚠️ Some errors occurred")
    }
}
```

## Method 3: Firebase Console (Manual)

### For Cloud Data:
1. Go to https://console.firebase.google.com/
2. Select project: `communally-42179`
3. Click "Firestore Database"
4. Delete these collections manually:
   - `users` (all user profiles)
   - `opportunities` (all job postings)
   - `applications` (all applications)
   - `conversations` (all chats)
   - `messages` (all messages)
   - `notifications` (all notifications)
   - `ratings` (all ratings)

### For Local Data:
On **each device**, run this in Xcode debugger console (Cmd+Shift+Y):

```swift
UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
```

Or simply **delete the app** and reinstall it.

## Method 4: Script Approach (Easiest)

I'll create a simple script for you:

```bash
# Coming next...
```

## What Gets Deleted 🗑️

### From Firebase:
- ✅ All user profiles (names, photos, etc.)
- ✅ All job postings
- ✅ All job applications
- ✅ All messages and conversations
- ✅ All notifications
- ✅ All ratings and reviews

### From Local Device:
- ✅ Saved user sessions
- ✅ Local user database cache
- ✅ Migration flags
- ✅ All UserDefaults data
- ✅ Authentication tokens

## After Reset 🔄

When you restart the app:
1. ✨ Fresh login screen
2. No previous accounts
3. Empty Firebase database
4. Like a brand new installation
5. Ready to create new accounts!

## Verification ✓

After reset, check:
- [ ] Login screen shows (not logged in)
- [ ] Firebase Console shows empty collections
- [ ] No user data in local storage
- [ ] Can sign in as new user
- [ ] Onboarding shows for new user
- [ ] Everything starts from scratch

## Restore Point 💾

**Important**: There is **NO UNDO** for this operation!

If you want to keep a backup:
1. Go to Firebase Console
2. Export your Firestore data first
3. Download a backup
4. Then proceed with reset

---

**Use with caution!** This is a destructive operation.
**Created**: November 30, 2025

