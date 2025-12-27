import Foundation
import UIKit
import AVFoundation
import os.log

#if !targetEnvironment(macCatalyst)
import MediaPipeTasksVision
#endif

// MARK: - Hand Landmark

/// Represents one of 21 hand landmarks detected by MediaPipe
struct HandLandmark: Identifiable {
    let id: Int
    let name: String
    let x: Float      // Normalized [0, 1] by image width
    let y: Float      // Normalized [0, 1] by image height
    let z: Float      // Depth relative to wrist
    
    // World coordinates (real-world 3D in meters)
    let worldX: Float?
    let worldY: Float?
    let worldZ: Float?
    
    /// The 21 MediaPipe hand landmark names
    static let landmarkNames: [String] = [
        "WRIST",
        "THUMB_CMC", "THUMB_MCP", "THUMB_IP", "THUMB_TIP",
        "INDEX_FINGER_MCP", "INDEX_FINGER_PIP", "INDEX_FINGER_DIP", "INDEX_FINGER_TIP",
        "MIDDLE_FINGER_MCP", "MIDDLE_FINGER_PIP", "MIDDLE_FINGER_DIP", "MIDDLE_FINGER_TIP",
        "RING_FINGER_MCP", "RING_FINGER_PIP", "RING_FINGER_DIP", "RING_FINGER_TIP",
        "PINKY_MCP", "PINKY_PIP", "PINKY_DIP", "PINKY_TIP"
    ]
    
    // Landmark indices for easy access
    static let wrist = 0
    static let thumbTip = 4
    static let indexMCP = 5
    static let indexPIP = 6
    static let indexDIP = 7
    static let indexTip = 8
    static let middleMCP = 9
    static let middlePIP = 10
    static let middleTip = 12
    static let ringMCP = 13
    static let ringPIP = 14
    static let ringTip = 16
    static let pinkyMCP = 17
    static let pinkyPIP = 18
    static let pinkyTip = 20
}

// MARK: - Finger Extension Analyzer

/// Analyzes finger extension state from hand landmarks
/// Supports both image coordinates (normalized 0-1) and world coordinates (meters)
struct FingerExtensionAnalyzer {
    
    // MARK: - Adaptive Thresholds
    
    /// Determines if landmarks are world coordinates (meters) vs image coordinates (normalized)
    private static func isWorldCoordinates(_ landmarks: [HandLandmark]) -> Bool {
        guard let first = landmarks.first else { return false }
        return first.worldX != nil
    }
    
    /// Get adaptive threshold based on coordinate system
    /// World coordinates are in meters (~0.01-0.1m range), image coords are normalized (0-1)
    private static func getThreshold(forWorld: Bool, imageThreshold: Float, worldThreshold: Float) -> Float {
        return forWorld ? worldThreshold : imageThreshold
    }
    
    // MARK: - Finger Extension Detection
    
    /// Check if a finger is extended (straight) vs curled using improved 3D analysis
    /// A finger is extended if the tip is farther from the wrist than the PIP joint
    static func isFingerExtended(landmarks: [HandLandmark], tipIndex: Int, pipIndex: Int, mcpIndex: Int) -> Bool {
        guard landmarks.count == 21 else { return false }
        
        let tip = landmarks[tipIndex]
        let pip = landmarks[pipIndex]
        let mcp = landmarks[mcpIndex]
        let wrist = landmarks[HandLandmark.wrist]
        
        // Calculate distances
        let tipToPip = distance(tip, pip)
        let pipToMcp = distance(pip, mcp)
        let tipToWrist = distance(tip, wrist)
        let mcpToWrist = distance(mcp, wrist)
        
        // Method 1: Tip should be farther from wrist than MCP (finger pointing outward)
        let tipFartherThanMcp = tipToWrist > mcpToWrist * 0.9
        
        // Method 2: Finger segments should be relatively straight (tip-pip distance significant)
        let segmentsExtended = tipToPip > pipToMcp * 0.4
        
        // Method 3: For upward gestures, tip.y < pip.y (in image coords, lower Y = higher)
        // For world coords, this depends on hand orientation
        let isWorld = isWorldCoordinates(landmarks)
        let tipAbovePip = isWorld ? (tip.y > pip.y - 0.01) : (tip.y < pip.y + 0.05)
        
        // Combined check: either tip is clearly farther, or segments are extended with proper position
        return (tipFartherThanMcp && segmentsExtended) || (segmentsExtended && tipAbovePip)
    }
    
