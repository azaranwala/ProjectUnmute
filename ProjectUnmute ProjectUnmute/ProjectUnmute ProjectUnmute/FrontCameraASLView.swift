import SwiftUI
import AVFoundation
import os.log

#if !targetEnvironment(macCatalyst)
import MediaPipeTasksVision
#endif

/// Thread-safe state for processing callbacks
final class ProcessingState: @unchecked Sendable {
    private let lock = NSLock()
    private var _lastProcessTime: Date = .distantPast
    private var _timestampMs: Int = 0
    
    var lastProcessTime: Date {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _lastProcessTime
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _lastProcessTime = newValue
        }
    }
    
    func incrementTimestamp(by amount: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        _timestampMs += amount
        return _timestampMs
    }
}

/// SwiftUI View for ASL detection using the iPhone front camera
struct FrontCameraASLView: View {
    @StateObject private var viewModel = FrontCameraASLViewModel()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            // Camera preview
            ASLCameraPreviewView(session: viewModel.captureSession)
                .ignoresSafeArea()
            
            // Overlay
            VStack {
                // Top bar
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundColor(.white)
                    }
                    Spacer()
                    Text("ASL Detection")
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                    // Data collection button
                    Button(action: { viewModel.isCollecting.toggle() }) {
                        Image(systemName: viewModel.isCollecting ? "record.circle.fill" : "record.circle")
                            .font(.title)
                            .foregroundColor(viewModel.isCollecting ? .red : .white)
                    }
                }
                .padding()
                .background(Color.black.opacity(0.5))
                
                // Data collection controls (when collecting)
                if viewModel.isCollecting {
                    HStack {
                        Text("Label:")
                            .foregroundColor(.white)
                        Picker("Label", selection: $viewModel.collectLabel) {
                            ForEach(["0","1","2","3","4","5","I_LOVE_YOU"], id: \.self) { label in
                                Text(label).tag(label)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 300)
                        
                        Button("Save (\(viewModel.collectedCount))") {
                            viewModel.captureSample()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        
                        Button("Export") {
                            viewModel.exportSamples()
                        }
                        .buttonStyle(.bordered)
                        .tint(.blue)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.8))
                }
                
                Spacer()
                
                // Detection result
                VStack(spacing: 10) {
                    if viewModel.isHandDetected {
                        Text(viewModel.detectedSign)
                            .font(.system(size: viewModel.detectedSign == "Unable to determine" ? 36 : 72, weight: .bold))
                            .foregroundColor(viewModel.detectedSign == "Unable to determine" ? .red : .green)
                        
                        // Confidence with threshold indicator
                        HStack(spacing: 8) {
                            Text("\(Int(viewModel.confidence * 100))%")
                                .font(.title2)
                                .foregroundColor(viewModel.confidence >= 0.70 ? .green : .red)
                            Text(viewModel.confidence >= 0.70 ? "✓" : "< 70%")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(viewModel.confidence >= 0.70 ? Color.green.opacity(0.3) : Color.red.opacity(0.3))
                                .cornerRadius(4)
                        }
                        
                        // Top 3 predictions
                        if !viewModel.topPredictions.isEmpty {
                            HStack(spacing: 20) {
                                ForEach(viewModel.topPredictions, id: \.sign) { pred in
                                    VStack {
                                        Text(pred.sign)
                                            .font(.headline)
                                        Text("\(Int(pred.confidence * 100))%")
                                            .font(.caption)
                                    }
                                    .foregroundColor(.white.opacity(0.7))
                                }
                            }
                            .padding(.top, 5)
                        }
                    } else {
                        Text("Show your hand")
                            .font(.title)
                            .foregroundColor(.white.opacity(0.6))
                        Text("Make an ASL sign in front of the camera")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
                .padding(30)
                .background(Color.black.opacity(0.7))
                .cornerRadius(20)
                .padding(.bottom, 50)
            }
        }
        .onAppear {
            viewModel.startCamera()
        }
        .onDisappear {
            viewModel.stopCamera()
        }
    }
}

