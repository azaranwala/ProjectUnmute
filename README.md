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
├── ProjectUnmute ProjectUnmute/    # iOS App
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
│   ├── ASLSignDetector.swift       # Sign detection orchestration
│   ├── ASLModelClassifier.swift    # ML model for static signs (centroid classifier)
│   ├── MotionSignDetector.swift    # Motion tracking for dynamic signs
│   ├── HandGestureProcessor.swift  # MediaPipe gesture recognition
│   │
│   ├── # Speech Recognition
│   ├── SpeechRecognizer.swift      # Speech-to-text engine
│   ├── AvatarVideoPlayer.swift     # ASL avatar video player
│   └── DemoMode.swift              # Demo/testing controls
│
├── scripts/                        # Python Training Scripts
│   ├── train_*.py                  # Model training scripts
│   ├── process_*.py                # Dataset processing
│   ├── collect_*.py                # Data collection tools
│   └── web_*.py                    # Web-based tools
│
├── ASLModelData.json               # Trained model data (centroids)
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

##  ASL Sign Recognition

### Supported ASL Signs
The app supports **229+ ASL signs** including letters, numbers, and common words using a hybrid detection system with **multi-language support** (English, Spanish, Chinese).

---

### 🎯 TIER 1: Motion-Based Signs (Highest Reliability)

These signs use `MotionSignDetector` with gesture+motion analysis. **Recommended for demos.**

| Sign | Motion Pattern | How to Perform | Confidence | Front | Back | Glasses |
|------|---------------|----------------|------------|-------|------|---------|
| **HELLO** | Salute outward | Flat hand at forehead, sweep outward | 70-85% | ✅ | ✅ | ✅ |
| **THANK YOU** | Chin outward | Flat hand at chin, arc forward/down | 70-85% | ✅ | ✅ | ✅ |
| **PLEASE** | Circular on chest | Flat hand circles on chest | 70-85% | ✅ | ✅ | ✅ |
| **YES** | Fist pump | Closed fist, pump up/down (3+ cycles) | 75-90% | ✅ | ✅ | ✅ |
| **NO** | Side-to-side | Wave 1-3 fingers side-to-side (3+ cycles) | 75-90% | ✅ | ✅ | ✅ |
| **GOOD** | Chin downward | Flat hand at chin, move down | 75-90% | ✅ | ✅ | ✅ |
| **BYE** | Wave | Open hand waves side-to-side (2+ cycles) | 75-90% | ✅ | ✅ | ✅ |
| **I LOVE YOU** | Static hold | Thumb + index + pinky extended | 90-95% | ✅ | ✅ | ✅ |

---

### 🎯 TIER 2: Static Signs (Rule-Based Detection)

These use finger pattern detection. **Very reliable for distinctive hand shapes.**

| Sign | Hand Shape | Confidence | Front | Back | Glasses |
|------|-----------|------------|-------|------|---------|
| **Good/Thumbs Up** | Fist + thumb pointing up | 90-92% | ✅ | ✅ | ✅ |
| **Peace/2** | Index + middle extended | 85-88% | ✅ | ✅ | ✅ |
| **1/Point** | Only index finger extended | 85-88% | ✅ | ✅ | ✅ |
| **Y** | Thumb + pinky only | 85-88% | ✅ | ✅ | ✅ |
| **L** | Thumb + index at 90° angle | 82-85% | ✅ | ✅ | ✅ |
| **3** | Thumb + index + middle | 82-85% | ✅ | ✅ | ✅ |
| **4** | 4 fingers extended, thumb curled | 82-85% | ✅ | ✅ | ✅ |
| **W** | Index + middle + ring extended | 82-85% | ✅ | ✅ | ✅ |
| **I** | Only pinky extended | 82-85% | ✅ | ✅ | ✅ |

---

### 🎯 TIER 3: ML Model Signs (229 Classes)

These use centroid-based ML classification. Confidence varies by sign distinctiveness.

**Fingerspelling (A-Z):** Expected 70-90% confidence
```
A, B, C, D, E, F, G, H, I, J, K, L, M, N, O, P, Q, R, S, T, U, V, W, X, Y, Z
```

**Numbers (0-9):** Expected 75-95% confidence
```
0, 1, 2, 3, 4, 5, 6, 7, 8, 9
```

**Common Words (197 signs):** Expected 60-85% confidence
```
AFTERNOON, ALL, ANGRY, BABY, BAD, BATHROOM, BIG, BLACK, BLUE, BROTHER, 
COLD, COME, DOCTOR, DONE, DRINK, EAT, FAMILY, FATHER, FINISH, FOOD, 
GO, GOOD, GOODBYE, HAPPY, HELLO, HELP, HOME, HOT, HUNGRY, HURT, 
KNOW, LIKE, LOVE, MILK, MOM, MORE, MORNING, MOTHER, MY, NAME, NEED, 
NICE, NIGHT, NO, NOW, ORANGE, PLEASE, RED, SAD, SCHOOL, SEE, SICK, 
SISTER, SIT, SLEEP, SORRY, STAND, STOP, THANK_YOU, TIRED, TODAY, 
TOMORROW, WAIT, WANT, WATER, WEEK, WHAT, WHEN, WHERE, WHITE, WHO, 
WHY, WORK, YEAR, YES, YOU, YOUR... (and 120+ more)
```

