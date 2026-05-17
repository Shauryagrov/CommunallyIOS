#!/bin/bash

echo "🎯 Communally Stripe Setup Script"
echo "=================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if Firebase CLI is installed
echo "1️⃣ Checking Firebase CLI..."
if ! command -v firebase &> /dev/null; then
    echo -e "${RED}❌ Firebase CLI not found${NC}"
    echo "Installing Firebase CLI..."
    npm install -g firebase-tools
else
    echo -e "${GREEN}✅ Firebase CLI is installed${NC}"
fi

echo ""
echo "2️⃣ Setting up Firebase Functions..."
cd firebase-functions

# Check if node_modules exists
if [ ! -d "node_modules" ]; then
    echo "Installing dependencies..."
    npm install
else
    echo -e "${GREEN}✅ Dependencies already installed${NC}"
fi

cd ..

echo ""
echo -e "${YELLOW}=====================================${NC}"
echo -e "${YELLOW}⚠️  MANUAL STEPS REQUIRED${NC}"
echo -e "${YELLOW}=====================================${NC}"
echo ""
echo "To complete Stripe setup, you need to:"
echo ""
echo "📱 Step 1: Add Stripe SDK to Xcode"
echo "   1. Open Communally.xcodeproj in Xcode"
echo "   2. Go to File → Add Package Dependencies"
echo "   3. Enter: https://github.com/stripe/stripe-ios"
echo "   4. Select version 24.3.0 or later"
echo "   5. Add these libraries:"
echo "      - StripePaymentSheet"
echo "      - StripeCore"
echo "      - StripeUICore"
echo ""
echo "🔑 Step 2: Configure Stripe Keys"
echo "   1. Log in to https://dashboard.stripe.com"
echo "   2. Go to Developers → API keys"
echo "   3. Copy your Publishable key (starts with pk_test_)"
echo "   4. Edit Communally/Services/StripeConfig.swift"
echo "   5. Replace the publishableKey with your key"
echo ""
echo "🔥 Step 3: Deploy Firebase Functions"
echo "   1. Get your Stripe Secret key from dashboard"
echo "   2. Run: firebase functions:config:set stripe.secret_key=\"sk_test_YOUR_KEY\""
echo "   3. Get Firebase project ID: firebase projects:list"
echo "   4. Deploy: firebase deploy --only functions"
echo "   5. Update StripeConfig.swift with your Functions URL"
echo ""
echo "📖 For detailed instructions, see: STRIPE_SETUP_GUIDE.md"
echo ""
echo -e "${GREEN}✨ Ready to set up Stripe payments!${NC}"
