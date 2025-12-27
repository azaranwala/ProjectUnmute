import SwiftUI
import UIKit
import AVFoundation
import Combine

// MARK: - Camera Source Type

enum CameraSource: String, CaseIterable {
    case iPhoneFront = "iPhone Front"
    case iPhoneBack = "iPhone Back"
    case metaGlasses = "Meta Glasses"
    case external = "External Device"
    
    var icon: String {
        switch self {
        case .iPhoneFront: return "iphone"
        case .iPhoneBack: return "iphone.rear.camera"
        case .metaGlasses: return "eyeglasses"
        case .external: return "video"
        }
    }
    
    var description: String {
        switch self {
        case .iPhoneFront: return "Use iPhone front camera"
        case .iPhoneBack: return "Use iPhone back camera"
        case .metaGlasses: return "Stream from Meta Glasses via MWDAT SDK"
        case .external: return "Use external camera device"
        }
    }
}

// MARK: - Camera Manager with Meta Glasses Support

@MainActor
class DeviceCameraManager: NSObject, ObservableObject {
    
    @Published var state: MWDATCameraState = .disconnected
    @Published var currentFrame: CGImage?
    @Published var frameRate: Double = 0.0
    @Published var previewLayer: AVCaptureVideoPreviewLayer?
    @Published var cameraSource: CameraSource = .iPhoneFront
    @Published var availableCameras: [CameraSource] = []
    @Published var externalCameraName: String?
    
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    
    private var frameCount = 0
    private var lastFrameTime = CACurrentMediaTime()
    
    override init() {
        super.init()
        discoverCameras()
    }
    
    /// Discover available cameras including Meta Glasses via MWDAT SDK
    func discoverCameras() {
        var cameras: [CameraSource] = []
        
        // Check for front camera
        if AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil {
            cameras.append(.iPhoneFront)
        }
        
        // Check for back camera
        if AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil {
            cameras.append(.iPhoneBack)
        }
        
        // Always add Meta Glasses option (uses MWDAT SDK)
        cameras.append(.metaGlasses)
        
        // Check for other external cameras
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external, .builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        )
        
        for device in discoverySession.devices {
            if device.deviceType == .external {
                cameras.append(.external)
                externalCameraName = device.localizedName
                print("📹 Found external camera: \(device.localizedName)")
            }
        }
        
