#!/bin/bash

echo "🔧 Opening Xcode to fix project settings warning..."
echo ""
echo "📋 Steps to follow:"
echo "   1. Xcode will open"
echo "   2. Click on 'Communally' project (blue icon at top of navigator)"
echo "   3. Look for yellow warning: 'Update to recommended settings'"
echo "   4. Click the warning"
echo "   5. Click 'Perform Changes' button"
echo "   6. Done! ✅"
echo ""
echo "Opening Xcode now..."
sleep 2

open /Users/arnavmehta/Communally-1/Communally.xcodeproj

echo ""
echo "✅ Xcode should be open now!"
echo "Follow the steps above to fix the warning."