    /// Check if index finger is extended
    static func isIndexExtended(_ landmarks: [HandLandmark]) -> Bool {
        isFingerExtended(
            landmarks: landmarks,
            tipIndex: HandLandmark.indexTip,
            pipIndex: HandLandmark.indexPIP,
            mcpIndex: HandLandmark.indexMCP
        )
    }
    
    /// Check if middle finger is curled (not extended)
    static func isMiddleCurled(_ landmarks: [HandLandmark]) -> Bool {
        !isFingerExtended(
            landmarks: landmarks,
            tipIndex: HandLandmark.middleTip,
            pipIndex: HandLandmark.middlePIP,
            mcpIndex: HandLandmark.middleMCP
        )
    }
    
    /// Check if ring finger is curled
    static func isRingCurled(_ landmarks: [HandLandmark]) -> Bool {
        !isFingerExtended(
            landmarks: landmarks,
            tipIndex: HandLandmark.ringTip,
            pipIndex: HandLandmark.ringPIP,
            mcpIndex: HandLandmark.ringMCP
        )
    }
    
    /// Check if pinky finger is curled
    static func isPinkyCurled(_ landmarks: [HandLandmark]) -> Bool {
        !isFingerExtended(
            landmarks: landmarks,
            tipIndex: HandLandmark.pinkyTip,
            pipIndex: HandLandmark.pinkyPIP,
            mcpIndex: HandLandmark.pinkyMCP
        )
    }
    
    /// Check if thumb is curled (using different logic - thumb tip near palm)
    static func isThumbCurled(_ landmarks: [HandLandmark]) -> Bool {
        guard landmarks.count == 21 else { return false }
        let thumbTip = landmarks[HandLandmark.thumbTip]
        let indexMCP = landmarks[HandLandmark.indexMCP]
        let wrist = landmarks[HandLandmark.wrist]
        
        // Adaptive threshold based on coordinate system
        let isWorld = isWorldCoordinates(landmarks)
        let threshold = getThreshold(forWorld: isWorld, imageThreshold: 0.15, worldThreshold: 0.04)
        
        // Thumb is curled if tip is close to index MCP (near palm)
        let distToIndexMCP = distance(thumbTip, indexMCP)
        
        // Alternative: check if thumb tip is close to wrist (folded in)
        let distToWrist = distance(thumbTip, wrist)
        let wristToIndexMCP = distance(wrist, indexMCP)
        let thumbFoldedIn = distToWrist < wristToIndexMCP * 0.7
        
        return distToIndexMCP < threshold || thumbFoldedIn
    }
    
    // MARK: - Gesture Detection
    
    /// Detect POINTING gesture: index extended, all others curled
    static func isPointing(_ landmarks: [HandLandmark]) -> Bool {
        guard landmarks.count == 21 else { return false }
        
        let indexUp = isIndexExtended(landmarks)
        let middleCurled = isMiddleCurled(landmarks)
        let ringCurled = isRingCurled(landmarks)
        let pinkyCurled = isPinkyCurled(landmarks)
        let thumbCurled = isThumbCurled(landmarks)
        
        // Strict check: index must be up, all others curled
        return indexUp && middleCurled && ringCurled && pinkyCurled && thumbCurled
    }
    
    /// Detect THANK_YOU gesture: flat hand with all fingers extended and together
    /// ASL "Thank You" is a flat hand moving from chin outward - we detect the flat hand position
    static func isThankYou(_ landmarks: [HandLandmark]) -> Bool {
        guard landmarks.count == 21 else { return false }
        
        // All fingers should be extended
        let indexExtended = isIndexExtended(landmarks)
        let middleExtended = !isMiddleCurled(landmarks)
        let ringExtended = !isRingCurled(landmarks)
        let pinkyExtended = !isPinkyCurled(landmarks)
        
        // Thumb should be extended outward (not curled)
        let thumbExtended = !isThumbCurled(landmarks)
        
        // Check that fingers are together (tips are close to each other)
        let fingersTogether = areFingersClose(landmarks)
        
        // Check hand is relatively flat (fingertips at similar depth)
        let handIsFlat = isHandFlat(landmarks)
        
        // All fingers extended and together = flat hand for Thank You
        return indexExtended && middleExtended && ringExtended && pinkyExtended && thumbExtended && fingersTogether && handIsFlat
    }
    
