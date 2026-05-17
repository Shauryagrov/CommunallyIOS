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

# Check if Stripe keys are configured in dotenv file (functions.config is deprecated)
ENV_FILE=".env"
if [ ! -f "$ENV_FILE" ]; then
    echo "⚠️  Missing firebase-functions/.env"
    echo ""
    echo "Create it from the template and set your Stripe keys:"
    echo "  cp .env.example .env"
    echo "  # then edit .env and set STRIPE_SECRET_KEY and STRIPE_WEBHOOK_SECRET"
    echo ""
    echo "Template available at: firebase-functions/.env.example"
    exit 1
fi

if rg -q "^STRIPE_SECRET_KEY=sk_(test|live)_" "$ENV_FILE" && rg -q "^STRIPE_WEBHOOK_SECRET=whsec_" "$ENV_FILE"; then
    echo "✅ Stripe environment variables found in .env"
else
    echo "⚠️  Stripe keys are missing or incomplete in firebase-functions/.env"
    echo ""
    echo "Expected keys:"
    echo "  STRIPE_SECRET_KEY=sk_test_..."
    echo "  STRIPE_WEBHOOK_SECRET=whsec_..."
    echo ""
    exit 1
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

