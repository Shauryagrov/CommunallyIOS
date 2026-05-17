#!/bin/bash

# Parent Email Confirmation Setup Script
# This script helps you set up the parent approval system

echo "🎯 Parent Email Confirmation Setup"
echo "===================================="
echo ""

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if files exist
echo "📁 Checking required files..."
echo ""

files=(
    "public/approve.html"
    "Communally/Services/ParentalApprovalService.swift"
    "Communally/Views/ParentalApprovalPendingView.swift"
    "firebase-functions/index.js"
)

all_exist=true
for file in "${files[@]}"; do
    if [ -f "$file" ]; then
        echo -e "${GREEN}✓${NC} $file"
    else
        echo -e "${RED}✗${NC} $file ${RED}(MISSING)${NC}"
        all_exist=false
    fi
done

echo ""

if [ "$all_exist" = false ]; then
    echo -e "${RED}❌ Some files are missing. Please check your setup.${NC}"
    exit 1
fi

echo -e "${GREEN}✅ All files present!${NC}"
echo ""

# Check Firebase CLI
echo "🔧 Checking Firebase CLI..."
if ! command -v firebase &> /dev/null; then
    echo -e "${RED}❌ Firebase CLI not found${NC}"
    echo "Install it with: npm install -g firebase-tools"
    exit 1
else
    echo -e "${GREEN}✓ Firebase CLI installed${NC}"
fi
echo ""

# Check if logged in to Firebase
echo "🔐 Checking Firebase authentication..."
if firebase projects:list &> /dev/null; then
    echo -e "${GREEN}✓ Logged in to Firebase${NC}"
else
    echo -e "${YELLOW}⚠ Not logged in to Firebase${NC}"
    echo "Run: firebase login"
    exit 1
fi
echo ""

# Prompt for Gmail configuration
echo -e "${BLUE}📧 Gmail Configuration${NC}"
echo "===================================="
echo ""
echo "You need a Gmail account to send parent approval emails."
echo ""
read -p "Enter your Gmail address: " gmail_email
echo ""
echo "You need a Gmail App Password (NOT your regular password)."
echo "Get one at: https://myaccount.google.com/apppasswords"
echo ""
read -sp "Enter your Gmail App Password: " gmail_password
echo ""
echo ""

# Confirm
echo -e "${YELLOW}⚠ About to set Gmail configuration:${NC}"
echo "Email: $gmail_email"
echo "Password: [hidden]"
echo ""
read -p "Is this correct? (y/n): " confirm

if [ "$confirm" != "y" ]; then
    echo "Setup cancelled."
    exit 0
fi

# Set Firebase Functions environment variables in firebase-functions/.env
echo ""
echo "🔧 Writing Gmail credentials to firebase-functions/.env..."

ENV_PATH="firebase-functions/.env"
EXAMPLE_ENV_PATH="firebase-functions/.env.example"

if [ ! -f "$ENV_PATH" ]; then
    if [ -f "$EXAMPLE_ENV_PATH" ]; then
        cp "$EXAMPLE_ENV_PATH" "$ENV_PATH"
    else
        touch "$ENV_PATH"
    fi
fi

# Update existing keys or append if missing
if rg -q "^GMAIL_EMAIL=" "$ENV_PATH"; then
    sed -i '' "s|^GMAIL_EMAIL=.*|GMAIL_EMAIL=$gmail_email|" "$ENV_PATH"
else
    echo "GMAIL_EMAIL=$gmail_email" >> "$ENV_PATH"
fi

if rg -q "^GMAIL_APP_PASSWORD=" "$ENV_PATH"; then
    sed -i '' "s|^GMAIL_APP_PASSWORD=.*|GMAIL_APP_PASSWORD=$gmail_password|" "$ENV_PATH"
else
    echo "GMAIL_APP_PASSWORD=$gmail_password" >> "$ENV_PATH"
fi

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Gmail values written to $ENV_PATH${NC}"
else
    echo -e "${RED}❌ Failed to write $ENV_PATH${NC}"
    exit 1
fi

echo ""

# Ask about deployment
echo -e "${BLUE}🚀 Deployment${NC}"
echo "===================================="
echo ""
read -p "Deploy to Firebase now? (y/n): " deploy_now

if [ "$deploy_now" = "y" ]; then
    echo ""
    echo "Deploying Firebase Functions and Hosting..."
    firebase deploy
    
    if [ $? -eq 0 ]; then
        echo ""
        echo -e "${GREEN}🎉 Deployment successful!${NC}"
    else
        echo ""
        echo -e "${RED}❌ Deployment failed${NC}"
        exit 1
    fi
fi

echo ""
echo "===================================="
echo -e "${GREEN}✅ Setup Complete!${NC}"
echo "===================================="
echo ""
echo "📱 Next steps:"
echo ""
echo "1. Open Xcode"
echo "2. Add these files to the project:"
echo "   • Communally/Services/ParentalApprovalService.swift"
echo "   • Communally/Views/ParentalApprovalPendingView.swift"
echo ""
echo "3. Build and run (⌘+R)"
echo ""
echo "4. Test with a user under 18 years old"
echo ""
echo "📚 For detailed instructions, see:"
echo "   • QUICK_SETUP_PARENT_APPROVAL.md"
echo "   • PARENT_EMAIL_CONFIRMATION.md"
echo ""