    /// Check if fingertips are close together (flat hand configuration)
    private static func areFingersClose(_ landmarks: [HandLandmark]) -> Bool {
        guard landmarks.count == 21 else { return false }
        
        let indexTip = landmarks[HandLandmark.indexTip]
        let middleTip = landmarks[HandLandmark.middleTip]
        let ringTip = landmarks[HandLandmark.ringTip]
        let pinkyTip = landmarks[HandLandmark.pinkyTip]
        
        // Adaptive threshold based on coordinate system
        let isWorld = isWorldCoordinates(landmarks)
        let threshold = getThreshold(forWorld: isWorld, imageThreshold: 0.12, worldThreshold: 0.035)
        
        // Check distances between adjacent fingertips
        let indexToMiddle = distance(indexTip, middleTip)
        let middleToRing = distance(middleTip, ringTip)
        let ringToPinky = distance(ringTip, pinkyTip)
        
        // Fingers are "together" if distances are small
        return indexToMiddle < threshold && middleToRing < threshold && ringToPinky < threshold
    }
    
    /// Check if the hand is relatively flat (all fingertips at similar Z depth)
    private static func isHandFlat(_ landmarks: [HandLandmark]) -> Bool {
        guard landmarks.count == 21 else { return false }
        
        let indexTip = landmarks[HandLandmark.indexTip]
        let middleTip = landmarks[HandLandmark.middleTip]
        let ringTip = landmarks[HandLandmark.ringTip]
        let pinkyTip = landmarks[HandLandmark.pinkyTip]
        
        // Get Z coordinates (depth)
        let zValues = [indexTip.z, middleTip.z, ringTip.z, pinkyTip.z]
        let minZ = zValues.min() ?? 0
        let maxZ = zValues.max() ?? 0
        let zRange = maxZ - minZ
        
        // Adaptive threshold for Z variance
        let isWorld = isWorldCoordinates(landmarks)
        let threshold = getThreshold(forWorld: isWorld, imageThreshold: 0.08, worldThreshold: 0.025)
        
        return zRange < threshold
    }
    
    // MARK: - Utility
    
    private static func distance(_ a: HandLandmark, _ b: HandLandmark) -> Float {
        let dx = a.x - b.x
        let dy = a.y - b.y
        let dz = a.z - b.z
        return sqrt(dx*dx + dy*dy + dz*dz)
    }
    
    /// Calculate angle between three landmarks (in radians)
    /// Useful for detecting finger curl angle
    static func angle(from: HandLandmark, vertex: HandLandmark, to: HandLandmark) -> Float {
        let v1 = (from.x - vertex.x, from.y - vertex.y, from.z - vertex.z)
        let v2 = (to.x - vertex.x, to.y - vertex.y, to.z - vertex.z)
        
        let dot = v1.0 * v2.0 + v1.1 * v2.1 + v1.2 * v2.2
        let mag1 = sqrt(v1.0 * v1.0 + v1.1 * v1.1 + v1.2 * v1.2)
        let mag2 = sqrt(v2.0 * v2.0 + v2.1 * v2.1 + v2.2 * v2.2)
        
        guard mag1 > 0 && mag2 > 0 else { return 0 }
        
        let cosAngle = dot / (mag1 * mag2)
        return acos(max(-1, min(1, cosAngle)))
    }
}

// MARK: - Gesture Result

/// A detected gesture with its confidence score
struct DetectedGesture: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let score: Float
    let handedness: String   // "Left" or "Right"
    let handednessScore: Float  // Confidence of handedness classification
    let landmarks: [HandLandmark]
    let worldLandmarks: [HandLandmark]?  // World coordinates for 3D analysis
    
    /// Built-in MediaPipe gesture categories + custom gestures
    static let supportedGestures = [
        "None",
        "Closed_Fist",
        "Open_Palm",
        "Pointing_Up",
        "Thumb_Down",
        "Thumb_Up",
        "Victory",
        "ILoveYou",
        "POINTING",   // Custom: index up, others curled
        "THANK_YOU"   // Custom: flat hand, all fingers extended and together
    ]
    
    /// Whether this is a custom-detected gesture (not from MediaPipe model)
    var isCustomGesture: Bool {
        name == "POINTING" || name == "THANK_YOU"
    }
    
    static func == (lhs: DetectedGesture, rhs: DetectedGesture) -> Bool {
        lhs.name == rhs.name && lhs.handedness == rhs.handedness
    }
    
    /// Get a landmark by index with optional world coordinates
    func getLandmark(_ index: Int) -> HandLandmark? {
        guard index >= 0 && index < landmarks.count else { return nil }
        return landmarks[index]
    }
    
    /// Get world landmark by index (for 3D analysis)
    func getWorldLandmark(_ index: Int) -> HandLandmark? {
        guard let world = worldLandmarks, index >= 0 && index < world.count else { return nil }
        return world[index]
    }
}

