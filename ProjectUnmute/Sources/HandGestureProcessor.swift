import Foundation
import UIKit
import AVFoundation
import os.log
import MediaPipeTasksVision

// MARK: - Hand Landmark

/// Represents one of 21 hand landmarks detected by MediaPipe
struct HandLandmark: Identifiable {
    let id: Int
    let name: String
    let x: Float      // Normalized [0, 1] by image width
    let y: Float      // Normalized [0, 1] by image height
    let z: Float      // Depth relative to wrist
    
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
struct FingerExtensionAnalyzer {
    
    /// Check if a finger is extended (straight) vs curled
    /// A finger is extended if the tip is farther from the wrist than the PIP joint
    static func isFingerExtended(landmarks: [HandLandmark], tipIndex: Int, pipIndex: Int, mcpIndex: Int) -> Bool {
        guard landmarks.count == 21 else { return false }
        
        let tip = landmarks[tipIndex]
        let pip = landmarks[pipIndex]
        let mcp = landmarks[mcpIndex]
        
        // For extension: tip should be farther from MCP than PIP is
        // Using Y coordinate (lower Y = higher in image for upward pointing)
        // Also check that tip is above PIP (tip.y < pip.y for upward)
        let tipToPip = distance(tip, pip)
        let pipToMcp = distance(pip, mcp)
        
        // Finger is extended if tip-to-pip distance is significant and tip is above pip
        let isExtended = tipToPip > pipToMcp * 0.5 && tip.y < pip.y
        return isExtended
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
        
        // Thumb is curled if tip is close to index MCP (near palm)
        let dist = distance(thumbTip, indexMCP)
        return dist < 0.15 // Threshold for "close"
    }
    
    /// Detect POINTING gesture: index extended, all others curled
    static func isPointing(_ landmarks: [HandLandmark]) -> Bool {
        guard landmarks.count == 21 else { return false }
        
        let indexUp = isIndexExtended(landmarks)
        let middleCurled = isMiddleCurled(landmarks)
        let ringCurled = isRingCurled(landmarks)
        let pinkyCurled = isPinkyCurled(landmarks)
        let thumbCurled = isThumbCurled(landmarks)
        
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
        
        // All fingers extended and together = flat hand for Thank You
        return indexExtended && middleExtended && ringExtended && pinkyExtended && thumbExtended && fingersTogether
    }
    
    /// Check if fingertips are close together (flat hand configuration)
    private static func areFingersClose(_ landmarks: [HandLandmark]) -> Bool {
        guard landmarks.count == 21 else { return false }
        
        let indexTip = landmarks[HandLandmark.indexTip]
        let middleTip = landmarks[HandLandmark.middleTip]
        let ringTip = landmarks[HandLandmark.ringTip]
        let pinkyTip = landmarks[HandLandmark.pinkyTip]
        
        // Check distances between adjacent fingertips
        let indexToMiddle = distance(indexTip, middleTip)
        let middleToRing = distance(middleTip, ringTip)
        let ringToPinky = distance(ringTip, pinkyTip)
        
        // Fingers are "together" if distances are small
        let threshold: Float = 0.12
        return indexToMiddle < threshold && middleToRing < threshold && ringToPinky < threshold
    }
    
    private static func distance(_ a: HandLandmark, _ b: HandLandmark) -> Float {
        let dx = a.x - b.x
        let dy = a.y - b.y
        let dz = a.z - b.z
        return sqrt(dx*dx + dy*dy + dz*dz)
    }
}

// MARK: - Gesture Result

/// A detected gesture with its confidence score
struct DetectedGesture: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let score: Float
    let handedness: String   // "Left" or "Right"
    let landmarks: [HandLandmark]
    
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
}

// MARK: - Gesture Processor Delegate

protocol HandGestureProcessorDelegate: AnyObject {
    func handGestureProcessor(_ processor: HandGestureProcessor, didDetectGestures gestures: [DetectedGesture])
    func handGestureProcessor(_ processor: HandGestureProcessor, didFailWithError error: Error)
}

// MARK: - Hand Gesture Processor

/// Processes frames from the Meta stream and detects hand gestures using MediaPipe GestureRecognizer
final class HandGestureProcessor: NSObject {
    
    // MARK: - Properties
    
    weak var delegate: HandGestureProcessorDelegate?
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ProjectUnmute", category: "HandGestureProcessor")
    
    private var gestureRecognizer: GestureRecognizer?
    private var isProcessing = false
    private let processingQueue = DispatchQueue(label: "com.projectunmute.gesture-processing", qos: .userInteractive)
    
    /// Minimum confidence threshold for gesture detection
    var minGestureConfidence: Float = 0.5
    
    /// Number of hands to detect (1 or 2)
    var maxHands: Int = 2
    
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
            options.minHandDetectionConfidence = 0.5
            options.minHandPresenceConfidence = 0.5
            options.minTrackingConfidence = 0.5
            options.gestureRecognizerLiveStreamDelegate = self
            
            gestureRecognizer = try GestureRecognizer(options: options)
            logger.info("GestureRecognizer initialized successfully")
        } catch {
            logger.error("Failed to create GestureRecognizer: \(error.localizedDescription)")
        }
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
            
            // Get the top gesture for this hand
            guard let topGesture = result.gestures[handIndex].first,
                  topGesture.score >= minGestureConfidence,
                  let gestureName = topGesture.categoryName,
                  gestureName != "None" else { continue }
            
            // Get handedness
            let handedness = result.handedness[handIndex].first?.categoryName ?? "Unknown"
            
            // Parse 21 landmarks
            let landmarks: [HandLandmark] = result.landmarks[handIndex].enumerated().map { index, landmark in
                HandLandmark(
                    id: index,
                    name: index < HandLandmark.landmarkNames.count ? HandLandmark.landmarkNames[index] : "UNKNOWN",
                    x: Float(landmark.x),
                    y: Float(landmark.y),
                    z: Float(landmark.z)
                )
            }
            
            let gesture = DetectedGesture(
                name: gestureName,
                score: topGesture.score,
                handedness: handedness,
                landmarks: landmarks
            )
            detectedGestures.append(gesture)
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
    
    private let processor = HandGestureProcessor()
    private var frameCount = 0
    
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
        }
    }
    
    nonisolated func handGestureProcessor(_ processor: HandGestureProcessor, didFailWithError error: Error) {
        Task { @MainActor in
            self.lastError = error.localizedDescription
        }
    }
    
    /// Apply custom finger extension analysis to detect POINTING and THANK_YOU gestures
    private func applyCustomGestureDetection(_ gestures: [DetectedGesture]) -> [DetectedGesture] {
        return gestures.map { gesture in
            // Check for POINTING gesture (highest priority)
            if FingerExtensionAnalyzer.isPointing(gesture.landmarks) {
                return DetectedGesture(
                    name: "POINTING",
                    score: 0.95,
                    handedness: gesture.handedness,
                    landmarks: gesture.landmarks
                )
            }
            
            // Check for THANK_YOU gesture (flat hand with fingers together)
            if FingerExtensionAnalyzer.isThankYou(gesture.landmarks) {
                return DetectedGesture(
                    name: "THANK_YOU",
                    score: 0.90,
                    handedness: gesture.handedness,
                    landmarks: gesture.landmarks
                )
            }
            
            return gesture
        }
    }
}
