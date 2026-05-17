#!/bin/bash

# Stripe Functions Deployment Script for Communally
# This script helps you deploy the Stripe payment processing functions to Firebase

set -e  # Exit on error

echo "🚀 Communally Stripe Functions Deployment"
echo "=========================================="
echo ""

# Check if Firebase CLI is installed
if ! command -v firebase &> /dev/null; then
    echo "❌ Firebase CLI is not installed"
    echo "   Install it with: npm install -g firebase-tools"
    exit 1
fi

echo "✅ Firebase CLI found"
echo ""

# Navigate to functions directory
cd "$(dirname "$0")/firebase-functions"

# Check if node_modules exists
if [ ! -d "node_modules" ]; then
    echo "📦 Installing dependencies..."
    npm install
    echo "✅ Dependencies installed"
else
    echo "✅ Dependencies already installed"
fi

echo ""
echo "🔑 Checking Stripe Configuration..."
echo ""

# Check if Stripe keys are configured
CONFIG_OUTPUT=$(firebase functions:config:get 2>&1 || true)

if [[ $CONFIG_OUTPUT == *"stripe"* ]]; then
    echo "✅ Stripe configuration found"
    echo "$CONFIG_OUTPUT"
else
    echo "⚠️  Stripe configuration not found"
    echo ""
    echo "You need to set your Stripe keys before deploying:"
    echo ""
    echo "Run these commands:"
    echo "  firebase functions:config:set stripe.secret_key=\"sk_test_YOUR_SECRET_KEY\""
    echo "  firebase functions:config:set stripe.webhook_secret=\"whsec_YOUR_WEBHOOK_SECRET\""
    echo ""
    echo "Get your keys from: https://dashboard.stripe.com/apikeys"
    echo ""
    read -p "Have you already set the Stripe keys? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Please set the Stripe keys first, then run this script again."
        exit 1
    fi
fi

echo ""
echo "🚀 Deploying functions to Firebase..."
echo ""

# Deploy functions
firebase deploy --only functions

echo ""
echo "✅ Deployment complete!"
echo ""
echo "📝 Next Steps:"
echo "1. Copy the function URLs from above"
echo "2. Go to Stripe Dashboard → Webhooks"
echo "3. Add webhook endpoint: [your-stripeWebhook-url]"
echo "4. Select events: payment_intent.succeeded, payment_intent.payment_failed, account.updated"
echo "5. Add the Stripe iOS SDK to your Xcode project"
echo "6. Update StripeConfig.swift with your publishable key"
echo "7. Uncomment Stripe SDK code in StripeService.swift"
echo "8. Set useMockPayments = false in StripeConfig.swift"
echo ""
echo "📖 See STRIPE_SETUP_GUIDE.md for full instructions"
echo ""