// MARK: - Gesture Processor Delegate

protocol HandGestureProcessorDelegate: AnyObject {
    func handGestureProcessor(_ processor: HandGestureProcessor, didDetectGestures gestures: [DetectedGesture])
    func handGestureProcessor(_ processor: HandGestureProcessor, didFailWithError error: Error)
}

// MARK: - Hand Gesture Processor

#if targetEnvironment(macCatalyst)
// MARK: - Mac Catalyst Stub (MediaPipe not supported)

/// Stub processor for Mac Catalyst (MediaPipe not available)
final class HandGestureProcessor: NSObject {
    weak var delegate: HandGestureProcessorDelegate?
    var minGestureConfidence: Float = 0.5
    var maxHands: Int = 2
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ProjectUnmute", category: "HandGestureProcessor")
    
    override init() {
        super.init()
        logger.info("HandGestureProcessor: MediaPipe not available on Mac Catalyst")
    }
    
    func processFrame(_ cgImage: CGImage, timestampMs: Int) {
        // No-op on Mac
    }
    
    func processFrame(_ pixelBuffer: CVPixelBuffer, timestampMs: Int) {
        // No-op on Mac
    }
    
    func stop() {
        logger.info("HandGestureProcessor stopped (Mac stub)")
    }
}

#else
// MARK: - iOS Implementation (with MediaPipe)

/// Processes frames from the Meta stream and detects hand gestures using MediaPipe GestureRecognizer
final class HandGestureProcessor: NSObject {
    
    // MARK: - Properties
    
    weak var delegate: HandGestureProcessorDelegate?
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ProjectUnmute", category: "HandGestureProcessor")
    
    private var gestureRecognizer: GestureRecognizer?
    private var isProcessing = false
    private let processingQueue = DispatchQueue(label: "com.projectunmute.gesture-processing", qos: .userInteractive)
    
    // MARK: - Configuration
    
    /// Minimum confidence threshold for gesture detection (0.0 - 1.0)
    var minGestureConfidence: Float = 0.6
    
    /// Minimum confidence for hand detection (0.0 - 1.0)
    var minHandDetectionConfidence: Float = 0.6
    
    /// Minimum confidence for hand presence (0.0 - 1.0)
    var minHandPresenceConfidence: Float = 0.6
    
    /// Minimum confidence for hand tracking (0.0 - 1.0)
    var minTrackingConfidence: Float = 0.6
    
    /// Number of hands to detect (1 or 2)
    var maxHands: Int = 2
    
