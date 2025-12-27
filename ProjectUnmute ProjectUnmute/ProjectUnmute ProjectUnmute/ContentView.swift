import SwiftUI
import AVKit
// Meta SDK imports commented out - using stubs instead
// import MWDATCamera
// import MWDATCore

// MARK: - ContentView

// Communication mode enum
enum CommunicationMode: String, CaseIterable {
    case speechToASL = "Speech → ASL"
    case aslToText = "ASL → Text"
}

struct ContentView: View {
    // Use DeviceCameraManager for real iPhone camera, or MWDATCameraManager for simulator stub
    @StateObject private var cameraManager = DeviceCameraManager()
    @StateObject private var gestureManager = GestureRecognitionManager()
    @StateObject private var speechManager = SpeechRecognitionManager()
    @StateObject private var avatarManager = AvatarVideoManager()
    @StateObject private var demoController = DemoModeController.shared
    @StateObject private var aslDetector = ASLSignDetector.shared
    
    @State private var showAvatarView = false
    @State private var communicationMode: CommunicationMode = .speechToASL
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                // For ASL→Text mode, always show the full view with controls
                if communicationMode == .aslToText {
                    aslToTextView
                } else {
                    // Speech→ASL mode uses state-based views
                    switch cameraManager.state {
                    case .disconnected:
                        disconnectedView
                    case .connecting:
                        ProgressView("Connecting to glasses...")
                            .foregroundColor(.white)
                    case .streaming:
                        streamingView
                    case .error(let message):
                        errorView(message: message)
                    }
                }
            }
            .navigationTitle("Project Unmute")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 12) {
                        micButton
                        DemoModeToggle()
                    }
                }
                ToolbarItem(placement: .principal) {
                    // Mode switcher buttons
                    HStack(spacing: 4) {
                        Button(action: { communicationMode = .speechToASL }) {
                            Text("Speech→ASL")
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(communicationMode == .speechToASL ? Color.blue : Color.gray.opacity(0.3))
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                        }
                        
                        Button(action: { communicationMode = .aslToText }) {
                            Text("ASL→Text")
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(communicationMode == .aslToText ? Color.green : Color.gray.opacity(0.3))
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    connectionButton
                }
            }
            .overlay(alignment: .bottom) {
                // Only show Speech demo controls in Speech → ASL mode
                if demoController.showDemoControls && communicationMode == .speechToASL {
                    DemoControlPanel(
                        speechManager: speechManager,
                        avatarManager: avatarManager,
                        showAvatarView: $showAvatarView
                    )
                    .transition(.move(edge: .bottom))
                }
            }
            .onChange(of: speechManager.matchedAvatarVideo) { _, videoName in
                if let name = videoName {
                    showAvatarView = true  // Auto-switch to avatar view
                    avatarManager.playVideo(for: name)
                }
            }
            .onChange(of: communicationMode) { _, newMode in
                // Stop video when switching modes to prevent background audio
                avatarManager.stopVideo()
                speechManager.stopListening()
            }
        }
    }
    
    private var micButton: some View {
        Button(action: { toggleSpeechRecognition() }) {
            Image(systemName: speechManager.isListening ? "mic.fill" : "mic.slash")
                .foregroundColor(speechManager.isListening ? .green : .gray)
        }
    }
    
    private func toggleSpeechRecognition() {
        if speechManager.isListening {
            speechManager.stopListening()
        } else {
            Task {
                await speechManager.startListening()
            }
        }
    }
    
    // MARK: - Subviews
    
    private var disconnectedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "eyeglasses")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("Ray-Ban Meta Glasses")
                .font(.title2)
                .foregroundColor(.white)
            
            Text("Connect your glasses to start streaming")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Button(action: { cameraManager.startStreaming() }) {
                Label("Start Streaming", systemImage: "video.fill")
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: 250)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }
        }
    }
    
    private var streamingView: some View {
        Group {
            // Show different content based on communication mode
            if communicationMode == .speechToASL {
                // SPEECH → ASL MODE (Original functionality)
                speechToASLView
            } else {
                // ASL → TEXT MODE (New functionality)
                aslToTextView
            }
        }
    }
    
    // MARK: - Speech → ASL View (Original)
    
    private var speechToASLView: some View {
        VStack(spacing: 0) {
            // Toggle between camera view and avatar view
            HStack(spacing: 8) {
                ViewModeButton(title: "Camera", icon: "video", isSelected: !showAvatarView) {
                    showAvatarView = false
                }
                ViewModeButton(title: "Avatar", icon: "person.crop.rectangle", isSelected: showAvatarView) {
                    showAvatarView = true
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            
            if showAvatarView {
                // Avatar video view - same size as camera (45% of screen)
                AvatarVideoPlayer(videoName: avatarManager.currentVideoName)
                    .frame(height: UIScreen.main.bounds.height * 0.45)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
            } else {
                // Live video feed with gesture overlay - 45% of screen height (same as ASL-to-Text)
                GeometryReader { geometry in
                    ZStack {
                        // Use camera preview layer for live video, fallback to frame display
                        if let previewLayer = cameraManager.previewLayer {
                            CameraPreviewView(previewLayer: previewLayer)
                        } else {
                            MWDATVideoView(frame: cameraManager.currentFrame)
                        }
                        
                        // Hand landmarks overlay
                        if !gestureManager.detectedGestures.isEmpty {
                            HandLandmarksOverlay(gestures: gestureManager.detectedGestures)
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .frame(height: UIScreen.main.bounds.height * 0.45)
                .padding(.horizontal)
            }
            
            // Speech transcription display
            TranscriptionView(
                text: speechManager.transcribedText,
                lastWord: speechManager.lastRecognizedWord,
                isListening: speechManager.isListening
            )
            .padding(.horizontal)
            
            // Speech status/error display
            if let error = speechManager.error {
                Text("⚠️ \(error)")
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }
            
            // Debug: Show matched video
            if let matched = speechManager.matchedAvatarVideo {
                Text("🎬 Matched: \(matched)")
                    .font(.caption)
                    .foregroundColor(.green)
                    .padding(.horizontal)
            }
            
            // Stream info bar
            HStack {
                Label("Live", systemImage: "circle.fill")
                    .foregroundColor(.red)
                    .font(.caption)
                
                Spacer()
                
                Text("\(Int(cameraManager.frameRate)) FPS")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            
            // Text-to-Speech toggle
            Toggle(isOn: $gestureManager.speakGesturesEnabled) {
                HStack {
                    Image(systemName: gestureManager.speakGesturesEnabled ? "speaker.wave.3.fill" : "speaker.slash.fill")
                        .foregroundColor(gestureManager.speakGesturesEnabled ? .green : .gray)
                    Text("Speak Gestures")
                        .font(.subheadline)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .cornerRadius(10)
            .padding(.horizontal)
            
            // Detected gestures display
            GestureResultsView(
                gestures: gestureManager.detectedGestures,
                pointingProgress: gestureManager.pointingHoldProgress,
                thankYouProgress: gestureManager.thankYouHoldProgress,
                didTriggerSpeech: gestureManager.didTriggerSpeech,
                lastSpokenPhrase: gestureManager.lastSpokenPhrase
            )
            .padding(.top, 12)
            
            Spacer()
            
            // Stop button
            Button(action: { stopAll() }) {
                Label("Stop Streaming", systemImage: "stop.fill")
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: 250)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }
            .padding(.bottom, 40)
        }
        .onChange(of: cameraManager.currentFrame) { _, newFrame in
            if let frame = newFrame {
                gestureManager.processFrame(frame)
            }
        }
    }
    
    // MARK: - ASL → Text View (New)
    
    private var aslToTextView: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Camera source picker
                VStack(spacing: 6) {
                    HStack {
                        Text("Camera Source")
                            .font(.caption.bold())
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        Button(action: { cameraManager.discoverCameras() }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                Text("Refresh")
                            }
                            .font(.caption)
                            .foregroundColor(.blue)
                        }
                    }
                    .padding(.horizontal)
                    
                    HStack(spacing: 8) {
                        ForEach(cameraManager.availableCameras, id: \.self) { source in
                            Button(action: { cameraManager.switchCamera(to: source) }) {
                                VStack(spacing: 2) {
                                    Image(systemName: source.icon)
                                        .font(.title3)
                                    Text(source.rawValue)
                                        .font(.caption2)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(cameraManager.cameraSource == source ? Color.green : Color.gray.opacity(0.3))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    // Show Meta Glasses status and authorize button when selected
                    if cameraManager.cameraSource == .metaGlasses {
                        VStack(spacing: 8) {
                            MetaGlassesStatusView()
                            
                            // Show status message
                            Text(MetaGlassesCameraManager.shared.statusMessage)
                                .font(.caption)
                                .foregroundColor(.yellow)
                                .multilineTextAlignment(.center)
                            
                            // Big Authorize button only if not authorized yet
                            if cameraManager.currentFrame == nil && !MetaGlassesCameraManager.shared.isAuthorized {
                                Button(action: {
                                    Task {
                                        await MetaGlassesCameraManager.shared.openMetaAIForAuthorization()
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: "link.badge.plus")
                                        Text("Authorize in Meta AI")
                                    }
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue)
                                    .cornerRadius(10)
                                }
                            }
                            
                            // Show waiting message if authorized but no frames
                            if cameraManager.currentFrame == nil && MetaGlassesCameraManager.shared.isAuthorized {
                                VStack(spacing: 8) {
                                    ProgressView()
                                        .scaleEffect(1.2)
                                    Text("Waiting for video from glasses...")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                    Text("👓 Put glasses on & tap temple to wake")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                    
                                    // Restart button if stuck
                                    Button(action: {
                                        Task {
                                            await MetaGlassesCameraManager.shared.restartStreaming()
                                        }
                                    }) {
                                        HStack {
                                            Image(systemName: "arrow.clockwise")
                                            Text("Restart Connection")
                                        }
                                        .font(.caption)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.blue)
                                        .cornerRadius(8)
                                    }
                                    .padding(.top, 4)
                                }
                                .padding()
                            }
                            
                            // No video message only if not authorized
                            if cameraManager.currentFrame == nil && !MetaGlassesCameraManager.shared.isAuthorized {
                                VStack(spacing: 8) {
                                    Text("⚠️ Camera permission required")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                    
                                    // Manual permission button
                                    Button(action: {
                                        // Open Meta AI app settings
                                        if let url = URL(string: "meta-ai://") {
                                            UIApplication.shared.open(url)
                                        }
                                    }) {
                                        HStack {
                                            Image(systemName: "gear")
                                            Text("Open Meta AI Settings")
                                        }
                                        .font(.caption)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.orange)
                                        .cornerRadius(8)
                                    }
                                    
                                    Text("Go to Settings → Connected Apps → ProjectUnmute → Enable Camera")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                        .multilineTextAlignment(.center)
                                }
                            }
                            
                            // Fallback to iPhone camera button
                            Button(action: {
                                cameraManager.switchCamera(to: .iPhoneFront)
                            }) {
                                HStack {
                                    Image(systemName: "iphone")
                                    Text("Use iPhone Camera Instead")
                                }
                                .font(.subheadline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(10)
                                .background(Color.green)
                                .cornerRadius(8)
                            }
                            .padding(.top, 4)
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical, 8)
                
                // Camera view - 60% of screen height
                GeometryReader { geometry in
                    ZStack {
                        // For iPhone cameras, use native preview layer
                        // For Meta Glasses, use MWDATVideoView with currentFrame
                        if cameraManager.cameraSource == .metaGlasses {
                            // Meta Glasses uses currentFrame directly
                            MWDATVideoView(frame: cameraManager.currentFrame)
                        } else if let previewLayer = cameraManager.previewLayer {
                            // iPhone cameras use AVCaptureVideoPreviewLayer
                            CameraPreviewView(previewLayer: previewLayer)
                        } else if let frame = cameraManager.currentFrame {
                            // Fallback: show currentFrame if preview layer not available
                            MWDATVideoView(frame: frame)
                        } else {
                            // Loading state
                            ZStack {
                                Color.black
                                VStack(spacing: 8) {
                                    ProgressView()
                                        .tint(.white)
                                    Text("Starting camera...")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                        
                        VStack {
                            Spacer()
                            HStack {
                                Image(systemName: cameraManager.cameraSource.icon)
                                Text(cameraManager.cameraSource.rawValue)
                            }
                            .font(.caption2)
                            .padding(4)
                            .background(Color.black.opacity(0.7))
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                        }
                        .padding(.bottom, 4)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .frame(height: UIScreen.main.bounds.height * 0.45)
                .padding(.horizontal)
                
                // ASL Detection panel (compact)
                ASLDetectionView()
                    .padding(.horizontal)
                
                // Demo Panel for simulator - INLINE BUTTONS
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "hand.tap.fill")
                            .foregroundColor(.orange)
                        Text("DEMO MODE - Tap to simulate signs")
                            .font(.caption.bold())
                            .foregroundColor(.black)
                    }
                    
                    // Word buttons - Row 1
                    HStack(spacing: 6) {
                        ForEach(["Hello", "Good", "Yes", "No"], id: \.self) { word in
                            Button(word) {
                                aslDetector.simulateDetectedSign(word)
                            }
                            .font(.caption.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color.blue)
                            .cornerRadius(8)
                        }
                    }
                    
                    // Word buttons - Row 2
                    HStack(spacing: 6) {
                        ForEach(["Please", "Thanks", "Help", "Stop"], id: \.self) { word in
                            Button(word) {
                                aslDetector.simulateDetectedSign(word)
                            }
                            .font(.caption.bold())
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color.green)
                            .cornerRadius(8)
                        }
                    }
                    
                    // Numbers
                    HStack(spacing: 6) {
                        ForEach(["1", "2", "3", "4", "5"], id: \.self) { num in
                            Button(num) {
                                aslDetector.simulateDetectedSign(num)
                            }
                            .font(.caption.bold())
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.orange)
                            .cornerRadius(8)
                        }
                    }
                }
                .padding()
                .background(Color.white)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.orange, lineWidth: 3)
                )
                .padding(.horizontal)
                
                // Action buttons
                HStack(spacing: 12) {
                    Button(action: { communicationMode = .speechToASL }) {
                        Text("← Speech Mode")
                            .font(.caption.bold())
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                    
                    Button(action: { stopAll() }) {
                        Text("Stop")
                            .font(.caption.bold())
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.red)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                }
                .padding(.bottom, 20)
                .padding(.horizontal)
            }
        }
        .onChange(of: cameraManager.currentFrame) { _, newFrame in
            if let frame = newFrame {
                gestureManager.processFrame(frame)
                processFrameForASL(frame)
            }
        }
    }
    
    /// Process frame for ASL sign detection using Vision framework
    private func processFrameForASL(_ frame: CGImage) {
        // Use Vision framework directly for hand detection
        // This runs on a background thread to avoid blocking UI
        DispatchQueue.global(qos: .userInteractive).async {
            aslDetector.processFrame(frame)
        }
    }
    
    private func stopAll() {
        cameraManager.stopStreaming()
        gestureManager.stop()
        speechManager.stopListening()
        avatarManager.stopVideo()
    }
    
    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 50))
                .foregroundColor(.orange)
            
            Text("Connection Error")
                .font(.title2)
                .foregroundColor(.white)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Retry") {
                cameraManager.startStreaming()
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
    private var connectionButton: some View {
        Button(action: {
            if cameraManager.state == .streaming {
                cameraManager.stopStreaming()
            } else {
                cameraManager.startStreaming()
            }
        }) {
            Image(systemName: cameraManager.state == .streaming ? "video.slash" : "video")
        }
    }
}

// MARK: - Gesture Results View

struct GestureResultsView: View {
    let gestures: [DetectedGesture]
    let pointingProgress: Double
    let thankYouProgress: Double
    let didTriggerSpeech: Bool
    let lastSpokenPhrase: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Speech trigger indicator
            if didTriggerSpeech, let phrase = lastSpokenPhrase {
                SpeechTriggerBanner(phrase: phrase)
            }
            
            if gestures.isEmpty {
                HStack {
                    Image(systemName: "hand.raised.slash")
                        .foregroundColor(.secondary)
                    Text("No gestures detected")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            } else {
                ForEach(gestures) { gesture in
                    GestureRow(
                        gesture: gesture,
                        holdProgress: holdProgress(for: gesture.name)
                    )
                }
            }
        }
        .padding(.horizontal)
        .animation(.easeInOut(duration: 0.2), value: gestures)
    }
    
    private func holdProgress(for gestureName: String) -> Double? {
        switch gestureName {
        case "POINTING": return pointingProgress
        case "THANK_YOU": return thankYouProgress
        default: return nil
        }
    }
}

struct SpeechTriggerBanner: View {
    let phrase: String
    
    var body: some View {
        HStack {
            Image(systemName: "speaker.wave.3.fill")
                .foregroundColor(.white)
                .symbolEffect(.pulse)
            Text("Speaking: \"\(phrase)\"")
                .font(.headline)
                .foregroundColor(.white)
            
            Spacer()
            
            // Bluetooth indicator
            if SpeechSynthesizer.shared.isBluetoothConnected {
                Image(systemName: "airpodsmax")
                    .foregroundColor(.white)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.green)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

struct GestureRow: View {
    let gesture: DetectedGesture
    let holdProgress: Double?  // For POINTING gesture hold tracking
    
    var body: some View {
        HStack {
            Image(systemName: gestureIcon)
                .font(.title2)
                .foregroundColor(gestureColor)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(gesture.name.replacingOccurrences(of: "_", with: " "))
                    .font(.headline)
                    .foregroundColor(.white)
                
                if let progress = holdProgress, gesture.isCustomGesture {
                    // Show hold progress for custom gestures (POINTING, THANK_YOU)
                    HStack(spacing: 4) {
                        Text("Hold: \(Int(progress * 2))s / 2s")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if progress >= 1.0 {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                        }
                    }
                } else {
                    Text("\(gesture.handedness) hand · \(Int(gesture.score * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Progress indicator
            if let progress = holdProgress, gesture.isCustomGesture {
                // Circular hold progress for custom gestures
                CircularProgressView(progress: progress, color: progress >= 1.0 ? .green : gestureColor)
                    .frame(width: 32, height: 32)
            } else {
                // Confidence indicator
                CircularProgressView(progress: Double(gesture.score), color: .green)
                    .frame(width: 32, height: 32)
            }
        }
        .padding(12)
        .background(gesture.isCustomGesture ? gestureColor.opacity(0.2) : Color.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(gesture.isCustomGesture ? gestureColor : Color.clear, lineWidth: 2)
        )
    }
    
    private var gestureIcon: String {
        switch gesture.name {
        case "Open_Palm": return "hand.raised.fill"
        case "Closed_Fist": return "hand.point.up.braille.fill"
        case "Thumb_Up": return "hand.thumbsup.fill"
        case "Thumb_Down": return "hand.thumbsdown.fill"
        case "Victory": return "peacesign"
        case "Pointing_Up": return "hand.point.up.fill"
        case "POINTING": return "hand.point.up.left.fill"
        case "THANK_YOU": return "hand.wave.fill"
        case "ILoveYou": return "hands.sparkles.fill"
        default: return "hand.raised"
        }
    }
    
    private var gestureColor: Color {
        switch gesture.name {
        case "Open_Palm": return .green
        case "Thumb_Up": return .blue
        case "Thumb_Down": return .orange
        case "Victory": return .purple
        case "ILoveYou": return .pink
        case "POINTING": return .orange
        case "THANK_YOU": return .cyan
        default: return .gray
        }
    }
}

struct CircularProgressView: View {
    let progress: Double
    var color: Color = .green
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 3)
            
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.1), value: progress)
        }
    }
}

// MARK: - Hand Landmarks Overlay

struct HandLandmarksOverlay: View {
    let gestures: [DetectedGesture]
    
    var body: some View {
        GeometryReader { geometry in
            ForEach(gestures) { gesture in
                HandLandmarkPath(landmarks: gesture.landmarks, size: geometry.size)
                    .stroke(gesture.handedness == "Left" ? Color.blue : Color.green, lineWidth: 2)
                
                // Draw landmark points
                ForEach(gesture.landmarks) { landmark in
                    Circle()
                        .fill(landmarkColor(for: landmark.id))
                        .frame(width: 6, height: 6)
                        .position(
                            x: CGFloat(landmark.x) * geometry.size.width,
                            y: CGFloat(landmark.y) * geometry.size.height
                        )
                }
            }
        }
    }
    
    private func landmarkColor(for index: Int) -> Color {
        switch index {
        case 0: return .red           // Wrist
        case 1...4: return .orange    // Thumb
        case 5...8: return .yellow    // Index
        case 9...12: return .green    // Middle
        case 13...16: return .blue    // Ring
        case 17...20: return .purple  // Pinky
        default: return .white
        }
    }
}

struct HandLandmarkPath: Shape {
    let landmarks: [HandLandmark]
    let size: CGSize
    
    // Finger connections for drawing lines
    private let connections: [(Int, Int)] = [
        // Thumb
        (0, 1), (1, 2), (2, 3), (3, 4),
        // Index
        (0, 5), (5, 6), (6, 7), (7, 8),
        // Middle
        (0, 9), (9, 10), (10, 11), (11, 12),
        // Ring
        (0, 13), (13, 14), (14, 15), (15, 16),
        // Pinky
        (0, 17), (17, 18), (18, 19), (19, 20),
        // Palm
        (5, 9), (9, 13), (13, 17)
    ]
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        guard landmarks.count == 21 else { return path }
        
        for (start, end) in connections {
            let startPoint = CGPoint(
                x: CGFloat(landmarks[start].x) * size.width,
                y: CGFloat(landmarks[start].y) * size.height
            )
            let endPoint = CGPoint(
                x: CGFloat(landmarks[end].x) * size.width,
                y: CGFloat(landmarks[end].y) * size.height
            )
            path.move(to: startPoint)
            path.addLine(to: endPoint)
        }
        
        return path
    }
}

// MARK: - View Mode Button

struct ViewModeButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.blue : Color.white.opacity(0.1))
            .foregroundColor(isSelected ? .white : .gray)
            .clipShape(Capsule())
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
