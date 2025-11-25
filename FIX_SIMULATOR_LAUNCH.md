# Fix Simulator Launch Error

## The Error
```
Simulator device failed to launch shaurlabs.Communally.
Code: 3 - No such process
```

This is a common Xcode/Simulator cache issue. Follow these steps in order:

## Solution Steps

### Step 1: Reset the Simulator (Quick Fix)
In Xcode:
1. Stop any running builds (⌘.)
2. **Simulator Menu** → **Device** → **Erase All Content and Settings**
3. Or restart the simulator: **Device** → **Restart**

### Step 2: Clean Build Folder
In Xcode:
```
Product → Clean Build Folder (⌘⇧K)
```

### Step 3: Delete Derived Data
Run this in Terminal:
```bash
rm -rf ~/Library/Developer/Xcode/DerivedData
```

### Step 4: Quit Everything and Restart
```bash
# Quit Xcode
killall Xcode

# Quit Simulator
killall Simulator

# Wait 5 seconds, then reopen
open Communally.xcodeproj
```

### Step 5: Rebuild and Run
In Xcode:
1. Select your simulator (iPhone 15 Pro or similar)
2. **Product** → **Build** (⌘B)
3. **Product** → **Run** (⌘R)

## If That Doesn't Work

### Nuclear Option: Reset Everything
```bash
# Close Xcode and Simulator
killall Xcode
killall Simulator

# Delete all simulator data
xcrun simctl shutdown all
xcrun simctl erase all

# Delete derived data
rm -rf ~/Library/Developer/Xcode/DerivedData

# Delete ModuleCache
rm -rf ~/Library/Developer/Xcode/DerivedData/ModuleCache.noindex

# Reopen and rebuild
open Communally.xcodeproj
```

Then in Xcode:
1. Clean Build Folder (⌘⇧K)
2. Build (⌘B)
3. Run (⌘R)

## Quick Terminal Script

Run this to do everything at once:
```bash
# Stop everything
killall Simulator 2>/dev/null
killall Xcode 2>/dev/null

# Clean caches
rm -rf ~/Library/Developer/Xcode/DerivedData
xcrun simctl shutdown all
xcrun simctl erase all

echo "✅ Cleaned! Now open Xcode and rebuild."
echo "Run: open Communally.xcodeproj"
```

## Alternative: Try a Different Simulator
Sometimes the issue is with a specific simulator device:

1. **Xcode** → **Window** → **Devices and Simulators**
2. Delete the current simulator
3. Add a new one (click **+** button)
4. Select the new simulator and run

## Common Causes
- Corrupted simulator cache
- Old build artifacts
- Xcode cache issues
- Simulator state mismatch
- Previous app installation remnants

## Expected Result
After following these steps, you should see:
```
✅ Build Succeeded
✅ Launching shaurlabs.Communally
✅ App opens in simulator
```