    /// Whether to use world landmarks for 3D analysis
    var useWorldLandmarks: Bool = true
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setupGestureRecognizer()
    }
    
    // MARK: - Setup
    
    private func setupGestureRecognizer() {
        guard let modelPath = Bundle.main.path(forResource: "gesture_recognizer", ofType: "task") else {
            logger.error("Failed to find gesture_recognizer.task model in bundle")
            return
        }
        
        do {
            let options = GestureRecognizerOptions()
            options.baseOptions.modelAssetPath = modelPath
            options.runningMode = .liveStream
            options.numHands = maxHands
            
            // Enhanced detection confidence thresholds for better accuracy
            options.minHandDetectionConfidence = minHandDetectionConfidence
            options.minHandPresenceConfidence = minHandPresenceConfidence
            options.minTrackingConfidence = minTrackingConfidence
            
            // Configure canned gestures classifier for improved recognition
            let cannedGesturesOptions = ClassifierOptions()
            cannedGesturesOptions.scoreThreshold = minGestureConfidence
            cannedGesturesOptions.maxResults = 3  // Get top 3 gestures for better analysis
            options.cannedGesturesClassifierOptions = cannedGesturesOptions
            
            options.gestureRecognizerLiveStreamDelegate = self
            
            gestureRecognizer = try GestureRecognizer(options: options)
            logger.info("GestureRecognizer initialized with enhanced configuration")
            logger.info("  - Hand detection confidence: \(self.minHandDetectionConfidence)")
            logger.info("  - Hand presence confidence: \(self.minHandPresenceConfidence)")
            logger.info("  - Tracking confidence: \(self.minTrackingConfidence)")
            logger.info("  - Gesture score threshold: \(self.minGestureConfidence)")
        } catch {
            logger.error("Failed to create GestureRecognizer: \(error.localizedDescription)")
        }
    }
    
    /// Reconfigure the gesture recognizer with updated settings
    func reconfigure() {
        stop()
        setupGestureRecognizer()
    }
    
    // MARK: - Public Methods
    
    /// Process a CGImage frame from the Meta glasses stream
    /// - Parameters:
    ///   - cgImage: The frame from MWDATCamera
    ///   - timestampMs: Frame timestamp in milliseconds
    func processFrame(_ cgImage: CGImage, timestampMs: Int) {
        guard !isProcessing else {
            // Skip frame if still processing previous one
            return
        }
        
        processingQueue.async { [weak self] in
            self?.recognizeGesture(in: cgImage, timestampMs: timestampMs)
        }
    }
    
    /// Process a CVPixelBuffer frame (alternative input format)
    /// - Parameters:
    ///   - pixelBuffer: The pixel buffer frame
    ///   - timestampMs: Frame timestamp in milliseconds
    func processFrame(_ pixelBuffer: CVPixelBuffer, timestampMs: Int) {
        guard !isProcessing else { return }
        
        processingQueue.async { [weak self] in
            self?.recognizeGesture(in: pixelBuffer, timestampMs: timestampMs)
        }
    }
    
    /// Stop gesture recognition and release resources
    func stop() {
        gestureRecognizer = nil
        isProcessing = false
        logger.info("HandGestureProcessor stopped")
    }
    
    // MARK: - Private Methods
    
    private func recognizeGesture(in cgImage: CGImage, timestampMs: Int) {
        isProcessing = true
        defer { isProcessing = false }
        
        do {
            // Convert CGImage to UIImage then to MPImage
            let uiImage = UIImage(cgImage: cgImage)
            let mpImage = try MPImage(uiImage: uiImage)
            
            // Run async gesture recognition
            try gestureRecognizer?.recognizeAsync(image: mpImage, timestampInMilliseconds: timestampMs)
        } catch {
            logger.error("Gesture recognition failed: \(error.localizedDescription)")
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.handGestureProcessor(self, didFailWithError: error)
            }
        }
    }
    
    private func recognizeGesture(in pixelBuffer: CVPixelBuffer, timestampMs: Int) {
        isProcessing = true
        defer { isProcessing = false }
        
        do {
            let mpImage = try MPImage(pixelBuffer: pixelBuffer)
            try gestureRecognizer?.recognizeAsync(image: mpImage, timestampInMilliseconds: timestampMs)
        } catch {
            logger.error("Gesture recognition failed: \(error.localizedDescription)")
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.handGestureProcessor(self, didFailWithError: error)
            }
        }
    }
    
    private func parseResult(_ result: GestureRecognizerResult) -> [DetectedGesture] {
        var detectedGestures: [DetectedGesture] = []
        
        // Iterate through each detected hand
        for handIndex in 0..<result.gestures.count {
            guard handIndex < result.handedness.count,
                  handIndex < result.landmarks.count else { continue }
            
            // Get all gestures for this hand (sorted by score)
            let handGestures = result.gestures[handIndex].sorted { $0.score > $1.score }
            
            // Get the top gesture for this hand
            guard let topGesture = handGestures.first,
                  topGesture.score >= minGestureConfidence,
                  let gestureName = topGesture.categoryName,
                  gestureName != "None" else { continue }
            
            // Get handedness with confidence
            let handednessCategory = result.handedness[handIndex].first
            let handedness = handednessCategory?.categoryName ?? "Unknown"
            let handednessScore = handednessCategory?.score ?? 0.0
            
            // Parse 21 landmarks (image coordinates)
            let landmarks: [HandLandmark] = result.landmarks[handIndex].enumerated().map { index, landmark in
                HandLandmark(
                    id: index,
                    name: index < HandLandmark.landmarkNames.count ? HandLandmark.landmarkNames[index] : "UNKNOWN",
                    x: Float(landmark.x),
                    y: Float(landmark.y),
                    z: Float(landmark.z),
                    worldX: nil,
                    worldY: nil,
                    worldZ: nil
                )
            }
            
            // Parse world landmarks (real-world 3D coordinates in meters)
            var worldLandmarks: [HandLandmark]? = nil
            if useWorldLandmarks && handIndex < result.worldLandmarks.count {
                worldLandmarks = result.worldLandmarks[handIndex].enumerated().map { index, landmark in
                    HandLandmark(
                        id: index,
                        name: index < HandLandmark.landmarkNames.count ? HandLandmark.landmarkNames[index] : "UNKNOWN",
                        x: Float(landmark.x),
                        y: Float(landmark.y),
                        z: Float(landmark.z),
                        worldX: Float(landmark.x),
                        worldY: Float(landmark.y),
                        worldZ: Float(landmark.z)
                    )
                }
            }
            
            let gesture = DetectedGesture(
                name: gestureName,
                score: topGesture.score,
                handedness: handedness,
                handednessScore: handednessScore,
                landmarks: landmarks,
                worldLandmarks: worldLandmarks
            )
            detectedGestures.append(gesture)
            
            // Log additional gesture candidates for debugging
            if handGestures.count > 1 {
                let alternatives = handGestures.dropFirst().prefix(2)
                    .compactMap { g -> String? in
                        guard let name = g.categoryName else { return nil }
                        return "\(name): \(String(format: "%.2f", g.score))"
                    }
                    .joined(separator: ", ")
                logger.debug("Alternative gestures for \(handedness) hand: \(alternatives)")
            }
        }
        
        return detectedGestures
    }
}

