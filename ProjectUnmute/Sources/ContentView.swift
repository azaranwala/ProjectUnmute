import SwiftUI
import AVKit
import WearablesDeviceAccessToolkit

// MARK: - ContentView

struct ContentView: View {
    @StateObject private var cameraManager = MWDATCameraManager()
    @StateObject private var gestureManager = GestureRecognitionManager()
    @StateObject private var speechManager = SpeechRecognitionManager()
    @StateObject private var avatarManager = AvatarVideoManager()
    
    @State private var showAvatarView = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
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
            .navigationTitle("Project Unmute")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    micButton
                }
                ToolbarItem(placement: .topBarTrailing) {
                    connectionButton
                }
            }
            .onChange(of: speechManager.matchedAvatarVideo) { _, videoName in
                if let name = videoName {
                    avatarManager.playVideo(for: name)
                }
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
                // Avatar video view
                AvatarVideoPlayer(videoName: avatarManager.currentVideoName)
                    .aspectRatio(16/9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding()
            } else {
                // Live video feed with gesture overlay
                ZStack {
                    MWDATVideoView(frame: cameraManager.currentFrame)
                        .aspectRatio(16/9, contentMode: .fit)
                    
                    // Hand landmarks overlay
                    if !gestureManager.detectedGestures.isEmpty {
                        HandLandmarksOverlay(gestures: gestureManager.detectedGestures)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding()
            }
            
            // Speech transcription display
            TranscriptionView(
                text: speechManager.transcribedText,
                lastWord: speechManager.lastRecognizedWord,
                isListening: speechManager.isListening
            )
            .padding(.horizontal)
            
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

// MARK: - Camera Manager

@MainActor
final class MWDATCameraManager: ObservableObject {
    
    enum StreamState: Equatable {
        case disconnected
        case connecting
        case streaming
        case error(String)
    }
    
    @Published private(set) var state: StreamState = .disconnected
    @Published private(set) var currentFrame: CGImage?
    @Published private(set) var frameRate: Double = 0
    
    private var cameraAccess: CameraAccess?
    private var frameCount: Int = 0
    private var lastFrameTime: Date = .now
    
    init() {
        // CameraAccess is initialized when streaming starts
    }
    
    func startStreaming() {
        guard state != .streaming && state != .connecting else { return }
        
        state = .connecting
        
        Task {
            do {
                // Initialize camera access from Meta Wearables SDK
                cameraAccess = try await CameraAccess()
                
                // Start the video stream with frame handler
                try await cameraAccess?.startStreaming { [weak self] frame in
                    Task { @MainActor in
                        self?.handleFrame(frame)
                    }
                }
                
                state = .streaming
            } catch {
                state = .error(error.localizedDescription)
            }
        }
    }
    
    func stopStreaming() {
        Task {
            await cameraAccess?.stopStreaming()
            cameraAccess = nil
            state = .disconnected
            currentFrame = nil
            frameRate = 0
        }
    }
    
    private func handleFrame(_ frame: CameraFrame) {
        // Convert CameraFrame to CGImage for display
        // The actual API may provide CMSampleBuffer, CVPixelBuffer, or CGImage
        currentFrame = frame.cgImage
        
        // Calculate frame rate
        frameCount += 1
        let now = Date.now
        let elapsed = now.timeIntervalSince(lastFrameTime)
        if elapsed >= 1.0 {
            frameRate = Double(frameCount) / elapsed
            frameCount = 0
            lastFrameTime = now
        }
    }
}

// MARK: - Video View (UIKit bridge)

struct MWDATVideoView: UIViewRepresentable {
    let frame: CGImage?
    
    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .black
        return imageView
    }
    
    func updateUIView(_ uiView: UIImageView, context: Context) {
        if let cgImage = frame {
            uiView.image = UIImage(cgImage: cgImage)
        } else {
            uiView.image = nil
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
