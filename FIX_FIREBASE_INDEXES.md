# Fix Firebase Indexes for Messaging & Notifications

## Problem
The app shows these errors:
```
❌ Error listening to conversations: The query requires an index
❌ Error fetching notifications: The query requires an index
```

## Quick Solution

### Step 1: Go to Firebase Console
1. Open: https://console.firebase.google.com/
2. Select your project: **communally-42179**
3. Click **Firestore Database** in left menu
4. Click **Indexes** tab at the top

### Step 2: Create Conversations Index

Click **"Create Index"** and enter:

**Collection ID**: `conversations`

**Fields to index**:
1. Field: `participantIds`  
   Order: `Arrays` or `Ascending`
   
2. Field: `lastMessageAt`  
   Order: `Descending`
   
3. Field: `__name__`  
   Order: `Descending`

**Query scope**: Collection

Click **Create Index**

### Step 3: Create Notifications Index

Click **"Create Index"** again and enter:

**Collection ID**: `notifications`

**Fields to index**:
1. Field: `userId`  
   Order: `Ascending`
   
2. Field: `createdAt`  
   Order: `Descending`
   
3. Field: `__name__`  
   Order: `Descending`

**Query scope**: Collection

Click **Create Index**

### Step 4: Wait for Index Creation

- Indexes take **5-15 minutes** to build
- You'll see a status indicator in Firebase Console
- Once they say "Enabled" (green checkmark), your messaging will work!

## Alternative: Use the Auto-Generated Links

When you see the error in Xcode console, Firebase provides direct links. They look like:

```
https://console.firebase.google.com/v1/r/project/communally-42179/firestore/indexes?create_composite=...
```

**Just click these links** - they'll automatically fill in all the right fields!

## Why This Happens

Firebase Firestore requires composite indexes when you:
- Query with multiple `where` clauses
- Query with `orderBy` on different fields
- Query arrays with ordering

Your app queries:
1. **Conversations**: Find conversations for a user + order by last message time
2. **Notifications**: Find notifications for a user + order by creation time

These need composite indexes to work efficiently.

## Verification

After creating indexes, restart your app and check:
1. ✅ No more "requires an index" errors
2. ✅ Messaging view loads properly
3. ✅ Notifications view loads properly
4. ✅ You can send and receive messages

## Troubleshooting

**If indexes are created but still not working:**
1. Wait 15-20 minutes (index building can take time)
2. Clear app data and restart
3. Check Firebase Console that indexes show as "Enabled"
4. Make sure you're using the right Firebase project

**If you see "Index creation failed":**
- Check you have enough quota (free tier has limits)
- Verify field names are exact (case-sensitive)
- Try using the auto-generated links from error messages

---

**Time Required**: 5 minutes to create + 10-15 minutes for Firebase to build them  
**Cost**: Free (included in Firebase free tier)  
**One-time Setup**: Yes, once created they persist