// MARK: - GestureRecognizerLiveStreamDelegate

extension HandGestureProcessor: GestureRecognizerLiveStreamDelegate {
    
    func gestureRecognizer(
        _ gestureRecognizer: GestureRecognizer,
        didFinishRecognition result: GestureRecognizerResult?,
        timestampInMilliseconds: Int,
        error: Error?
    ) {
        if let error = error {
            logger.error("Gesture recognition error: \(error.localizedDescription)")
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.delegate?.handGestureProcessor(self, didFailWithError: error)
            }
            return
        }
        
        guard let result = result else { return }
        
        let gestures = parseResult(result)
        
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.handGestureProcessor(self, didDetectGestures: gestures)
        }
    }
}

#endif  // !targetEnvironment(macCatalyst)

// MARK: - Observable Wrapper for SwiftUI

// MARK: - Speech Synthesizer

/// Handles text-to-speech output with Bluetooth audio routing
final class SpeechSynthesizer {
    static let shared = SpeechSynthesizer()
    
    private let synthesizer = AVSpeechSynthesizer()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ProjectUnmute", category: "Speech")
    
    private init() {
        configureAudioSession()
    }
    
    /// Configure audio session to route through Bluetooth (Meta Glasses)
    private func configureAudioSession() {
        #if !targetEnvironment(macCatalyst)
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            // Allow Bluetooth output and mixing with other audio
            try audioSession.setCategory(
                .playback,
                mode: .voicePrompt,
                options: [.allowBluetooth, .allowBluetoothA2DP]
            )
            
            // Activate the session
            try audioSession.setActive(true)
            
            // Log current output route
            let currentRoute = audioSession.currentRoute
            for output in currentRoute.outputs {
                logger.info("Audio output: \(output.portName) (\(output.portType.rawValue))")
                if output.portType == .bluetoothA2DP || output.portType == .bluetoothHFP {
                    logger.info("Bluetooth device connected: \(output.portName)")
                }
            }
            
            logger.info("Audio session configured for Bluetooth output")
        } catch {
            logger.error("Failed to configure audio session: \(error.localizedDescription)")
        }
        #else
        logger.info("Audio session: Mac handles audio routing automatically")
        #endif
    }
    
    /// Speak text through the current audio route (Bluetooth if connected)
    func speak(_ text: String) {
        guard !synthesizer.isSpeaking else {
            logger.info("Already speaking, skipping: \(text)")
            return
        }
        
        // Ensure Bluetooth routing is active
        routeToBluetoothIfAvailable()
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        
        synthesizer.speak(utterance)
        logger.info("Speaking via Bluetooth: \(text)")
    }
    
    /// Try to route audio to Bluetooth device
    private func routeToBluetoothIfAvailable() {
        let audioSession = AVAudioSession.sharedInstance()
        
        // Check for available Bluetooth outputs
        guard let availableInputs = audioSession.availableInputs else { return }
        
        for input in availableInputs {
            if input.portType == .bluetoothHFP || input.portType == .bluetoothA2DP {
                do {
                    try audioSession.setPreferredInput(input)
                    logger.info("Set preferred input to Bluetooth: \(input.portName)")
                } catch {
                    logger.error("Failed to set Bluetooth input: \(error.localizedDescription)")
                }
                break
            }
        }
    }
    
    /// Check if currently connected to Bluetooth audio
    var isBluetoothConnected: Bool {
        let audioSession = AVAudioSession.sharedInstance()
        let currentRoute = audioSession.currentRoute
        
        return currentRoute.outputs.contains { output in
            output.portType == .bluetoothA2DP || output.portType == .bluetoothHFP
        }
    }
    
    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}

// MARK: - Gesture Hold Tracker

