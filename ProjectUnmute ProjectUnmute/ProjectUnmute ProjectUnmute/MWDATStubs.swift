import SwiftUI
import UIKit
import AVFoundation
import Combine
import MWDATCore
import MWDATCamera

// MARK: - Meta Wearables Device Access Toolkit Integration
// Official SDK: https://github.com/facebook/meta-wearables-dat-ios
// Documentation: https://wearables.developer.meta.com/docs/develop/

// MARK: - Camera State

enum MWDATCameraState: Equatable {
    case disconnected
    case connecting
    case streaming
    case error(String)
    
    var description: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .streaming: return "Streaming"
        case .error(let msg): return "Error: \(msg)"
        }
    }
}

// MARK: - Meta Glasses Connection Status

enum MetaGlassesStatus: String {
    case notPaired = "Not Paired"
    case paired = "Paired"
    case connected = "Connected"
    case streaming = "Streaming"
    case error = "Error"
    
    var color: Color {
        switch self {
        case .notPaired: return .gray
        case .paired: return .yellow
        case .connected: return .blue
        case .streaming: return .green
        case .error: return .red
        }
    }
}

// MARK: - Meta Glasses Camera Manager

/// Camera manager that integrates with Meta Wearables Device Access Toolkit
/// Add SDK via: File > Add Package Dependencies > https://github.com/facebook/meta-wearables-dat-ios
@MainActor
class MetaGlassesCameraManager: ObservableObject {
    
    static let shared = MetaGlassesCameraManager()
    
    // MARK: - Published Properties
    
    @Published var state: MWDATCameraState = .disconnected
    @Published var glassesStatus: MetaGlassesStatus = .notPaired
    @Published var currentFrame: CGImage?
    @Published var frameRate: Double = 0.0
    @Published var isSDKAvailable: Bool = true
    @Published var glassesName: String = "Meta Glasses"
    @Published var batteryLevel: Int = 0
    @Published var isAuthorized: Bool = false
    @Published var statusMessage: String = "Tap Start Streaming"
    
    // MARK: - Private Properties
    
    private var frameCount = 0
    private var lastFrameTime = CACurrentMediaTime()
    private var streamingTask: Task<Void, Never>?
    
    // MWDAT SDK objects
    private var deviceSelector: AutoDeviceSelector?
    private var streamSession: StreamSession?
    private var frameListenerToken: (any AnyListenerToken)?
    private var stateListenerToken: (any AnyListenerToken)?
    
    // MARK: - Initialization
    
    private init() {
        print("✅ Meta Wearables SDK is available (MWDATCamera, MWDATCore)")
        // Configure Wearables SDK on init
        do {
            try Wearables.configure()
            print("✅ Wearables.configure() succeeded")
        } catch {
            print("⚠️ Wearables.configure() failed: \(error)")
        }
    }
    
    // MARK: - Connection Methods
    