        availableCameras = cameras
        print("📷 Available cameras: \(cameras.map { $0.rawValue })")
    }
    
    /// Check if running in simulator
    private var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
    
    /// Switch camera source
    func switchCamera(to source: CameraSource) {
        guard availableCameras.contains(source) else { return }
        print("🔄 Switching camera to: \(source.rawValue)")
        
        let wasUsingMetaGlasses = (cameraSource == .metaGlasses)
        
        // Stop current streaming
        stopStreaming()
        metaGlassesSubscriptions.removeAll()
        
        // Update source immediately
        cameraSource = source
        
        // If we were using Meta Glasses, clean up async but don't wait
        if wasUsingMetaGlasses {
            Task {
                await MetaGlassesCameraManager.shared.stopStreaming()
            }
        }
        
        // Start new camera immediately (don't wait for Meta cleanup)
        startStreaming()
    }
    
    func startStreaming() {
        state = .connecting
        print("📸 startStreaming() called, source: \(cameraSource.rawValue)")
        
        // Handle Meta Glasses separately - it uses MWDAT SDK on MainActor
        if cameraSource == .metaGlasses {
            print("🕶️ Meta Glasses selected, starting MWDAT streaming...")
            setupMetaGlassesStreaming()
            return
        }
        
        // Simulator doesn't have a camera - show simulator mode
        if isSimulator {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.state = .streaming
                self?.startSimulatorMode()
            }
            return
        }
        
        // Check camera permission first
        checkCameraPermission { [weak self] granted in
            guard let self = self else { return }
            if granted {
                self.sessionQueue.async {
                    self.setupCaptureSession()
                }
            } else {
                DispatchQueue.main.async {
                    self.state = .error("Camera permission denied. Please enable in Settings.")
                }
            }
        }
    }
    
    private func checkCameraPermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            print("📷 Camera permission: authorized")
            completion(true)
        case .notDetermined:
            print("📷 Camera permission: requesting...")
            AVCaptureDevice.requestAccess(for: .video) { granted in
                print("📷 Camera permission result: \(granted)")
                completion(granted)
            }
        case .denied, .restricted:
            print("📷 Camera permission: denied/restricted")
            completion(false)
        @unknown default:
            completion(false)
        }
    }
    
    private func startSimulatorMode() {
        // Generate placeholder frames for simulator testing
        Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { [weak self] timer in
            guard let self = self, self.state == .streaming else {
                timer.invalidate()
                return
            }
            
            DispatchQueue.main.async {
                self.currentFrame = self.generateSimulatorFrame()
                
                // Calculate frame rate
                self.frameCount += 1
                let now = CACurrentMediaTime()
                if now - self.lastFrameTime >= 1.0 {
                    self.frameRate = Double(self.frameCount)
                    self.frameCount = 0
                    self.lastFrameTime = now
                }
            }
        }
    }
    
    private func generateSimulatorFrame() -> CGImage? {
        let size = CGSize(width: 640, height: 480)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        let image = renderer.image { context in
            // Gradient background
            let colors = [UIColor.darkGray.cgColor, UIColor.black.cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            
            // Draw camera icon
            let iconRect = CGRect(x: size.width/2 - 40, y: size.height/2 - 60, width: 80, height: 60)
            UIColor.white.withAlphaComponent(0.3).setFill()
            UIBezierPath(roundedRect: iconRect, cornerRadius: 10).fill()
            
            // Draw text
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 20, weight: .semibold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraphStyle
            ]
            
            let title = "📱 Simulator Mode"
            let titleRect = CGRect(x: 0, y: size.height/2 + 20, width: size.width, height: 30)
            title.draw(in: titleRect, withAttributes: titleAttrs)
            
            let subtitleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14, weight: .regular),
                .foregroundColor: UIColor.lightGray,
                .paragraphStyle: paragraphStyle
            ]
            
            let subtitle = "Run on real iPhone for camera"
            let subtitleRect = CGRect(x: 0, y: size.height/2 + 50, width: size.width, height: 25)
            subtitle.draw(in: subtitleRect, withAttributes: subtitleAttrs)
            
            // FPS counter
            let fpsAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: UIColor.green
            ]
            let fpsText = String(format: "%.0f FPS", self.frameRate)
            fpsText.draw(at: CGPoint(x: 10, y: 10), withAttributes: fpsAttrs)
        }
        
        return image.cgImage
    }
    
    func stopStreaming() {
        sessionQueue.async { [weak self] in
            self?.captureSession?.stopRunning()
            DispatchQueue.main.async {
                self?.state = .disconnected
                self?.currentFrame = nil
                self?.frameRate = 0
                self?.previewLayer = nil
            }
        }
    }
    
    func stop() {
        stopStreaming()
        Task {
            await MetaGlassesCameraManager.shared.stopStreaming()
        }
    }
    
    // MARK: - Meta Glasses Streaming via MWDAT SDK
    
    private func setupMetaGlassesStreaming() {
        print("🕶️ Starting Meta Glasses streaming via MWDAT SDK...")
        
        // IMPORTANT: Clear previewLayer so MWDATVideoView is used instead of CameraPreviewView
        self.previewLayer = nil
        
        let metaManager = MetaGlassesCameraManager.shared
        
        // Set up subscriptions FIRST (before starting stream) so we don't miss any frames
        metaGlassesSubscriptions.removeAll()
        
        metaManager.$currentFrame
            .receive(on: DispatchQueue.main)
            .sink { [weak self] frame in
                if let frame = frame {
                    print("📺 Frame forwarded to UI: \(frame.width)x\(frame.height)")
                }
                self?.currentFrame = frame
            }
            .store(in: &metaGlassesSubscriptions)
        
        metaManager.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                print("📺 State forwarded to UI: \(state)")
                self?.state = state
            }
            .store(in: &metaGlassesSubscriptions)
        
        metaManager.$frameRate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] rate in
                self?.frameRate = rate
            }
            .store(in: &metaGlassesSubscriptions)
        
        print("📺 Meta Glasses subscriptions set up, previewLayer: \(String(describing: self.previewLayer))")
        
        // Now start streaming
        Task { @MainActor in
            await metaManager.startStreaming()
        }
    }
    
    private var metaGlassesSubscriptions = Set<AnyCancellable>()
    
    private func setupCaptureSession() {
        print("📷 setupCaptureSession() called for: \(cameraSource.rawValue)")
        
        // Handle Meta Glasses separately via MWDAT SDK
        if cameraSource == .metaGlasses {
            setupMetaGlassesStreaming()
            return
        }
        
        let session = AVCaptureSession()
        session.sessionPreset = .high
        
        // Get camera based on selected source
        var camera: AVCaptureDevice?
        
        switch cameraSource {
        case .iPhoneFront:
            camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            print("📷 Looking for front camera: \(camera != nil ? "found" : "NOT FOUND")")
        case .iPhoneBack:
            camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            print("📷 Looking for back camera: \(camera != nil ? "found" : "NOT FOUND")")
        case .metaGlasses:
            // Handled above
            return
        case .external:
            // Look for other external camera devices
            let discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.external],
                mediaType: .video,
                position: .unspecified
            )
            camera = discoverySession.devices.first
            if let extCamera = camera {
                print("📹 Using external camera: \(extCamera.localizedName)")
            }
        }
        
        guard let camera = camera else {
            print("❌ Camera not found for: \(cameraSource.rawValue)")
            DispatchQueue.main.async {
                self.state = .error("Camera not available: \(self.cameraSource.rawValue)")
            }
            return
        }
        
        print("📷 Camera found: \(camera.localizedName)")
        
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            print("📷 Created capture input")
            
            if session.canAddInput(input) {
                session.addInput(input)
                print("📷 Added input to session")
            } else {
                print("❌ Cannot add input to session")
            }
            
            // Setup video output
            let output = AVCaptureVideoDataOutput()
            output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "camera.frame.queue"))
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            
            if session.canAddOutput(output) {
                session.addOutput(output)
                print("📷 Added output to session")
            } else {
                print("❌ Cannot add output to session")
            }
            
            self.captureSession = session
            self.videoOutput = output
            
            // Create preview layer on main thread
            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            print("📷 Created preview layer")
            
            // Start running BEFORE setting UI state
            session.startRunning()
            print("📷 Session started running: \(session.isRunning)")
            
            DispatchQueue.main.async {
                self.previewLayer = layer
                self.state = .streaming
                print("📷 Preview layer set, state = streaming")
            }
            
        } catch {
            DispatchQueue.main.async {
                self.state = .error(error.localizedDescription)
            }
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension DeviceCameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.currentFrame = cgImage
            
            // Calculate frame rate
            self.frameCount += 1
            let now = CACurrentMediaTime()
            if now - self.lastFrameTime >= 1.0 {
                self.frameRate = Double(self.frameCount)
                self.frameCount = 0
                self.lastFrameTime = now
            }
        }
    }
}

// MARK: - Camera Preview View

struct CameraPreviewView: UIViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer?
    
    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.backgroundColor = .black
        view.previewLayer = previewLayer
        return view
    }
    
    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        uiView.previewLayer = previewLayer
    }
}

/// Custom UIView that properly handles AVCaptureVideoPreviewLayer frame updates
class CameraPreviewUIView: UIView {
    var previewLayer: AVCaptureVideoPreviewLayer? {
        didSet {
            // Remove old layer
            oldValue?.removeFromSuperlayer()
            
            // Add new layer
            if let newLayer = previewLayer {
                newLayer.videoGravity = .resizeAspectFill
                newLayer.frame = bounds
                layer.insertSublayer(newLayer, at: 0)
            }
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        // Update preview layer frame when view bounds change
        previewLayer?.frame = bounds
    }
}