---

### 🌍 Multi-Language Support

Detected signs are automatically translated and spoken in the user's preferred language:

| Sign | English | Spanish | Chinese |
|------|---------|---------|---------|
| HELLO | Hello | Hola | 你好 |
| THANK YOU | Thank You | Gracias | 谢谢 |
| PLEASE | Please | Por favor | 请 |
| YES | Yes | Sí | 是 |
| NO | No | No | 不 |
| GOOD | Good | Bueno | 好 |
| BYE | Bye | Adiós | 再见 |
| I LOVE YOU | I Love You | Te quiero | 我爱你 |

---

### 📱 Camera Compatibility

| Camera Source | Detection Quality | Notes |
|---------------|-------------------|-------|
| **iPhone Front** | ⭐⭐⭐⭐⭐ Excellent | Best for selfie-mode signing |
| **iPhone Back** | ⭐⭐⭐⭐ Very Good | Works with geometric pinky detection |
| **Meta Glasses** | ⭐⭐⭐⭐⭐ Excellent | First-person POV, natural signing |

---

### Detection Features
- **Temporal Smoothing**: Exponential moving average reduces jitter
- **N-of-M Agreement**: Requires 3 of 5 frames to agree before confirming
- **Rotation Invariance**: Works regardless of hand orientation
- **80% Confidence Threshold**: Only shows high-confidence predictions
- **I Love You Priority**: Checked first to prevent false HELLO/YES detections
- **Geometric Pinky Detection**: Alternative detection for back camera compatibility

### Basic Gestures (MediaPipe)
| Gesture | Icon | Description |
|---------|------|-------------|
| `Open_Palm` | ✋ | Open hand facing camera |
| `Closed_Fist` | ✊ | Closed fist |
| `Thumb_Up` | 👍 | Thumbs up |
| `Thumb_Down` | 👎 | Thumbs down |
| `Victory` | ✌️ | Peace sign |
| `Pointing_Up` | ☝️ | Index finger up |
| `ILoveYou` | 🤟 | ASL "I love you" |

##  Speech → ASL Video System

### Multi-Language Support & Accuracy

| Language | Total Words | Translated | Accuracy | Notes |
|----------|-------------|------------|----------|-------|
| **English** | 103 | 103 | **100%** | Native support |
| **Spanish** | 103 | 77 | **75%** | Speak Spanish words |
| **Chinese** | 103 | 78 | **76%** | Speak Mandarin words |

> 📖 **[Complete Word List →](docs/SPEECH_TO_ASL_WORDS.md)** - Full list of supported words in all languages

### Supported Word Categories (103 Words)

| Category | Count | Examples |
|----------|-------|----------|
| **Greetings** | 6 | hello, hi, bye, goodbye, morning, night |
| **Responses** | 8 | yes, no, please, sorry, thank you, ok |
| **Feelings** | 11 | happy, sad, angry, love, tired, hungry |
| **Actions** | 19 | help, stop, wait, go, come, eat, drink |
| **Questions** | 7 | what, where, when, who, why, how |
| **People** | 7 | family, father, mother, brother, sister |
| **Places** | 3 | home, school, bathroom |
| **Time** | 8 | now, today, tomorrow, day, week, year |
| **Numbers** | 10 | one, two, three... ten |
| **Colors** | 10 | red, blue, green, yellow, orange... |
| **Descriptions** | 14 | good, bad, big, small, hot, cold |

### Adding New Signs
1. Create video of ASL sign (MP4/MOV/M4V)
2. Name file after the word: `hello.mp4`, `thank_you.mp4`
3. Add to `ProjectUnmute ProjectUnmute/AvatarAssets/`
4. For multi-language support, add translations to `LanguageSettings.swift`
5. App auto-detects and maps to spoken words

### Sample Word Mappings
| Spoken Word | Video File |
|-------------|------------|
| "Hello" / "Hola" / "你好" | `hello.mp4` |
| "Thank you" / "Gracias" / "谢谢" | `thank_you.mp4` |
| "Goodbye" / "Adiós" / "再见" | `goodbye.mp4` |
| "Help" / "Ayuda" / "帮助" | `help.mp4` |
| "Yes" / "Sí" / "是" | `yes.mp4` |

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
- [x] Multi-camera source support (Front, Back, Meta Glasses)
- [x] Custom ML model for ASL detection (centroid classifier)
- [x] Motion-based dynamic sign detection (HELLO, THANK YOU, YES, NO, etc.)
- [x] Temporal smoothing & stabilization
- [x] 229+ sign vocabulary
- [x] Multi-language support (English, Spanish, Chinese)
- [x] Text-to-speech in selected language
- [x] I Love You detection with geometric pinky analysis
- [x] Back camera compatibility fixes
- [ ] Two-handed sign detection
- [ ] Real-time ASL-to-speech synthesis improvements
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