    /// Start video streaming from Meta Glasses
    func startStreaming() async {
        // Prevent multiple simultaneous start attempts
        guard state != .streaming && state != .connecting else {
            print("ℹ️ Already streaming or connecting, skipping startStreaming()")
            return
        }
        
        state = .connecting
        glassesStatus = .paired
        print("🕶️ Starting Meta Glasses streaming...")
        
        do {
            // Get Wearables interface
            let wearablesInterface = Wearables.shared
            print("✅ Got Wearables.shared")
            
            // Check registration state
            let regState = wearablesInterface.registrationState
            print("📋 Registration state: \(regState)")
            
            // If not registered, start registration flow
            if regState == .unavailable || regState == .available {
                print("🔑 Starting registration flow...")
                do {
                    try wearablesInterface.startRegistration()
                    print("✅ Registration started - Meta AI app should open")
                    print("⏳ Please approve the app in Meta AI, then come back")
                    
                    // Wait a moment for registration to complete
                    try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                    
                    let newState = wearablesInterface.registrationState
                    print("📋 New registration state: \(newState)")
                } catch {
                    print("⚠️ Registration error: \(error)")
                }
            }
            
            // Request camera permission after registration
            print("🔐 Requesting camera permission...")
            var cameraPermissionGranted = false
            do {
                let permStatus = try await wearablesInterface.requestPermission(.camera)
                print("✅ Camera permission status: \(permStatus)")
                cameraPermissionGranted = (permStatus == .granted)
                
                if permStatus != .granted {
                    print("⚠️ Camera permission not granted: \(permStatus)")
                    print("💡 Open Meta AI app → Settings → Connected Apps → ProjectUnmute → Enable Camera")
                    statusMessage = "⚠️ Grant camera permission in Meta AI app"
                }
            } catch {
                print("⚠️ Camera permission error: \(error)")
                print("💡 This may be a known SDK issue. Try:")
                print("   1. Open Meta AI app")
                print("   2. Go to Settings → Connected Apps → ProjectUnmute")
                print("   3. Manually enable Camera permission")
                print("   4. Return to this app and try again")
                statusMessage = "⚠️ Enable camera in Meta AI → Settings → Connected Apps"
                
                // Don't return - try to continue, permission might already be granted in Meta AI
            }
            
            // Check available devices
            let devices = wearablesInterface.devices
            print("📱 Available devices: \(devices)")
            
            if devices.isEmpty {
                print("⚠️ No Meta Glasses found! Make sure glasses are paired in Meta View app.")
                glassesStatus = .notPaired
                state = .error("No glasses found. Pair in Meta View app.")
                return
            }
            
            // Create device selector (auto-selects connected glasses)
            print("🔍 Creating AutoDeviceSelector...")
            deviceSelector = AutoDeviceSelector(wearables: wearablesInterface)
            print("✅ AutoDeviceSelector created")
            
            // Wait briefly for device to be selected
            var retryCount = 0
            while deviceSelector?.activeDevice == nil && retryCount < 5 {
                print("⏳ Waiting for device selection... (\(retryCount + 1)/5)")
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                retryCount += 1
            }
            
            if let activeDevice = deviceSelector?.activeDevice {
                print("🕶️ Active device: \(activeDevice)")
                glassesName = "Ray-Ban Meta"
            } else {
                print("⚠️ No active device selected after waiting")
                print("💡 Make sure glasses are connected via Bluetooth and Meta View app")
            }
            
            // Create stream session with config
            let config = StreamSessionConfig()
            print("🎥 Creating StreamSession (resolution: \(config.resolution), frameRate: \(config.frameRate))...")
            streamSession = StreamSession(streamSessionConfig: config, deviceSelector: deviceSelector!)
            print("✅ StreamSession created")
            
            // Listen for video frames
            frameListenerToken = streamSession!.videoFramePublisher.listen { [weak self] frame in
                Task { @MainActor in
                    self?.handleFrame(frame)
                }
            }
            
            // Listen for state changes
            stateListenerToken = streamSession!.statePublisher.listen { [weak self] sessionState in
                Task { @MainActor in
                    self?.handleStateChange(sessionState)
                }
            }
            
            // Start streaming
            print("▶️ Starting stream session...")
            await streamSession!.start()
            
            // Don't set state to streaming yet - wait for actual frames via handleStateChange
            state = .connecting
            glassesStatus = .paired
            glassesName = "Ray-Ban Meta"
            statusMessage = "Waiting for glasses camera... Tap temple to activate"
            print("⏳ Stream session started, waiting for glasses to send frames...")
            print("💡 TIP: Put glasses on, tap the temple to wake camera")
            
        } catch {
            state = .error("Streaming failed: \(error.localizedDescription)")
            glassesStatus = .error
            print("❌ Streaming error: \(error)")
            
            // Fall back to simulation for testing
            print("📱 Falling back to simulation mode...")
            await startSimulatedStreaming()
        }
    }
    
    /// Stop video streaming
    func stopStreaming() async {
        print("⏹ Stopping Meta Glasses streaming...")
        
        // Cancel listeners first
        await frameListenerToken?.cancel()
        await stateListenerToken?.cancel()
        
        // Stop the stream session
        await streamSession?.stop()
        
        // Cancel any background tasks
        streamingTask?.cancel()
        streamingTask = nil
        
        // Clear references
        streamSession = nil
        deviceSelector = nil
        frameListenerToken = nil
        stateListenerToken = nil
        
        // Reset state
        state = .disconnected
        glassesStatus = .connected
        currentFrame = nil
        frameRate = 0
        isAuthorized = false  // Reset so user can re-authorize if needed
        
        print("⏹ Stopped streaming")
    }
    
    /// Force restart streaming (stop then start)
    func restartStreaming() async {
        print("🔄 Restarting Meta Glasses streaming...")
        await stopStreaming()
        try? await Task.sleep(nanoseconds: 500_000_000)  // Brief pause
        await startStreaming()
    }
    