/// Camera preview using AVCaptureSession (renamed to avoid conflict)
struct ASLCameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        
        DispatchQueue.main.async {
            previewLayer.frame = view.bounds
        }
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let previewLayer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            DispatchQueue.main.async {
                previewLayer.frame = uiView.bounds
            }
        }
    }
}

/// ViewModel for front camera ASL detection
@MainActor
final class FrontCameraASLViewModel: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isHandDetected = false
    @Published var detectedSign = "-"
    @Published var confidence: Float = 0
    @Published var topPredictions: [(sign: String, confidence: Float)] = []
    
    // Data collection
    @Published var isCollecting = false
    @Published var collectLabel = "0"
    @Published var collectedCount = 0
    var collectedSamples: [[Float]] = []
    var currentLandmarks: [Float] = []
    
    // MARK: - Private Properties
    
    let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let processingQueue = DispatchQueue(label: "com.projectunmute.frontcamera.processing")
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ProjectUnmute", category: "FrontCameraASL")
    
    #if !targetEnvironment(macCatalyst)
    private var handLandmarker: HandLandmarker?
    #endif
    
    private let processInterval: TimeInterval = 0.1 // Process every 100ms
    
    // Thread-safe storage for delegate callback
    private let processingState = ProcessingState()
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setupHandLandmarker()
    }
    
    // MARK: - Setup
    
    private func setupHandLandmarker() {
        #if !targetEnvironment(macCatalyst)
        guard let modelPath = Bundle.main.path(forResource: "hand_landmarker", ofType: "task") else {
            logger.error("Failed to find hand_landmarker.task")
            return
        }
        
        do {
            let options = HandLandmarkerOptions()
            options.baseOptions.modelAssetPath = modelPath
            options.runningMode = .liveStream
            options.numHands = 1
            options.minHandDetectionConfidence = 0.5
            options.minHandPresenceConfidence = 0.5
            options.minTrackingConfidence = 0.5
            options.handLandmarkerLiveStreamDelegate = self
            
            handLandmarker = try HandLandmarker(options: options)
            logger.info("HandLandmarker initialized for front camera ASL")
        } catch {
            logger.error("Failed to create HandLandmarker: \(error.localizedDescription)")
        }
        #endif
    }
    
    // MARK: - Camera Control
    
    func startCamera() {
        processingQueue.async { [weak self] in
            self?.setupCaptureSession()
        }
    }
    
    func stopCamera() {
        captureSession.stopRunning()
        logger.info("Front camera stopped")
    }
    
    private func setupCaptureSession() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .high
        
        // Get front camera
        guard let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            logger.error("Front camera not available")
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: frontCamera)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            }
            
            videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            
            if captureSession.canAddOutput(videoOutput) {
                captureSession.addOutput(videoOutput)
            }
            
            // Mirror the front camera
            if let connection = videoOutput.connection(with: .video) {
                if connection.isVideoMirroringSupported {
                    connection.isVideoMirrored = true
                }
            }
            
            captureSession.commitConfiguration()
            captureSession.startRunning()
            
            logger.info("Front camera started")
        } catch {
            logger.error("Failed to setup capture session: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Hand Processing
    
    // Confidence threshold - lowered for new exponential decay confidence formula
    private let confidenceThreshold: Float = 0.50
    
    private func processLandmarks(_ landmarks: [[Float]]) {
        guard landmarks.count == 21 else { return }
        
        // Flatten to 63 features (21 landmarks × 3 coords)
        // Training uses raw coordinates with StandardScaler
        var features: [Float] = []
        for landmark in landmarks {
            features.append(contentsOf: landmark)
        }
        
        // Store current landmarks for data collection
        Task { @MainActor in
            self.currentLandmarks = features
        }
        
        // Classify using ASLModelClassifier
        if let result = ASLModelClassifier.shared.classify(landmarks: features) {
            let topN = ASLModelClassifier.shared.classifyTopN(landmarks: features, n: 3)
            
            Task { @MainActor in
                self.isHandDetected = true
                self.confidence = result.confidence
                self.topPredictions = topN
                
                // Apply confidence threshold: >=70% shows sign, <70% shows "Do not recognize"
                if result.confidence >= 0.70 {
                    self.detectedSign = result.sign
                } else {
                    self.detectedSign = "Do not recognize"
                }
            }
        }
    }
    
    // MARK: - Data Collection
    
    func captureSample() {
        guard !currentLandmarks.isEmpty else {
            logger.warning("No landmarks to capture")
            return
        }
        
        var sample = currentLandmarks
        // We'll store the label index at the end for now
        collectedSamples.append(sample)
        collectedCount += 1
        logger.info("📸 Captured sample \(self.collectedCount) for label: \(self.collectLabel)")
        
        // Log the landmarks to console for manual copying
        let landmarkStr = currentLandmarks.map { String(format: "%.6f", $0) }.joined(separator: ",")
        print("LANDMARK_DATA:\(collectLabel),\(landmarkStr)")
    }
    
    func exportSamples() {
        // Print all collected samples in CSV format
        print("\n===== COLLECTED LANDMARKS =====")
        print("label," + (0..<63).map { "x\($0/3)_\(["x","y","z"][$0%3])" }.joined(separator: ","))
        
        for sample in collectedSamples {
            let landmarkStr = sample.map { String(format: "%.6f", $0) }.joined(separator: ",")
            print("\(collectLabel),\(landmarkStr)")
        }
        print("===== END LANDMARKS (\(collectedSamples.count) samples) =====\n")
        
        logger.info("Exported \(self.collectedSamples.count) samples to console")
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension FrontCameraASLViewModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        // Throttle processing using thread-safe state
        let now = Date()
        guard now.timeIntervalSince(processingState.lastProcessTime) >= processInterval else { return }
        processingState.lastProcessTime = now
        
        #if !targetEnvironment(macCatalyst)
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let timestamp = processingState.incrementTimestamp(by: Int(processInterval * 1000))
        
        Task { @MainActor [weak self] in
            guard let self = self, let landmarker = self.handLandmarker else { return }
            do {
                let mpImage = try MPImage(pixelBuffer: pixelBuffer)
                try landmarker.detectAsync(image: mpImage, timestampInMilliseconds: timestamp)
            } catch {
                // Silently ignore processing errors
            }
        }
        #endif
    }
}

// MARK: - HandLandmarkerLiveStreamDelegate

#if !targetEnvironment(macCatalyst)
extension FrontCameraASLViewModel: HandLandmarkerLiveStreamDelegate {
    
    nonisolated func handLandmarker(_ handLandmarker: HandLandmarker, didFinishDetection result: HandLandmarkerResult?, timestampInMilliseconds: Int, error: Error?) {
        
        guard let result = result, !result.landmarks.isEmpty else {
            Task { @MainActor in
                self.isHandDetected = false
                self.detectedSign = "-"
                self.confidence = 0
                self.topPredictions = []
            }
            return
        }
        
        // Extract landmarks from first hand
        let handLandmarks = result.landmarks[0]
        var landmarks: [[Float]] = []
        
        // Video is already mirrored (isVideoMirrored = true), so landmarks are from mirrored perspective
        // Training data was also collected from mirrored frames (cv2.flip), so NO additional X-mirroring needed
        for landmark in handLandmarks {
            landmarks.append([Float(landmark.x), Float(landmark.y), Float(landmark.z)])
        }
        
        // Process on main actor
        Task { @MainActor in
            self.processLandmarks(landmarks)
        }
    }
}
#endif

// MARK: - Preview

struct FrontCameraASLView_Previews: PreviewProvider {
    static var previews: some View {
        FrontCameraASLView()
    }
}