/// Tracks how long a gesture has been held continuously
final class GestureHoldTracker {
    private var currentGesture: String?
    private var holdStartTime: Date?
    private var hasTriggered = false
    
    let holdDuration: TimeInterval
    let onTrigger: (String) -> Void
    
    init(holdDuration: TimeInterval = 2.0, onTrigger: @escaping (String) -> Void) {
        self.holdDuration = holdDuration
        self.onTrigger = onTrigger
    }
    
    func update(gesture: String?) {
        if gesture == currentGesture {
            // Same gesture continuing
            if let startTime = holdStartTime, !hasTriggered {
                let elapsed = Date().timeIntervalSince(startTime)
                if elapsed >= holdDuration {
                    hasTriggered = true
                    if let g = gesture {
                        onTrigger(g)
                    }
                }
            }
        } else {
            // Gesture changed, reset tracker
            currentGesture = gesture
            holdStartTime = gesture != nil ? Date() : nil
            hasTriggered = false
        }
    }
    
    func reset() {
        currentGesture = nil
        holdStartTime = nil
        hasTriggered = false
    }
    
    var currentHoldDuration: TimeInterval {
        guard let startTime = holdStartTime else { return 0 }
        return Date().timeIntervalSince(startTime)
    }
}

// MARK: - Observable Wrapper for SwiftUI

@MainActor
final class GestureRecognitionManager: ObservableObject {
    
    @Published private(set) var detectedGestures: [DetectedGesture] = []
    @Published private(set) var isProcessing = false
    @Published private(set) var lastError: String?
    @Published private(set) var pointingHoldProgress: Double = 0  // 0 to 1 for 2 seconds
    @Published private(set) var thankYouHoldProgress: Double = 0  // 0 to 1 for 2 seconds
    @Published private(set) var didTriggerSpeech = false
    @Published private(set) var lastSpokenPhrase: String?
    @Published var speakGesturesEnabled: Bool = true  // Enable/disable TTS for gestures
    
    private let processor = HandGestureProcessor()
    private var frameCount = 0
    private var lastSpokenGesture: String?  // Track last spoken gesture to avoid repetition
    private var lastSpeakTime: Date = .distantPast  // Debounce speech
    private let speakDebounceInterval: TimeInterval = 1.5  // Minimum seconds between speaking same gesture
    
    private lazy var pointingHoldTracker = GestureHoldTracker(holdDuration: 2.0) { [weak self] gesture in
        Task { @MainActor in
            self?.handleGestureTrigger(gesture: "POINTING", phrase: "Hello")
        }
    }
    
    private lazy var thankYouHoldTracker = GestureHoldTracker(holdDuration: 2.0) { [weak self] gesture in
        Task { @MainActor in
            self?.handleGestureTrigger(gesture: "THANK_YOU", phrase: "Thank you")
        }
    }
    
    init() {
        processor.delegate = self
    }
    
    /// Process a frame from the Meta glasses camera
    func processFrame(_ cgImage: CGImage) {
        frameCount += 1
        let timestampMs = Int(Date().timeIntervalSince1970 * 1000)
        processor.processFrame(cgImage, timestampMs: timestampMs)
    }
    
    func stop() {
        processor.stop()
        detectedGestures = []
        isProcessing = false
        pointingHoldTracker.reset()
        thankYouHoldTracker.reset()
        pointingHoldProgress = 0
        thankYouHoldProgress = 0
        didTriggerSpeech = false
        lastSpokenPhrase = nil
        lastSpokenGesture = nil
    }
    