    /// Open Meta AI app for authorization
    func openMetaAIForAuthorization() async {
        // Prevent multiple authorization attempts
        guard !isAuthorized else {
            print("ℹ️ Already authorized, skipping")
            return
        }
        
        print("🔗 Opening Meta AI for authorization...")
        
        let wearables = Wearables.shared
        let regState = wearables.registrationState
        print("📋 Current registration state: \(regState)")
        
        // Check if already registered
        if regState == .registered {
            print("✅ Already registered! Requesting camera permission...")
            
            // Request camera permission through SDK
            do {
                let permStatus = try await wearables.requestPermission(.camera)
                print("📷 Camera permission result: \(permStatus)")
                
                if permStatus == .granted {
                    isAuthorized = true
                    if state != .streaming {
                        print("✅ Camera permission granted! Starting stream...")
                        await startStreaming()
                    } else {
                        print("ℹ️ Already streaming, permission confirmed")
                    }
                } else {
                    print("⚠️ Camera permission not granted: \(permStatus)")
                    print("💡 You may need to grant camera permission in Meta AI app settings")
                }
            } catch {
                print("❌ Camera permission error: \(error)")
            }
            return
        }
        
        // Not registered - start registration flow
        // The SDK's startRegistration() will open Meta AI automatically
        print("🔄 Starting SDK registration flow...")
        do {
            try wearables.startRegistration()
            print("✅ Registration flow started - Meta AI should open")
            print("📱 Please approve the app in Meta AI, then return here")
        } catch {
            print("❌ Registration error: \(error)")
            
            // Only try manual URL schemes if SDK registration fails
            print("🔄 Trying manual Meta AI launch...")
            await openMetaAIManually()
        }
    }
    
    /// Manually open Meta AI app (fallback)
    private func openMetaAIManually() async {
        // Prioritize Meta AI and Meta View apps, NOT Messenger
        let metaAIURLs = [
            "fb-viewapp://",           // Meta View app (manages glasses)
            "meta-ai://",              // Meta AI app
            "fb://profile",            // Facebook app
        ]
        
        for urlString in metaAIURLs {
            if let url = URL(string: urlString) {
                if UIApplication.shared.canOpenURL(url) {
                    print("📱 Opening: \(urlString)")
                    UIApplication.shared.open(url, options: [:]) { success in
                        print(success ? "✅ Opened \(urlString)" : "❌ Failed to open \(urlString)")
                    }
                    return
                }
            }
        }
        
        // If no Meta app available, show App Store for Meta View
        print("⚠️ Meta AI/View app not found, opening App Store...")
        if let appStoreURL = URL(string: "itms-apps://apps.apple.com/app/id1454921774") { // Meta View app
            UIApplication.shared.open(appStoreURL, options: [:]) { _ in }
        }
    }
    
    // MARK: - Frame Handling
    
    private func handleFrame(_ frame: VideoFrame) {
        // Log frame reception
        print("🎬 Frame received!")
        
        // VideoFrame has makeUIImage() method
        if let uiImage = frame.makeUIImage() {
            print("🖼️ UIImage created: \(uiImage.size)")
            if let cgImage = uiImage.cgImage {
                self.currentFrame = cgImage
                updateFrameRate()
                print("✅ Frame displayed, FPS: \(frameRate)")
            } else {
                print("⚠️ Failed to get CGImage from UIImage")
            }
        } else {
            print("⚠️ Failed to create UIImage from VideoFrame")
        }
    }
    
    private func handleStateChange(_ sessionState: StreamSessionState) {
        print("📊 Stream state: \(sessionState)")
        switch sessionState {
        case .streaming:
            state = .streaming
            glassesStatus = .streaming
            statusMessage = "Streaming from Meta Glasses"
        case .stopped, .stopping:
            state = .disconnected
            glassesStatus = .connected
            statusMessage = "Streaming stopped"
        case .waitingForDevice:
            state = .connecting
            glassesStatus = .paired
            statusMessage = "👓 Tap glasses temple to start camera"
            print("💡 Glasses connected but camera not active. User must tap temple to wake camera.")
        case .starting:
            state = .connecting
            statusMessage = "Starting stream..."
        case .paused:
            glassesStatus = .connected
            statusMessage = "⏸️ Stream paused - tap temple to resume"
            print("⏸️ Stream paused! Tap glasses temple to resume, or take them off/put on to restart.")
        @unknown default:
            break
        }
    }
    
    private func updateFrameRate() {
        frameCount += 1
        let now = CACurrentMediaTime()
        if now - lastFrameTime >= 1.0 {
            frameRate = Double(frameCount)
            frameCount = 0
            lastFrameTime = now
        }
    }
    
    // MARK: - Simulation (when SDK not available)
    
    private func simulateConnection() async {
        // Simulate connection delay
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        glassesStatus = .connected
        glassesName = "Ray-Ban Meta (Simulated)"
        batteryLevel = 85
        print("🕶️ Simulated Meta Glasses connection")
    }
    
