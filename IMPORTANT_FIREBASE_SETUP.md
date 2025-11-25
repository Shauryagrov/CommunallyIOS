# ⚠️ IMPORTANT: App Won't Launch Without Firebase Setup

## Why The App Isn't Opening

The app requires a valid `GoogleService-Info.plist` file with **real Firebase credentials** to launch.

Currently, the file has placeholder values for security (no API keys in git).

## Quick Fix (2 minutes)

### Option 1: Use Your Existing Firebase Project

If you had a working Firebase project before:

1. **Download GoogleService-Info.plist** from Firebase Console:
   - Go to: https://console.firebase.google.com
   - Select your project: `communally-a4cb3` (or create new)
   - Click the iOS app
   - Download `GoogleService-Info.plist`

2. **Replace the placeholder file**:
   ```bash
   # Backup current file
   mv Communally/GoogleService-Info.plist Communally/GoogleService-Info-backup.plist
   
   # Copy your downloaded file
   cp ~/Downloads/GoogleService-Info.plist Communally/
   ```

3. **Clean and rebuild**:
   ```bash
   # Clean Xcode cache
   rm -rf ~/Library/Developer/Xcode/DerivedData/Communally-*
   
   # Open in Xcode
   open Communally.xcodeproj
   
   # Then: Product → Clean Build Folder (Cmd+Shift+K)
   # Then: Product → Build (Cmd+B)
   ```

### Option 2: Create New Firebase Project (5 minutes)

1. **Go to Firebase Console**: https://console.firebase.google.com

2. **Create a new project**:
   - Click "Add project"
   - Name: "Communally" (or any name)
   - Enable Google Analytics (optional)

3. **Add iOS app**:
   - Bundle ID: `shaurlabs.Communally`
   - Download `GoogleService-Info.plist`

4. **Enable Authentication**:
   - Go to Authentication → Sign-in method
   - Enable "Google" sign-in provider
   - Add iOS client ID from `GoogleService-Info.plist`

5. **Enable Firestore**:
   - Go to Firestore Database
   - Click "Create database"
   - Choose "Start in test mode"
   - Select a region

6. **Replace the file** (same as Option 1, step 2-3)

## Clean Xcode Cache (If Still Having Issues)

```bash
# Close Xcode first, then run:

# 1. Clean DerivedData
rm -rf ~/Library/Developer/Xcode/DerivedData/Communally-*

# 2. Clean Swift Package Manager cache
rm -rf ~/Library/Caches/org.swift.swiftpm

# 3. Clean Clang module cache
rm -rf ~/Library/Developer/Xcode/DerivedData/ModuleCache.noindex

# 4. Reopen project
open Communally.xcodeproj
```

## What's In The Current File

The placeholder `GoogleService-Info.plist` contains:

```xml
<key>API_KEY</key>
<string>YOUR_API_KEY_HERE</string>

<key>PROJECT_ID</key>
<string>YOUR_PROJECT_ID</string>

<key>GOOGLE_APP_ID</key>
<string>YOUR_GOOGLE_APP_ID</string>
```

This **won't work** - you need real values from Firebase.

## Why We Did This

For security! We removed the actual Firebase credentials so they wouldn't be exposed on GitHub.

- ✅ **Secure**: No API keys in public repository
- ✅ **Safe**: Each developer uses their own Firebase project
- ❌ **Requires setup**: You need to add your own credentials

## Troubleshooting

### "Firebase configure failed"

**Solution**: Add a valid `GoogleService-Info.plist` file

### "Google Sign-In not working"

**Solution**: 
1. Enable Google Sign-In in Firebase Console
2. Make sure `GoogleService-Info.plist` has correct `GOOGLE_APP_ID`

### "Firestore permission denied"

**Solution**:
1. Enable Firestore in Firebase Console
2. Start in "test mode" for development

### "Build failed with package resolution errors"

**Solution**:
```bash
# Clean everything
rm -rf ~/Library/Developer/Xcode/DerivedData
rm -rf ~/Library/Caches/org.swift.swiftpm

# Reopen Xcode
open Communally.xcodeproj

# Let packages resolve (may take 1-2 minutes)
# Then clean and build
```

## Quick Reference

| What You Need | Where To Get It |
|---------------|----------------|
| GoogleService-Info.plist | Firebase Console → Project Settings → iOS App |
| Enable Google Sign-In | Firebase Console → Authentication → Sign-in method |
| Enable Firestore | Firebase Console → Firestore Database |
| Bundle ID | `shaurlabs.Communally` |

## Once Setup Is Complete

After adding your Firebase configuration:

1. ✅ App will launch
2. ✅ Google Sign-In will work
3. ✅ Firestore database will sync
4. ✅ Real-time features will activate
5. ✅ Notifications will function

## Need Help?

See these files:
- `FIREBASE_SETUP.md` - Detailed Firebase setup guide
- `SETUP_GOOGLE_SERVICES.md` - Google services configuration
- `BUILD_WITH_MESSAGEKIT.md` - Build troubleshooting

---

**TL;DR**: Download `GoogleService-Info.plist` from Firebase Console and replace the placeholder file. Then clean and rebuild.
