# Project Unmute

**Real-time ASL (American Sign Language) translation app** that bridges communication between deaf/hard-of-hearing and hearing individuals using Ray-Ban Meta smart glasses.

![iOS 17+](https://img.shields.io/badge/iOS-17.0+-blue.svg)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange.svg)
![Meta Glasses](https://img.shields.io/badge/Meta-Ray--Ban%20Glasses-green.svg)
![License](https://img.shields.io/badge/License-MIT-yellow.svg)

##  Features

###  Speech → ASL Mode
- **Real-time speech recognition** via iPhone/Meta Glasses microphone
- **Automatic avatar video playback** showing ASL signs for spoken words
- **Live transcription display** on screen

###  ASL → Text Mode  
- **Live video streaming** from Ray-Ban Meta glasses camera
- **Hand gesture detection** using MediaPipe Vision
- **ASL sign recognition** with sentence building
- **Text-to-speech output** through Meta Glasses speakers

###  Camera Sources
- **Ray-Ban Meta Glasses** - First-person POV for ASL detection
- **iPhone Front Camera** - For testing and demos
- **iPhone Back Camera** - Alternative input

##  Demo

| Speech → ASL | ASL → Text |
|:------------:|:----------:|
| Speak naturally, see ASL avatar | Sign in ASL, see text translation |

##  Architecture

```
ProjectUnmute/
├── ProjectUnmute ProjectUnmute/
│   ├── ProjectUnmuteApp.swift      # SwiftUI @main entry
│   ├── ContentView.swift           # Main UI with mode switching
│   ├── SceneDelegate.swift         # Scene lifecycle + URL handling
│   ├── AppDelegate.swift           # SDK configuration
│   │
│   ├── # Meta Glasses Integration
│   ├── MWDATStubs.swift            # Meta Wearables SDK wrapper
│   ├── CameraManager.swift         # Multi-source camera management
│   │
│   ├── # ASL Detection
│   ├── ASLDetectionView.swift      # ASL → Text UI
│   ├── ASLSignDetector.swift       # Sign detection logic
│   ├── HandGestureProcessor.swift  # MediaPipe gesture recognition
│   │
│   ├── # Speech Recognition
│   ├── SpeechRecognizer.swift      # Speech-to-text engine
│   ├── AvatarVideoPlayer.swift     # ASL avatar video player
│   └── DemoMode.swift              # Demo/testing controls
│
├── Podfile                         # CocoaPods dependencies
├── gesture_recognizer.task         # MediaPipe ML model
└── README.md
```

##  Requirements

| Component | Requirement |
|-----------|-------------|
| **Xcode** | 15.0+ |
| **iOS** | 17.0+ |
| **Swift** | 5.9+ |
| **Device** | iPhone (for Meta Glasses pairing) |
| **Glasses** | Ray-Ban Meta (Gen 2 recommended) |
| **CocoaPods** | 1.14+ |

##  Quick Start

### 1. Clone Repository
```bash
git clone https://github.com/azaranwala/ProjectUnmute.git
cd ProjectUnmute
```

### 2. Install Dependencies
```bash
# Install CocoaPods if needed
sudo gem install cocoapods

# Install pods
pod install
```

### 3. Open in Xcode
```bash
open "ProjectUnmute ProjectUnmute.xcworkspace"
```

### 4. Add Meta Wearables SDK (SPM)
1. In Xcode: **File → Add Package Dependencies...**
2. Enter URL: `https://github.com/facebook/meta-wearables-dat-ios`
3. Select version and add to target

### 5. Configure Meta Developer App
1. Create app at [Meta Developer Portal](https://developers.facebook.com/)
2. Update `Info.plist` with your `MetaAppID`
3. Configure URL schemes for OAuth callback

### 6. Build & Run
- Select your iPhone as target
- Build and run (`Cmd+R`)
- Pair Meta Glasses via Meta AI app

##  Configuration

### Info.plist Keys
```xml
<!-- Meta Wearables SDK -->
<key>MWDAT</key>
<dict>
    <key>MetaAppID</key>
    <string>YOUR_META_APP_ID</string>
    <key>AppLinkURLScheme</key>
    <string>projectunmute://</string>
</dict>

<!-- Permissions -->
<key>NSCameraUsageDescription</key>
<string>Camera access for hand tracking</string>
<key>NSMicrophoneUsageDescription</key>
<string>Microphone for speech recognition</string>
<key>NSSpeechRecognitionUsageDescription</key>
<string>Speech recognition for ASL translation</string>
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Bluetooth to connect Meta Glasses</string>
```

##  Meta Glasses Setup

### First-Time Pairing
1. Install **Meta AI** app on iPhone
2. Pair Ray-Ban Meta glasses via Bluetooth
3. Enable **Developer Mode** in Meta AI settings
4. Launch ProjectUnmute
5. Tap **"Meta Glasses"** camera source
6. Authorize in Meta AI when prompted
7. Return to ProjectUnmute - streaming begins!

### Troubleshooting
| Issue | Solution |
|-------|----------|
| "No devices found" | Ensure glasses paired in Meta AI app |
| "Camera permission error" | Grant camera in Meta AI → Connected Apps |
| "Registration failed" | Update Meta AI app to latest version |
| Opens Messenger instead | Fixed in v1.0 - use latest code |

##  Hand Gesture Recognition

### Supported Gestures (MediaPipe)
| Gesture | Icon | Description |
|---------|------|-------------|
| `Open_Palm` | ✋ | Open hand facing camera |
| `Closed_Fist` | ✊ | Closed fist |
| `Thumb_Up` | 👍 | Thumbs up |
| `Thumb_Down` | 👎 | Thumbs down |
| `Victory` | ✌️ | Peace sign |
| `Pointing_Up` | ☝️ | Index finger up |
| `ILoveYou` | 🤟 | ASL "I love you" |

### Custom Gesture Triggers
| Gesture | Hold Time | Action |
|---------|-----------|--------|
| `POINTING` | 2 sec | Speaks "Hello" |
| `THANK_YOU` | 2 sec | Speaks "Thank you" |

##  Avatar Video System

### Adding New Signs
1. Create video of ASL sign (MP4/MOV/M4V)
2. Name file after the word: `hello.mp4`, `thank_you.mp4`
3. Add to `Resources/AvatarAssets/`
4. App auto-detects and maps to spoken words

### Current Mappings
| Spoken Word | Video File |
|-------------|------------|
| "Hello" | `hello.mp4` |
| "Thank you" | `thank_you.mp4` |
| "Goodbye" | `goodbye.mp4` |
| "Help" | `help.mp4` |
| "Yes" / "No" | `yes.mp4` / `no.mp4` |

##  Demo Mode

For testing without Meta Glasses:
1. Switch to **iPhone Front Camera**
2. Use **Demo Mode** buttons to simulate ASL signs
3. Test sentence building and speech output

##  Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| [Meta Wearables SDK](https://github.com/facebook/meta-wearables-dat-ios) | Latest | Glasses streaming |
| [MediaPipeTasksVision](https://developers.google.com/mediapipe) | 0.10.x | Hand/gesture detection |
| Apple Speech Framework | Built-in | Speech recognition |
| AVFoundation | Built-in | Video/audio playback |

##  Roadmap

- [x] Meta Glasses video streaming
- [x] Speech → ASL avatar translation  
- [x] ASL → Text with gesture detection
- [x] Multi-camera source support
- [ ] Expanded ASL vocabulary (100+ signs)
- [ ] Custom ML model for ASL detection
- [ ] Real-time ASL-to-speech synthesis
- [ ] Offline mode support
- [ ] Apple Watch companion app

##  Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open Pull Request

##  License

This project is licensed under the MIT License - see [LICENSE](LICENSE) file.

##  Acknowledgments

- [Meta Wearables SDK](https://wearables.developer.meta.com/) for glasses integration
- [Google MediaPipe](https://developers.google.com/mediapipe) for hand tracking
- ASL community for inspiration and guidance

##  Contact

**Al Aqmar Zaranwala** - [@azaranwala](https://github.com/azaranwala)

Project Link: [https://github.com/azaranwala/ProjectUnmute](https://github.com/azaranwala/ProjectUnmute)

---

<p align="center">Made for accessibility</p>