    private func startSimulatedStreaming() async {
        state = .streaming
        glassesStatus = .streaming
        
        streamingTask = Task {
            while !Task.isCancelled && state == .streaming {
                await MainActor.run {
                    self.currentFrame = self.generateSimulatorFrame()
                    self.updateFrameRate()
                }
                try? await Task.sleep(nanoseconds: 33_333_333) // ~30 FPS
            }
        }
    }
    
    private func generateSimulatorFrame() -> CGImage? {
        let size = CGSize(width: 1280, height: 720)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        let image = renderer.image { context in
            // Gradient background
            let colors = [UIColor.darkGray.cgColor, UIColor.black.cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            
            // Glasses icon
            let iconRect = CGRect(x: size.width/2 - 60, y: size.height/2 - 80, width: 120, height: 80)
            UIColor.white.withAlphaComponent(0.2).setFill()
            UIBezierPath(roundedRect: iconRect, cornerRadius: 20).fill()
            
            // Title
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 28, weight: .bold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraphStyle
            ]
            
            let title = "🕶️ Meta Glasses"
            let titleRect = CGRect(x: 0, y: size.height/2 + 20, width: size.width, height: 40)
            title.draw(in: titleRect, withAttributes: titleAttrs)
            
            // Subtitle
            let subtitleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 18, weight: .medium),
                .foregroundColor: UIColor.orange,
                .paragraphStyle: paragraphStyle
            ]
            
            let sdkStatus = self.isSDKAvailable ? "SDK Ready" : "SDK Not Installed"
            let subtitle = "Simulation Mode - \(sdkStatus)"
            let subtitleRect = CGRect(x: 0, y: size.height/2 + 65, width: size.width, height: 30)
            subtitle.draw(in: subtitleRect, withAttributes: subtitleAttrs)
            
            // Instructions
            let instrAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14, weight: .regular),
                .foregroundColor: UIColor.lightGray,
                .paragraphStyle: paragraphStyle
            ]
            
            let instructions = "Add SDK: File > Add Package Dependencies\nhttps://github.com/facebook/meta-wearables-dat-ios"
            let instrRect = CGRect(x: 0, y: size.height/2 + 100, width: size.width, height: 50)
            instructions.draw(in: instrRect, withAttributes: instrAttrs)
            
            // FPS counter
            let fpsAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium),
                .foregroundColor: UIColor.green
            ]
            let fpsText = String(format: "%.0f FPS", self.frameRate)
            fpsText.draw(at: CGPoint(x: 15, y: 15), withAttributes: fpsAttrs)
            
            // Status badge
            let statusAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: UIColor.white,
                .backgroundColor: UIColor.orange
            ]
            let statusText = " SIMULATION "
            statusText.draw(at: CGPoint(x: size.width - 100, y: 15), withAttributes: statusAttrs)
        }
        
        return image.cgImage
    }
}

// MARK: - Video View

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
        }
    }
}

// MARK: - Meta Glasses Status View

struct MetaGlassesStatusView: View {
    @ObservedObject var manager = MetaGlassesCameraManager.shared
    @State private var isConnecting = false
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                // Connection indicator
                Circle()
                    .fill(manager.glassesStatus.color)
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 1)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(manager.glassesName)
                        .font(.caption.bold())
                        .foregroundColor(.white)
                    
                    Text(manager.state.description)
                        .font(.caption2)
                        .foregroundColor(manager.glassesStatus.color)
                }
                
                Spacer()
                
                // Frame rate
                if manager.frameRate > 0 {
                    Text(String(format: "%.0f FPS", manager.frameRate))
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.2))
                        .cornerRadius(4)
                }
                
                // Connect button - show if no frames received (frameRate == 0)
                if manager.frameRate == 0 {
                    Button(action: {
                        isConnecting = true
                        Task {
                            await manager.openMetaAIForAuthorization()
                            isConnecting = false
                        }
                    }) {
                        HStack(spacing: 4) {
                            if isConnecting {
                                ProgressView()
                                    .scaleEffect(0.7)
                            }
                            Text("Authorize")
                        }
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.blue)
                        .cornerRadius(6)
                    }
                    .disabled(isConnecting)
                }
            }
            
            // Instructions - show if no frames received
            if manager.frameRate == 0 {
                VStack(spacing: 4) {
                    Text("Tap 'Authorize' to open Meta AI and approve access")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    Text("Then return to this app")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
                .multilineTextAlignment(.center)
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.8))
        .cornerRadius(10)
    }
}
