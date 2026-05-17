# ⚡ Test Location Privacy Feature - Quick Guide

## 🎯 **3-Minute Test**

---

## **Setup (30 seconds)**

1. **Build & Run** the app (Cmd+R)
2. Have **2 test accounts ready:**
   - Account A = Job Hirer
   - Account B = Job Seeker

---

## **Test 1: Job Seeker Sees General Location (1 min)**

### **Steps:**

1. **Sign in as Job Hirer (Account A)**
2. **Post a job:**
   - Title: "Test Privacy Job"
   - Location: "123 Main Street, San Francisco, CA"
   - Pay: $50
   - Post it!

3. **Sign out, sign in as Job Seeker (Account B)**
4. **Browse opportunities:**
   - Find the "Test Privacy Job"
   - ✅ **Check:** Location shows "San Francisco, CA" (NOT full address)
   - ✅ **Check:** Icon is general location circle (not pin)

5. **Tap on the job to view details:**
   - ✅ **Check:** Map shows a circle/area (not exact pin)
   - ✅ **Check:** See green info badge: "Exact location disclosed after acceptance"
   - ✅ **Check:** Location text shows "San Francisco, CA"

---

## **Test 2: After Acceptance, Location Unlocks (1 min)**

### **Steps:**

1. **Still as Job Seeker:**
   - Apply to the "Test Privacy Job"

2. **Sign out, sign in as Job Hirer (Account A)**
   - Go to "Opportunities" tab
   - View the "Test Privacy Job"
   - See applicants
   - **Accept the job seeker**

3. **Sign out, sign in as Job Seeker (Account B)**
4. **Go to "My Applications" tab:**
   - Find the accepted job
   - ✅ **Check:** Location now shows "123 Main Street, San Francisco, CA" (full address!)
   - ✅ **Check:** Icon changed to map pin

5. **Tap to view job details:**
   - ✅ **Check:** Map shows exact pin location
   - ✅ **Check:** No privacy notice anymore
   - ✅ **Check:** Full address visible

---

## **Test 3: Map Shows Approximate Locations (30 sec)**

### **Steps:**

1. **As Job Seeker, go to "Map" tab:**
   - ✅ **Check:** Opportunity pins are NOT at exact addresses
   - ✅ **Check:** They're offset by ~1-2km
   - ✅ **Check:** General area is correct, but not precise

2. **Tap a pin to see popup:**
   - ✅ **Check:** Shows "City, State" only
   - ✅ **Check:** Does NOT show street address

---

## ✅ **Success Checklist**

### **Before Acceptance:**
- [ ] Job cards show "City, State" only
- [ ] Location icon is circle (not pin)
- [ ] Map shows approximate area/circle
- [ ] Detail view has privacy notice
- [ ] No street address visible anywhere

### **After Acceptance:**
- [ ] Job shows full street address
- [ ] Location icon changes to map pin
- [ ] Map shows exact marker
- [ ] No privacy notice
- [ ] "My Applications" shows exact location

### **Job Hirer (Always):**
- [ ] Can see full address on own jobs
- [ ] Map shows exact pins for own jobs
- [ ] No location restrictions

---

## 🔍 **What to Look For**

### **Visual Differences:**

**General Location (Hidden):**
```
🌍 San Francisco, CA
[Map with circle overlay]
ℹ️ Exact location disclosed after acceptance
```

**Exact Location (Visible):**
```
📍 123 Main Street, San Francisco, CA
[Map with precise pin]
(No privacy notice)
```

---

## 🐛 **Common Issues & Fixes**

### **"I still see exact address as job seeker"**
- Make sure you're NOT the job hirer (owner)
- Make sure you're NOT accepted yet
- Try refreshing the view (pull down)

### **"Map doesn't show anything"**
- Check location permissions
- Make sure opportunity has valid coordinates
- Try zooming out on map

### **"Location doesn't unlock after acceptance"**
- Close and reopen the detail view
- Check "My Applications" tab instead
- Make sure acceptance went through (check as hirer)

---

## 📱 **Quick Visual Test**

**Browse as Job Seeker → Should see:**
```
┌─────────────────────────────┐
│ 👤 Job Title               │
│ 🌍 San Francisco, CA       │
│ 💰 $50                     │
└─────────────────────────────┘
```

**After Acceptance → Should see:**
```
┌─────────────────────────────┐
│ ✅ ACCEPTED                │
│ 👤 Job Title               │
│ 📍 123 Main St, SF, CA     │
│ 💰 $50                     │
└─────────────────────────────┘
```

---

## 🎉 **That's It!**

**If all checks pass, your location privacy feature is working perfectly!** 🔒✨

The feature protects job hirers' addresses while still showing job seekers the general area, then automatically reveals the exact location once they're officially hired.

**This is a professional, privacy-first approach!** 💪
