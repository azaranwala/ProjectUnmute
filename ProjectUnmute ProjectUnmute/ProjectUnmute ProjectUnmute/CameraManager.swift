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
        
        // Stop current streaming
        stopStreaming()
        metaGlassesSubscriptions.removeAll()
        
        cameraSource = source
        
        // Always start streaming when switching cameras
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
        
        sessionQueue.async { [weak self] in
            self?.setupCaptureSession()
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
        MetaGlassesCameraManager.shared.stopStreaming()
    }
    
    // MARK: - Meta Glasses Streaming via MWDAT SDK
    
    private func setupMetaGlassesStreaming() {
        print("🕶️ Starting Meta Glasses streaming via MWDAT SDK...")
        
        Task { @MainActor in
            let metaManager = MetaGlassesCameraManager.shared
            
            // Start streaming from Meta Glasses
            await metaManager.startStreaming()
            
            // Forward frames to our currentFrame property
            // This uses Combine to observe MetaGlassesCameraManager's frame updates
            metaManager.$currentFrame
                .receive(on: DispatchQueue.main)
                .sink { [weak self] frame in
                    self?.currentFrame = frame
                }
                .store(in: &metaGlassesSubscriptions)
            
            metaManager.$state
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    self?.state = state
                }
                .store(in: &metaGlassesSubscriptions)
            
            metaManager.$frameRate
                .receive(on: DispatchQueue.main)
                .sink { [weak self] rate in
                    self?.frameRate = rate
                }
                .store(in: &metaGlassesSubscriptions)
        }
    }
    
    private var metaGlassesSubscriptions = Set<AnyCancellable>()
    
    private func setupCaptureSession() {
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
        case .iPhoneBack:
            camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
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
            DispatchQueue.main.async {
                self.state = .error("Camera not available: \(self.cameraSource.rawValue)")
            }
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            
            if session.canAddInput(input) {
                session.addInput(input)
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
            }
            
            self.captureSession = session
            self.videoOutput = output
            
            // Create preview layer
            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            
            DispatchQueue.main.async {
                self.previewLayer = layer
            }
            
            // Start running
            session.startRunning()
            
            DispatchQueue.main.async {
                self.state = .streaming
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
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Remove existing layers
        uiView.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        
        if let previewLayer = previewLayer {
            previewLayer.frame = uiView.bounds
            uiView.layer.addSublayer(previewLayer)
        }
    }
}
