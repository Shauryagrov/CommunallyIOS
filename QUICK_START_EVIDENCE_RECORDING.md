# ⚡️ Evidence Recording - Quick Start (5 Minutes)

## 🎯 What You're Adding

Audio/video/photo recording for dispute protection:
- 🎙️ Record audio during jobs
- 🎥 Record video with audio
- 📸 Take photos for evidence
- 💾 Save locally on device
- 📝 Add notes to recordings

**Perfect for evidence and accountability!**

---

## 📦 Step 1: Add Files (2 min)

### Add to Services Folder:
1. Right-click `Communally/Services` in Xcode
2. "Add Files to 'Communally'..."
3. Select: `EvidenceRecordingService.swift`
4. **UNCHECK** "Copy items if needed"
5. Click "Add"

### Add to Views Folder:
1. Right-click `Communally/Views` in Xcode
2. "Add Files to 'Communally'..."
3. Select: `EvidenceRecordingView.swift`
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

2. **Get accepted for a job**

3. **Look for:** "Evidence" button at bottom
   - Blue button with 🛡️ icon
   - Just above "Share My Location"

4. **Tap to expand:**
   - Shows 3 recording buttons:
   - 🎙️ Audio (blue)
   - 🎥 Video (red)
   - 📸 Photo (green)

5. **Tap "Audio":**
   - Permission requested (first time)
   - Allow microphone
   - Recording starts
   - Timer shows: "0:05"
   - Red indicator pulsing

6. **Speak into mic:**
   - "This is a test recording"

7. **Tap "Stop":**
   - Recording saved
   - Badge shows: "Evidence (1)"

8. **Tap "View Recordings":**
   - List opens
   - Shows your audio recording
   - Duration, file size, timestamp

9. **Tap recording:**
   - Detail view
   - Tap "Play Recording"
   - Hear your test audio ✅

---

## ✅ Verification Checklist

After building:

- [ ] "Evidence" button visible on accepted jobs
- [ ] Tapping button expands panel
- [ ] Three recording type buttons visible
- [ ] Microphone permission requested
- [ ] Recording starts and shows timer
- [ ] Red indicator pulses during recording
- [ ] Stop button saves recording
- [ ] "View Recordings" shows list
- [ ] Can play back audio recordings
- [ ] Can add notes to recordings
- [ ] Can delete recordings

---

## 🎯 What Users Will See

### Collapsed State:
```
┌─────────────────────┐
│  🛡️ Evidence        │ (Blue button)
└─────────────────────┘
```

### Expanded State (Idle):
```
┌──────────────────────────────────┐
│  🛡️ Evidence Recording      ⌄   │
├──────────────────────────────────┤
│  [ 🎙️ Audio ] [ 🎥 Video ] [ 📸 ] │
├──────────────────────────────────┤
│  📁 View Recordings (0)          │
└──────────────────────────────────┘
```

### Recording State:
```
┌──────────────────────────────────┐
│  🔴 Evidence Recording      ⌄   │
├──────────────────────────────────┤
│  🔴 Recording                    │
│  Audio                     2:15  │
│  Size: 1.2 MB                    │
├──────────────────────────────────┤
│  [ ⏸️ Pause ]  [ ⏹️ Stop ]      │
└──────────────────────────────────┘
```

---

## 🎙️ Recording Types

| Type | Icon | Use Case |
|------|------|----------|
| **Audio** | 🎙️ | Voice recording, conversations |
| **Video** | 🎥 | Visual evidence, condition |
| **Photo** | 📸 | Quick snapshots |

---

## ⚙️ Quick Settings

Access via: Recordings List → Gear Icon

**Options:**
- Auto-start recording
- Quality (Low/Standard/High)
- Auto-save to Photos

---

## 📱 Files Added

**Services:**
- `EvidenceRecordingService.swift` (900 lines)

**Views:**
- `EvidenceRecordingView.swift` (650 lines)

**Modified:**
- `OpportunityDetailView.swift` (added panel)
- `Info.plist` (added permissions)

---

## 🔒 Permissions

App will request:

1. **Microphone** (for audio/video)
   - "Record audio during jobs for evidence"

2. **Camera** (for video/photos)
   - "Record video or take photos for evidence"

3. **Photo Library** (to save recordings)
   - "Save evidence recordings to your photo library"

---

## 💡 Use Cases

### Dispute Protection:
- Record agreement discussions
- Document work before/after
- Capture incidents

### Safety:
- Record concerning interactions
- Document property conditions
- Prove timeline of events

### Accountability:
- Show work quality
- Prove completion
- Defend against false claims

---

## 🆘 Troubleshooting

### Button Not Showing?
- Check: Must be accepted for job
- Check: Job must be in progress
- Check: Must be job seeker (not hirer)

### Can't Record?
- Check: Microphone permission granted
- Check: Settings → Privacy → Microphone → Allow
- Check: Phone not in use by other app

### Recording Not Saved?
- Check: Storage space available
- Check: Didn't minimize app during recording
- Check: Tap "Stop" (not just exit)

### Can't Play Audio?
- Check: Volume turned up
- Check: Phone not on silent mode
- Check: File not corrupted

---

## 📊 Statistics

### File Sizes (Approximate):

| Type | Quality | Per Minute |
|------|---------|------------|
| Audio | Low | 0.5 MB |
| Audio | Standard | 1.0 MB |
| Audio | High | 1.5 MB |
| Video | Low | 5 MB |
| Video | Standard | 10 MB |
| Video | High | 15 MB |

### Limits:
- Max duration: 1 hour per recording
- Total recordings: Unlimited
- Concurrent: 1 at a time

---

## 🎯 Integration

### Works With:

✅ **Safety Monitoring** - Record during active jobs  
✅ **Location Sharing** - Pair location with evidence  
✅ **Emergency Alerts** - Document dangerous situations  
✅ **Job Completion** - Attach to completed jobs  

---

## 🏆 What This Adds

After setup:

✅ Evidence recording capability  
✅ Dispute protection  
✅ Audio/video/photo options  
✅ Quality settings  
✅ Note-taking  
✅ Local secure storage  
✅ Professional UI  

---

## 🚀 Next Steps

1. **Build & Test** (do it now!)
2. **Grant permissions** (when prompted)
3. **Test recording** (audio first)
4. **Try video** (if on real device)
5. **Review recordings** (playback test)

---

## 📚 Full Documentation

For complete details:
- **EVIDENCE_RECORDING_SYSTEM.md** - Full guide
- **COMPLETE_SAFETY_SETUP.md** - All safety features

---

**Ready to protect your users? Let's go!** 🚀

*Setup Time: 5 minutes*  
*Files: 2*  
*Lines of Code: 1,550+*
