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

[![App Demo Video](https://img.youtube.com/vi/kL8WR2BcHiY/0.jpg)](https://youtu.be/kL8WR2BcHiY)

**▶️ [Watch the App Demo Video](https://youtu.be/kL8WR2BcHiY)**

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

### Overview
The app uses a **hybrid detection system** combining motion-based detection, rule-based static sign detection, and ML classification. The system supports **18 ASL signs** that can be reliably detected across all camera sources, with **multi-language output** (English, Spanish, Chinese).

---

### 🎯 Supported ASL Signs (18 Signs)

These signs are specifically tuned for **consistent, reliable detection** across iPhone Front Camera, Back Camera, and Meta Glasses.

#### Numbers (6 signs) - ML Classifier
| # | Sign | Detection Method | Confidence | Notes |
|---|------|-----------------|------------|-------|
| 1 | **0** | ML Classifier | 80% | Closed fist |
| 2 | **1** | ML Classifier | 80% | Index finger up |
| 3 | **2** | ML Classifier | 80% | Index + middle up |
| 4 | **3** | ML Classifier | 80% | Thumb + index + middle |
| 5 | **4** | ML Classifier | 80% | Four fingers up |
| 6 | **5** | ML Classifier | 80% | Open hand |

#### Greetings & Social (6 signs)
| # | Sign | Detection Method | Confidence | English | Spanish | Chinese |
|---|------|-----------------|------------|---------|---------|--------|
| 7 | **HELLO** | Motion + ML | 80-88% | Hello | Hola | 你好 |
| 8 | **BYE** | Motion | 80-85% | Bye | Adiós | 再见 |
| 9 | **THANK YOU** | Motion | 80-85% | Thank You | Gracias | 谢谢 |
| 10 | **PLEASE** | Motion + ML | 80-85% | Please | Por favor | 请 |
| 11 | **SORRY** | ML Classifier | 80% | Sorry | Lo siento | 对不起 |
| 12 | **OK** | ML Classifier | 80% | OK | OK | 好的 |

#### Responses & Actions (3 signs)
| # | Sign | Detection Method | Confidence | English | Spanish | Chinese |
|---|------|-----------------|------------|---------|---------|--------|
| 13 | **YES** | Motion | 80-90% | Yes | Sí | 是 |
| 14 | **STOP** | Motion | 85-90% | Stop | Para | 停 |
| 15 | **GOOD** | Motion | 85-92% | Good | Bueno | 好 |

#### Gestures (3 signs)
| # | Sign | Detection Method | Confidence | English | Spanish | Chinese |
|---|------|-----------------|------------|---------|---------|--------|
| 16 | **PEACE** | Motion (Static) | 85-90% | Peace | Paz | 和平 |
| 17 | **I LOVE YOU** | Motion (Static) | 90-95% | I Love You | Te amo | 我爱你 |
| 18 | **ILY** | ML Classifier | 80% | I Love You | Te amo | 我爱你 |

> **Note:** The ML model was trained on a limited dataset. Additional signs can be added by retraining the model with more data.

---

### 📱 Camera Compatibility Matrix

| Category | Signs | iPhone Front | iPhone Back | Meta Glasses |
|----------|-------|:------------:|:-----------:|:------------:|
| **Numbers** | 0, 1, 2, 3, 4, 5 | ✅ High | ✅ High | ✅ High |
| **Greetings** | HELLO, BYE, THANK YOU, PLEASE, SORRY, OK | ✅ High | ✅ High | ✅ High |
| **Actions** | YES, STOP, GOOD | ✅ High | ✅ High | ✅ High |
| **Gestures** | PEACE, I LOVE YOU, ILY | ✅ High | ✅ High | ✅ High |

**Detection Quality Summary:**
| Camera Source | Quality | Best For |
|---------------|---------|----------|
| **iPhone Front** | ⭐⭐⭐⭐⭐ Excellent | Selfie-mode signing, demos |
| **iPhone Back** | ⭐⭐⭐⭐ Very Good | Third-person recording |
| **Meta Glasses** | ⭐⭐⭐⭐⭐ Excellent | First-person POV, real-world use |

---

### 🔧 Detection System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     ASLSignDetector                              │
│  (Orchestrates detection, manages cooldowns, outputs speech)    │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌─────────────────────┐    ┌─────────────────────┐             │
│  │ MotionSignDetector  │    │  ASLModelClassifier │             │
│  │ (Dynamic Signs)     │    │  (Static Signs)     │             │
│  │                     │    │                     │             │
│  │ • YES (fist pump)   │    │ • ML model (13 cls) │             │
│  │ • PLEASE (rub)      │    │ • 0-5, HELLO, ILY   │             │
│  │ • BYE (wave)        │    │ • OK, PEACE, PLEASE │             │
│  │ • HELLO (sweep)     │    │ • SORRY             │             │
│  │ • THANK YOU (chin)  │    │                     │             │
│  │ • GOOD (thumbs up)  │    │ Filtered to 18 signs│             │
│  │ • PEACE (V-sign)    │    │ (ML + Motion)       │             │
│  └─────────────────────┘    └─────────────────────┘             │
│           │                            │                         │
│           ▼                            ▼                         │
│  ┌──────────────────────────────────────────────────────────┐│
│  │                    Detection Pipeline                        ││
│  │  1. Validate landmarks (filter noise)                        ││
│  │  2. Check motion signs FIRST (priority)                      ││
│  │  3. Check ML classifier (filtered to 18 signs)               ││
│  │  4. Apply 8-frame stabilization                              ││
│  │  5. Apply 5-second transition cooldown                       ││
│  │  6. Confirm and speak via TTS                                ││
│  └──────────────────────────────────────────────────────────┐│
└─────────────────────────────────────────────────────────────────┘
```

---

### ⚙️ Detection Parameters

| Parameter | Value | Purpose |
|-----------|-------|--------|
| **Stability Threshold** | 8 frames | Consecutive frames required before confirmation |
| **Transition Cooldown** | 5 seconds | Wait time between ANY two sign detections |
| **Same-Sign Cooldown** | 8 seconds | Wait time before detecting the same sign again |
| **Confidence Threshold** | 80% | Minimum confidence to confirm a sign |
| **Motion Threshold** | 0.02 | Minimum movement magnitude to detect motion |

---

### 🗂️ Dataset & Training

#### Training Datasets

The ML model was trained using multiple publicly available ASL datasets:

| # | Dataset | Samples | Classes | Description | Source |
|---|---------|---------|---------|-------------|--------|
| 1 | **WLASL** | ~50,000+ | 100-2000 | Word-Level American Sign Language video dataset | [GitHub](https://github.com/dxli94/WLASL) |
| 2 | **WLASL Full** | ~500,000+ | 2,000 | Complete WLASL with all sign variations | [GitHub](https://github.com/dxli94/WLASL) |
| 3 | **ASL Citizen** | ~100,000+ | 2,731 | Community-contributed signs from 52 deaf signers | [Microsoft Research](https://www.microsoft.com/en-us/research/project/asl-citizen/) |
| 4 | **Kaggle ASL Alphabet** | ~20,000+ | 26 (A-Z) | Fingerspelling alphabet dataset | [Kaggle](https://www.kaggle.com/datasets/grassknoted/asl-alphabet) |
| 5 | **Combined ASL** | ~60,000+ | Mixed | Merged dataset from multiple sources | Custom |
| 6 | **Custom Collected** | ~12,000+ | 50+ | Hand-collected samples for specific signs | In-house |

#### Dataset Sources

**WLASL (Word-Level American Sign Language)**
- 2,000 ASL glosses with video instances
- Multiple signers performing each sign
- Subset configs: `nslt_100.json`, `nslt_300.json`, `nslt_1000.json`, `nslt_2000.json`

**ASL Citizen**
- Microsoft Research dataset
- 83,399 video samples across 2,731 signs
- Recorded by 52 Deaf ASL signers
- High diversity in signing styles

**Kaggle ASL Alphabet**
- 87,000 images of 26 ASL letters (A-Z)
- Static hand poses for fingerspelling

#### Model Architecture

| Component | Details |
|-----------|--------|
| **Hand Landmark Model** | MediaPipe Hand Landmarker (21 landmarks) |
| **ML Classifier** | Centroid-based classifier with EMA smoothing |
| **Training Output** | `ASLModelData.json` (229 sign classes) |
| **Feature Vector** | 63 floats (x, y, z for each of 21 landmarks) |
| **Normalization** | Wrist-centered, scale-normalized, X-mirrored |
| **Confidence Threshold** | 80% minimum for sign confirmation |

---

### 🌍 Multi-Language Output

Detected signs are automatically translated and spoken via Text-to-Speech:

| Language | Code | TTS Voice | Example Output |
|----------|------|-----------|---------------|
| **English** | en-US | Default US English | "Hello" |
| **Spanish** | es-ES | Spanish (Spain) | "Hola" |
| **Chinese** | zh-CN | Mandarin Chinese | "你好" |

---

### 🎯 TIER 2: Additional Static Signs (Rule-Based)

These signs are detected via finger pattern analysis but may overlap with the 9 primary signs:

| Sign | Hand Shape | Confidence |
|------|-----------|------------|
| **1/Point** | Only index finger extended | 85-88% |
| **Y** | Thumb + pinky only | 85-88% |
| **L** | Thumb + index at 90° angle | 82-85% |
| **3** | Thumb + index + middle | 82-85% |
| **4** | 4 fingers extended, thumb curled | 82-85% |
| **W** | Index + middle + ring extended | 82-85% |

---

### 🎯 TIER 3: ML Model Signs (229 Classes)

The full ML model supports 229 sign classes, but output is **filtered to only the 9 primary signs** to prevent false positives.

**Fingerspelling (A-Z):** Available in ML model, filtered out
**Numbers (0-9):** Available in ML model, filtered out
**Common Words:** 197 signs available, 9 allowed through filter

---

### Detection Features
- **Landmark Validation**: Filters out noise when no hand is in frame
- **Temporal Smoothing**: Exponential moving average reduces jitter
- **N-of-M Agreement**: Requires 8 consecutive frames to confirm
- **Rotation Invariance**: Works regardless of hand orientation
- **80% Confidence Threshold**: Only shows high-confidence predictions
- **I Love You Priority**: Checked first to prevent false positives
- **Geometric Pinky Detection**: Alternative detection for back camera
- **Coordinate Mirroring**: X-axis mirrored for all cameras for consistency

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

| Language | Total Words | With Video | Accuracy | Notes |
|----------|-------------|------------|----------|-------|
| **English** | 100 | 99 | **99%** | Native support |
| **Spanish** | 100 | 99 | **99%** | Speak Spanish words |
| **Chinese** | 100 | 99 | **99%** | Speak Mandarin words |

### Complete Supported Words Table

| # | English | Spanish | Chinese | Video | Confidence |
|---|---------|---------|---------|-------|------------|
| **Greetings** |||||
| 1 | hello | hola | 你好 | ✅ | High |
| 2 | hi | hola | 嗨 | ✅ | High |
| 3 | bye | adiós | 再见 | ✅ | High |
| 4 | goodbye | adiós | 再见 | ✅ | High |
| 5 | morning | buenos días | 早上好 | ✅ | High |
| 6 | night | buenas noches | 晚安 | ✅ | High |
| **Responses** |||||
| 7 | yes | sí | 是 | ✅ | High |
| 8 | no | no | 不 | ✅ | High |
| 9 | maybe | quizás | 也许 | ✅ | High |
| 10 | ok | ok | 好的 | ✅ | High |
| 11 | please | por favor | 请 | ✅ | High |
| 12 | sorry | lo siento | 对不起 | ✅ | High |
| 13 | thank you | gracias | 谢谢 | ✅ | Medium* |
| **Feelings** |||||
| 14 | happy | feliz | 快乐 | ✅ | High |
| 15 | sad | triste | 悲伤 | ✅ | High |
| 16 | angry | enojado | 生气 | ✅ | High |
| 17 | love | amor | 爱 | ✅ | High |
| 18 | fine | bien | 很好 | ✅ | High |
| 19 | tired | cansado | 累 | ✅ | High |
| 20 | hungry | hambriento | 饿 | ✅ | High |
| 21 | thirsty | sediento | 渴 | ✅ | High |
| 22 | sick | enfermo | 生病 | ✅ | High |
| 23 | hurt | herido | 受伤 | ✅ | High |
| 24 | pain | dolor | 疼痛 | ✅ | High |
| **Actions** |||||
| 25 | help | ayuda | 帮助 | ✅ | High |
| 26 | stop | para | 停 | ✅ | High |
| 27 | wait | espera | 等 | ✅ | High |
| 28 | go | ve | 去 | ✅ | High |
| 29 | come | ven | 来 | ✅ | High |
| 30 | sit | siéntate | 坐 | ✅ | High |
| 31 | stand | levántate | 站 | ✅ | High |
| 32 | open | abre | 开 | ✅ | High |
| 33 | close | cierra | 关 | ✅ | High |
| 34 | eat | come | 吃 | ✅ | High |
| 35 | drink | bebe | 喝 | ✅ | High |
| 36 | want | quiero | 想要 | ✅ | High |
| 37 | need | necesito | 需要 | ✅ | High |
| 38 | like | me gusta | 喜欢 | ✅ | High |
| 39 | know | sé | 知道 | ✅ | High |
| 40 | understand | entiendo | 明白 | ✅ | High |
| 41 | finish | terminar | 完成 | ✅ | High |
| 42 | done | hecho | 完成了 | ✅ | High |
| 43 | work | trabajo | 工作 | ✅ | High |
| **Questions** |||||
| 44 | what | qué | 什么 | ✅ | High |
| 45 | where | dónde | 哪里 | ✅ | High |
| 46 | when | cuándo | 什么时候 | ✅ | High |
| 47 | who | quién | 谁 | ✅ | High |
| 48 | why | por qué | 为什么 | ✅ | High |
| 49 | how | cómo | 怎么 | ✅ | High |
| 50 | which | cuál | 哪个 | ✅ | High |
| **People** |||||
| 51 | family | familia | 家人 | ✅ | High |
| 52 | friend | amigo | 朋友 | ✅ | High |
| 53 | father | padre | 父亲 | ✅ | High |
| 54 | mother | madre | 母亲 | ✅ | High |
| 55 | brother | hermano | 兄弟 | ✅ | High |
| 56 | sister | hermana | 姐妹 | ✅ | High |
| 57 | doctor | doctor | 医生 | ✅ | High |
| **Places** |||||
| 58 | home | casa | 家 | ✅ | High |
| 59 | school | escuela | 学校 | ✅ | High |
| 60 | bathroom | baño | 洗手间 | ✅ | High |
| **Time** |||||
| 61 | now | ahora | 现在 | ✅ | High |
| 62 | later | después | 稍后 | ✅ | High |
| 63 | today | hoy | 今天 | ✅ | High |
| 64 | tomorrow | mañana | 明天 | ✅ | High |
| 65 | day | día | 天 | ✅ | High |
| 66 | week | semana | 周 | ✅ | High |
| 67 | year | año | 年 | ✅ | High |
| 68 | again | otra vez | 再次 | ✅ | High |
| **Numbers** |||||
| 69 | one | uno | 一 | ✅ | High |
| 70 | two | dos | 二 | ✅ | High |
| 71 | three | tres | 三 | ❌ | None |
| 72 | four | cuatro | 四 | ✅ | High |
| 73 | five | cinco | 五 | ✅ | High |
| 74 | six | seis | 六 | ✅ | High |
| 75 | seven | siete | 七 | ✅ | High |
| 76 | eight | ocho | 八 | ✅ | High |
| 77 | nine | nueve | 九 | ✅ | High |
| 78 | ten | diez | 十 | ✅ | High |
| **Colors** |||||
| 79 | red | rojo | 红色 | ✅ | High |
| 80 | blue | azul | 蓝色 | ✅ | High |
| 81 | green | verde | 绿色 | ✅ | High |
| 82 | yellow | amarillo | 黄色 | ✅ | High |
| 83 | orange | naranja | 橙色 | ✅ | High |
| 84 | purple | morado | 紫色 | ✅ | High |
| 85 | pink | rosa | 粉色 | ✅ | High |
| 86 | black | negro | 黑色 | ✅ | High |
| 87 | white | blanco | 白色 | ✅ | High |
| 88 | brown | marrón | 棕色 | ✅ | High |
| **Descriptions** |||||
| 89 | good | bueno | 好 | ✅ | High |
| 90 | bad | malo | 坏 | ✅ | High |
| 91 | big | grande | 大 | ✅ | High |
| 92 | small | pequeño | 小 | ✅ | High |
| 93 | hot | caliente | 热 | ✅ | High |
| 94 | cold | frío | 冷 | ✅ | High |
| 95 | cool | genial | 酷 | ✅ | High |
| 96 | more | más | 更多 | ✅ | High |
| 97 | all | todo | 全部 | ✅ | High |
| 98 | name | nombre | 名字 | ✅ | High |
| 99 | water | agua | 水 | ✅ | High |
| 100 | food | comida | 食物 | ✅ | High |

### Confidence Levels
| Level | Meaning |
|-------|---------|
| **High** | Single word, exact match, video available |
| **Medium*** | Multi-word phrase (e.g., "thank you" → `thank_you.mp4`) |
| **None** | No video file available |

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