    /// Speak detected gesture through Meta Glasses speakers
    private func speakGestureIfNeeded(_ gesture: DetectedGesture) {
        guard speakGesturesEnabled else { return }
        guard gesture.score >= 0.7 else { return }  // Only speak high-confidence gestures
        
        let gestureName = gesture.name
        
        // Skip "None" or unknown gestures
        guard gestureName != "None" && gestureName != "UNKNOWN" else { return }
        
        // Debounce: don't repeat same gesture too quickly
        let now = Date()
        if gestureName == lastSpokenGesture && now.timeIntervalSince(lastSpeakTime) < speakDebounceInterval {
            return
        }
        
        // Convert gesture name to speakable text
        let speakableText = gestureToSpeakableText(gestureName)
        
        // Speak the gesture
        SpeechSynthesizer.shared.speak(speakableText)
        lastSpokenGesture = gestureName
        lastSpeakTime = now
        lastSpokenPhrase = speakableText
        didTriggerSpeech = true
        
        // Reset speech indicator after delay
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            didTriggerSpeech = false
        }
    }
    
    /// Convert gesture name to human-readable speakable text
    private func gestureToSpeakableText(_ gestureName: String) -> String {
        // Map gesture names to natural speech
        let gestureMap: [String: String] = [
            "POINTING": "Pointing",
            "THANK_YOU": "Thank you",
            "Closed_Fist": "Closed fist",
            "Open_Palm": "Open palm",
            "Victory": "Peace sign",
            "Thumb_Up": "Thumbs up",
            "Thumb_Down": "Thumbs down",
            "ILoveYou": "I love you",
            "WAVE": "Wave",
            "OK": "OK sign",
            "ROCK": "Rock on",
            "CALL": "Call me",
        ]
        
        if let mapped = gestureMap[gestureName] {
            return mapped
        }
        
        // Convert SNAKE_CASE or camelCase to readable text
        return gestureName
            .replacingOccurrences(of: "_", with: " ")
            .lowercased()
            .capitalized
    }
    
    private func handleGestureTrigger(gesture: String, phrase: String) {
        didTriggerSpeech = true
        lastSpokenPhrase = phrase
        SpeechSynthesizer.shared.speak(phrase)
        
        // Reset after a delay
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            didTriggerSpeech = false
            lastSpokenPhrase = nil
        }
    }
    
    private func updateGestureTrackers(gestures: [DetectedGesture]) {
        // Check if any hand is showing POINTING gesture
        let isPointing = gestures.contains { $0.name == "POINTING" }
        pointingHoldTracker.update(gesture: isPointing ? "POINTING" : nil)
        
        // Check if any hand is showing THANK_YOU gesture
        let isThankYou = gestures.contains { $0.name == "THANK_YOU" }
        thankYouHoldTracker.update(gesture: isThankYou ? "THANK_YOU" : nil)
        
        // Update progress for UI
        if isPointing {
            pointingHoldProgress = min(1.0, pointingHoldTracker.currentHoldDuration / 2.0)
        } else {
            pointingHoldProgress = 0
        }
        
        if isThankYou {
            thankYouHoldProgress = min(1.0, thankYouHoldTracker.currentHoldDuration / 2.0)
        } else {
            thankYouHoldProgress = 0
        }
    }
}

extension GestureRecognitionManager: HandGestureProcessorDelegate {
    
    nonisolated func handGestureProcessor(_ processor: HandGestureProcessor, didDetectGestures gestures: [DetectedGesture]) {
        Task { @MainActor in
            // Apply custom gesture detection on top of MediaPipe results
            let enhancedGestures = self.applyCustomGestureDetection(gestures)
            self.detectedGestures = enhancedGestures
            self.lastError = nil
            
            // Track gestures for 2-second trigger
            self.updateGestureTrackers(gestures: enhancedGestures)
            
            // Speak detected gestures through Meta Glasses speakers
            for gesture in enhancedGestures {
                self.speakGestureIfNeeded(gesture)
            }
        }
    }
    
    nonisolated func handGestureProcessor(_ processor: HandGestureProcessor, didFailWithError error: Error) {
        Task { @MainActor in
            self.lastError = error.localizedDescription
        }
    }
    
    /// Apply custom finger extension analysis to detect POINTING and THANK_YOU gestures
    /// Uses world landmarks when available for more accurate 3D gesture analysis
    private func applyCustomGestureDetection(_ gestures: [DetectedGesture]) -> [DetectedGesture] {
        return gestures.map { gesture in
            // Use world landmarks if available for better 3D accuracy, fallback to image landmarks
            let analysisLandmarks = gesture.worldLandmarks ?? gesture.landmarks
            
            // Check for POINTING gesture (highest priority)
            if FingerExtensionAnalyzer.isPointing(analysisLandmarks) {
                return DetectedGesture(
                    name: "POINTING",
                    score: 0.95,
                    handedness: gesture.handedness,
                    handednessScore: gesture.handednessScore,
                    landmarks: gesture.landmarks,
                    worldLandmarks: gesture.worldLandmarks
                )
            }
            
            // Check for THANK_YOU gesture (flat hand with fingers together)
            if FingerExtensionAnalyzer.isThankYou(analysisLandmarks) {
                return DetectedGesture(
                    name: "THANK_YOU",
                    score: 0.90,
                    handedness: gesture.handedness,
                    handednessScore: gesture.handednessScore,
                    landmarks: gesture.landmarks,
                    worldLandmarks: gesture.worldLandmarks
                )
            }
            
            return gesture
        }
    }
}
