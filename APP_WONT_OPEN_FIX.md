# 🔧 App Won't Open - Quick Fix Guide

## The Problem

The app isn't launching because:
1. ❌ `GoogleService-Info.plist` has **placeholder values** (not real Firebase credentials)
2. ❌ Xcode cache has **permission issues** from sandboxed builds

## The Solution (Choose One)

### 🚀 Quick Fix #1: Automated Clean & Rebuild

Run this script to clean all caches:

```bash
cd /Users/arnavmehta/Communally-1
./clean-and-rebuild.sh
```

This will:
- ✅ Clean Xcode DerivedData
- ✅ Clear Swift package cache
- ✅ Clear Clang module cache
- ✅ Open project in Xcode
- ⏳ Wait for packages to resolve
- 🔨 Build and run

### 🔥 Quick Fix #2: Manual Clean

```bash
# 1. Close Xcode completely

# 2. Clean everything
rm -rf ~/Library/Developer/Xcode/DerivedData/Communally-*
rm -rf ~/Library/Caches/org.swift.swiftpm
rm -rf ~/.cache/clang/ModuleCache

# 3. Open project
cd /Users/arnavmehta/Communally-1
open Communally.xcodeproj

# 4. In Xcode:
#    - Wait for package resolution (1-2 min)
#    - Product → Clean Build Folder (⌘⇧K)
#    - Product → Build (⌘B)
#    - Product → Run (⌘R)
```

### ⚠️ Important: Firebase Setup Required

The app needs a **real** `GoogleService-Info.plist` file:

1. Go to **Firebase Console**: https://console.firebase.google.com
2. Select your project (or create new one)
3. Download `GoogleService-Info.plist`
4. Replace the placeholder file:
   ```bash
   cp ~/Downloads/GoogleService-Info.plist Communally/
   ```

**See `IMPORTANT_FIREBASE_SETUP.md` for detailed Firebase setup instructions.**

## Why This Happened

### Security First! 🔒

When we fixed the API keys issue:
- ✅ Removed real Firebase credentials from git (good for security!)
- ❌ Left placeholder values that don't work (app won't launch)

### Solution:

**Option A**: Use your own Firebase project (recommended)
- Create your own Firebase project
- Download your own `GoogleService-Info.plist`
- Keep it local (already in `.gitignore`)

**Option B**: Get the original Firebase credentials
- If you had working credentials before
- Restore from backup
- Or re-download from Firebase Console

## Step-by-Step Recovery

### 1. Clean Xcode Cache
```bash
./clean-and-rebuild.sh
```

### 2. Add Firebase Credentials

**Quick method:**
```bash
# If you have the original file backed up:
cp /path/to/backup/GoogleService-Info.plist Communally/
```

**Or create new Firebase project:**
See `IMPORTANT_FIREBASE_SETUP.md`

### 3. Build in Xcode

```bash
open Communally.xcodeproj
```

Then in Xcode:
1. ⏳ Wait for "Resolving Package Dependencies" to finish
2. 🧹 Product → Clean Build Folder (⌘⇧K)
3. 🔨 Product → Build (⌘B)
4. ▶️  Product → Run (⌘R)

## Expected Build Time

- **Package Resolution**: 1-2 minutes (first time)
- **Build**: 30-60 seconds
- **Total**: 2-3 minutes

## Troubleshooting

### "Package resolution failed"

```bash
# Nuclear option - delete everything and start fresh
rm -rf ~/Library/Developer/Xcode/DerivedData
rm -rf ~/Library/Caches/org.swift.swiftpm
rm -rf ~/.cache/clang

# Reopen
open Communally.xcodeproj
```

### "Firebase configuration failed"

✅ **Fix**: Add valid `GoogleService-Info.plist` (see `IMPORTANT_FIREBASE_SETUP.md`)

### "Module 'MessageKit' not found"

✅ **Fix**: Clean and rebuild
```bash
./clean-and-rebuild.sh
```

### "Permission denied" errors

✅ **Fix**: Close Xcode, run clean script with sudo if needed:
```bash
sudo rm -rf ~/Library/Developer/Xcode/DerivedData/Communally-*
```

## What Changed

**Before (Insecure):**
- ✅ App launched immediately
- ❌ API keys exposed in git

**Now (Secure):**
- ✅ No API keys in git
- ✅ Secure configuration
- ⚠️  Requires Firebase setup

## Files to Check

1. **Communally/GoogleService-Info.plist**
   - Should have REAL values (not "YOUR_API_KEY_HERE")
   - If placeholder values → app won't launch
   - Solution: Replace with real file from Firebase

2. **.gitignore**
   - ✅ Should contain `GoogleService-Info.plist`
   - Keeps your credentials private

## Quick Verification

Check if Firebase config is valid:

```bash
cat Communally/GoogleService-Info.plist | grep "YOUR_"
```

**If you see "YOUR_API_KEY_HERE"** → Config is placeholder, needs replacement
**If you see no matches** → Config is probably valid!

## Summary

| Issue | Solution | Time |
|-------|----------|------|
| Cache issues | Run `./clean-and-rebuild.sh` | 2 min |
| Missing Firebase | Add `GoogleService-Info.plist` | 5 min |
| Package errors | Clean DerivedData | 2 min |
| Permission errors | Close Xcode, clean, reopen | 3 min |

## Resources

- 📖 `IMPORTANT_FIREBASE_SETUP.md` - Firebase setup guide
- 📖 `BUILD_WITH_MESSAGEKIT.md` - Build troubleshooting
- 📖 `FIREBASE_SETUP.md` - Detailed Firebase instructions
- 🔧 `clean-and-rebuild.sh` - Automated cache cleaning

## Still Stuck?

1. Make sure Xcode is completely closed
2. Run the clean script: `./clean-and-rebuild.sh`
3. Add valid Firebase credentials
4. Wait for package resolution
5. Clean and build in Xcode

**The app WILL work once Firebase is configured properly!** 🚀

---

**TL;DR**: Run `./clean-and-rebuild.sh`, add real `GoogleService-Info.plist` from Firebase Console, then build in Xcode.

