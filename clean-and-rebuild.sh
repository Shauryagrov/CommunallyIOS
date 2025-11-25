#!/bin/bash

# Clean and Rebuild Script for Communally
# Fixes package resolution and build issues

echo "🧹 Cleaning Xcode Build Cache..."
echo ""

# Close Xcode if running
osascript -e 'quit app "Xcode"' 2>/dev/null

echo "1️⃣  Removing DerivedData..."
rm -rf ~/Library/Developer/Xcode/DerivedData/Communally-*

echo "2️⃣  Clearing Swift Package Manager cache..."
rm -rf ~/Library/Caches/org.swift.swiftpm/repositories
rm -rf ~/Library/Caches/org.swift.swiftpm/security

echo "3️⃣  Clearing Clang module cache..."
rm -rf ~/.cache/clang/ModuleCache

echo "4️⃣  Clearing project build folder..."
rm -rf .build
rm -rf Communally.xcodeproj/project.xcworkspace/xcuserdata
rm -rf Communally.xcodeproj/xcuserdata

echo ""
echo "✅ Cache cleaned successfully!"
echo ""
echo "📱 Opening Xcode..."
open Communally.xcodeproj

echo ""
echo "⏳ Wait for package resolution to complete (1-2 minutes)"
echo "📝 Then: Product → Clean Build Folder (⌘⇧K)"
echo "🔨 Then: Product → Build (⌘B)"
echo ""
echo "✨ If you still have issues, check IMPORTANT_FIREBASE_SETUP.md"
echo ""

