# Meta Glasses Integration Progress

## Status: ⏳ Waiting for Meta SDK Support

Last Updated: December 22, 2025

---

## ✅ Completed Steps

### 1. Meta Wearables SDK Installation
- Added via Swift Package Manager
- Repository: https://github.com/facebook/meta-wearables-dat-ios
- Modules: `MWDATCore`, `MWDATCamera`

### 2. Info.plist Configuration
```xml
<key>MWDAT</key>
<dict>
    <key>AppLinkURLScheme</key>
    <string>fb1380747310272637</string>
    <key>MetaAppID</key>
    <string>1380747310272637</string>
    <key>Analytics</key>
    <dict>
        <key>OptOut</key>
        <false/>
    </dict>
</dict>
```

### 3. URL Schemes
- `fb1380747310272637` (fb + MetaAppID)
- `projectunmute` (backup)

### 4. Privacy Permissions
- `NSCameraUsageDescription` ✅
- `NSBluetoothAlwaysUsageDescription` ✅
- `NSBluetoothPeripheralUsageDescription` ✅

### 5. Meta Developer Portal
- Project: ProjectUnmute
- Bundle ID: `com.ProjectUnmute.ProjectUnmute-ProjectUnmute`
- MetaAppID: `1380747310272637`
- Release Channel: Created
- Tester: Added

### 6. App Code
- `MWDATStubs.swift` - Meta Glasses camera manager
- `AppDelegate.swift` - URL callback handling
- `ProjectUnmuteApp.swift` - onOpenURL handler
- `ContentView.swift` - Camera source picker with Meta Glasses option

---

## ❌ Current Blocker

### Error
```
Registration state: RegistrationState(rawValue: 0)  // unavailable
Registration error: RegistrationError(rawValue: 5)  // metaAINotInstalled
```

### Cause
The Meta AI app on the device doesn't have MWDAT SDK integration built in yet. The SDK was released December 4, 2025, and Meta is gradually rolling out support.

### Related GitHub Issue
- **Issue #41**: Registration callback not received after clicking Connect in Meta AI
- URL: https://github.com/facebook/meta-wearables-dat-ios/issues/41
- Status: Open (as of Dec 22, 2025)

---

## 🔧 When Meta Fixes This

### Testing Steps
1. Update Meta AI app from App Store
2. Open ProjectUnmute app
3. Select "Meta Glasses" camera source
4. Tap "Authorize in Meta AI"
5. Approve in Meta AI when prompted
6. Return to ProjectUnmute
7. Video should start streaming

### Expected Console Output
```
📋 Registration state: RegistrationState(rawValue: 3)  // registered
📱 Available devices: [device_id]
🎬 Frame received!
🖼️ UIImage created: (width, height)
✅ Frame displayed, FPS: 30
```

---

## 📁 Key Files

| File | Purpose |
|------|---------|
| `MWDATStubs.swift` | Meta Glasses camera manager with SDK integration |
| `CameraManager.swift` | Camera source switching logic |
| `ContentView.swift` | UI with camera source picker |
| `AppDelegate.swift` | URL callback handling |
| `ProjectUnmuteApp.swift` | SwiftUI app with onOpenURL |
| `Info.plist` | SDK configuration and permissions |

---

## 🔗 Resources

- Meta Wearables Developer Center: https://wearables.developer.meta.com/
- SDK Documentation: https://wearables.developer.meta.com/docs/develop/
- iOS SDK GitHub: https://github.com/facebook/meta-wearables-dat-ios
- SDK Issues: https://github.com/facebook/meta-wearables-dat-ios/issues

---

## 📱 Workaround

While waiting for Meta SDK support, use **iPhone Camera** for ASL detection testing:
1. In the app, tap "iPhone Front" or "iPhone Back"
2. The camera feed will work immediately
3. ASL hand detection will function normally
