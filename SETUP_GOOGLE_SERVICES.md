# 🔑 Google Services Setup

## ⚠️ SECURITY NOTICE

**Your API keys should NEVER be committed to Git!**

The `GoogleService-Info.plist` file has been removed from Git tracking and added to `.gitignore`.

## 📝 Setup Instructions

### 1. Get Your Firebase Configuration

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project: **communally-a4cb3**
3. Go to **Project Settings** (gear icon)
4. Scroll down to **Your apps** section
5. Click on your iOS app
6. Click **Download GoogleService-Info.plist**

### 2. Add to Your Project

1. Copy the downloaded `GoogleService-Info.plist` file
2. Place it in: `/Users/arnavmehta/Communally-1/Communally/`
3. Make sure it's named exactly: `GoogleService-Info.plist`

### 3. Verify Setup

The file should contain:
- `API_KEY` - Your Firebase API key
- `GCM_SENDER_ID` - For push notifications
- `PROJECT_ID` - Your Firebase project ID
- `GOOGLE_APP_ID` - Your Google app ID
- `STORAGE_BUCKET` - Your Firebase storage bucket

### 4. Template File

A template file is provided at:
```
Communally/GoogleService-Info-TEMPLATE.plist
```

You can copy this and fill in your actual values.

## 🔒 Security Best Practices

✅ **DO:**
- Keep `GoogleService-Info.plist` in your local project only
- Add it to `.gitignore` (already done)
- Download fresh from Firebase Console
- Share the template file instead

❌ **DON'T:**
- Commit API keys to Git
- Share API keys in screenshots or messages
- Push API keys to GitHub/public repos

## 🚨 If API Keys Were Exposed

If your API keys were accidentally pushed to Git:

1. **Regenerate keys immediately** in Firebase Console
2. **Remove from Git history** using:
   ```bash
   git filter-branch --force --index-filter \
     'git rm --cached --ignore-unmatch Communally/GoogleService-Info.plist' \
     --prune-empty --tag-name-filter cat -- --all
   ```
3. **Force push** to remote (if applicable)
4. **Download new config** from Firebase

---

**Need Help?** Check [Firebase Documentation](https://firebase.google.com/docs/ios/setup)

