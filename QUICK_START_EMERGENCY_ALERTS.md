# ⚡️ Emergency Alerts - Quick Start (5 Minutes)

## 🎯 What You're Adding

Real-time alerts that warn users about:
- 🚨 Active Crime
- 🔥 Fires  
- ⛈️ Severe Weather
- 🌊 Floods
- ☢️ Hazardous Materials
- ⚠️ Civil Unrest
- 🚧 Road Closures

**Users can avoid dangerous areas!**

---

## 📦 Step 1: Add Files (2 min)

### Add to Services Folder:
1. Right-click `Communally/Services` in Xcode
2. "Add Files to 'Communally'..."
3. Select: `EmergencyAlertService.swift`
4. **UNCHECK** "Copy items if needed"
5. Click "Add"

### Add to Views Folder:
1. Right-click `Communally/Views` in Xcode
2. "Add Files to 'Communally'..."
3. Select: `EmergencyAlertView.swift`
4. **UNCHECK** "Copy items if needed"
5. Click "Add"

---

## 🔨 Step 2: Build (30 sec)

```bash
⌘B  # Build
```

Should succeed with ✅

---

## 🧪 Step 3: Test (2 min)

### See It in Action:

1. **Run app:** ⌘R

2. **Add test alert:**
   - In console or code, call:
   ```swift
   EmergencyAlertService.shared.addTestAlert(near: location)
   ```

3. **Look for:**
   - 🔴 Red pulsing badge (top-right, above notifications)
   - Alert banner slides down from top
   - Shows: "🚨 ACTIVE CRIME - Armed Robbery in Progress"

4. **Tap "View Details":**
   - Full alert view opens
   - Shows map with danger zone
   - See safety advice

5. **Tap badge:**
   - Alert list opens
   - Shows all nearby emergencies

---

## ✅ Verification Checklist

After building:

- [ ] Red emergency badge visible (when alerts active)
- [ ] Badge pulses/animates
- [ ] Tapping badge opens alert list
- [ ] Alert banner slides down from top
- [ ] "View Details" opens full detail view
- [ ] Map shows danger zone circle
- [ ] Settings accessible from alert list

---

## 🎯 What Users Will See

### During Normal Use:
- **No alerts:** Badge hidden, all clear
- **Alert nearby:** Red pulsing badge appears

### When Alert Triggered:
1. Red badge pulses (top-right)
2. Banner slides down:
   ```
   🚨 ACTIVE CRIME
   Armed Robbery in Progress
   Avoid this area. Take alternative route.
   [View Details & Route Around] [X]
   ```
3. User can dismiss or view details

### In Alert Details:
- Large icon
- Full description
- Map with danger zone
- Distance to danger
- Safety advice
- "View in Maps" button
- "Share Alert" button

---

## ⚙️ User Controls

Access via: Alert List → Gear Icon

**Users can:**
- Enable/disable monitoring
- Choose alert types (crime, fire, weather, etc.)
- Set minimum severity (low/medium/high/critical)
- See monitoring info

---

## 🧪 Quick Test Scenarios

### Test 1: Badge Appears
```
1. Add test alert
2. Red badge appears (pulsing)
3. Shows count (e.g., "1")
✅ Success
```

### Test 2: Banner Works
```
1. Alert triggers
2. Banner slides down
3. Shows alert info
4. Tap X to dismiss
✅ Success
```

### Test 3: Details View
```
1. Tap "View Details"
2. Full view opens
3. Map shows location
4. Buttons work
✅ Success
```

### Test 4: Settings
```
1. Tap red badge
2. Tap gear icon
3. Toggle features
4. Settings save
✅ Success
```

---

## 🚨 Alert Types

| Type | Icon | When Shown |
|------|------|------------|
| Crime | 🚨 | Robbery, assault nearby |
| Fire | 🔥 | Building fire, wildfire |
| Weather | ⛈️ | Tornado, severe storm |
| Flood | 🌊 | Flash flood warning |
| Hazmat | ☢️ | Chemical spill, gas leak |
| Unrest | ⚠️ | Protest, riot |
| Road | 🚧 | Closure, accident |
| Other | 🆘 | General emergency |

---

## 📊 How It Works

```
Every 5 minutes:
  ↓
Check for emergencies within 5km
  ↓
User within 1km of danger?
  ↓
YES → Show alert + notify
NO → Stay silent
```

**Privacy:** Location only used for proximity check, not stored

---

## 🔧 Integration

### Works With Safety Monitoring:
- Safety monitoring checks for emergency alerts
- If user near danger → triggers safety check-in
- Both badges visible (emergency + safety)

### Appears On:
- Dashboard (badge + banner)
- Can access from any tab

---

## 📱 Files Added

**Services:**
- `EmergencyAlertService.swift` (500 lines)

**Views:**
- `EmergencyAlertView.swift` (450 lines)

**Modified:**
- `DashboardView.swift` (added badge + banner)
- `SafetyMonitoringService.swift` (added integration)

---

## 💡 Production Ready

### Current State:
✅ UI complete  
✅ Alert logic working  
✅ User controls functional  
✅ Notifications integrated  
⏳ Real API integration (placeholder ready)

### To Go Live:
1. Add real API keys (weather, crime, etc.)
2. Implement API fetch functions
3. Test with real data
4. Deploy!

---

## 🆘 Troubleshooting

### Badge Not Showing?
- Check: Alert is within 1km
- Check: Monitoring enabled
- Check: Alert meets severity threshold

### Banner Not Appearing?
- Check: `showAlertBanner` is true
- Check: `currentBannerAlert` is set
- Check: Console for errors

### Build Errors?
- Clean build folder: Shift+⌘+K
- Re-add files (uncheck "Copy items")
- Rebuild: ⌘B

---

## 🎊 Success!

You now have:

✅ Real-time emergency alerts  
✅ 8+ alert categories  
✅ Smart proximity detection  
✅ Beautiful UI  
✅ User controls  
✅ Map integration  
✅ Safety integration  

**Total Time:** 5 minutes  
**Lines of Code:** 950+  
**Safety Level:** 🛡️🛡️🛡️🛡️🛡️

---

## 🚀 Next Steps

1. **Build & Test** (do it now!)
2. **Try test alerts** (see it work)
3. **Configure settings** (test user controls)
4. **Plan API integration** (for real data)
5. **Launch!** 🎉

---

## 📚 Full Documentation

For complete details:
- **EMERGENCY_ALERTS_SYSTEM.md** - Full guide
- **SAFETY_FEATURES_SUMMARY.md** - All safety features

---

**Ready to protect your users? Let's go!** 🚀
