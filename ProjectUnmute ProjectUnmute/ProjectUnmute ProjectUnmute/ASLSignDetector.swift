import Foundation
import AVFoundation
import Vision
import CoreImage
import os.log

// MARK: - ASL Sign Detector

/// Detects ASL signs from hand landmarks and converts them to text
/// This provides the reverse functionality: ASL → Text/Speech
/// Supports real-time detection from Meta Glasses camera feed
final class ASLSignDetector: ObservableObject {
    
    static let shared = ASLSignDetector()
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ProjectUnmute", category: "ASLSignDetector")
    
    // Vision request for hand pose detection
    private lazy var handPoseRequest: VNDetectHumanHandPoseRequest = {
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 1 // Focus on one hand for clearer detection
        return request
    }()
    
    // MARK: - Published Properties
    
    @Published var detectedSign: String?
    @Published var detectedSentence: String = ""
    @Published var confidence: Float = 0
    @Published var isDetecting: Bool = false
    @Published var handVisible: Bool = false  // True when a hand is in frame
    @Published var autoSpeakEnabled: Bool = true  // Auto-speak confirmed signs
    
    // MARK: - Private Properties
    
    private var lastDetectedSign: String?
    private var signHoldStartTime: Date?
    private let holdDurationRequired: TimeInterval = 1.0 // Hold sign for 1 second to confirm
    private var signHistory: [String] = []
    
    // MARK: - Hand Landmark Indices (MediaPipe standard)
    
    private struct LM {
        static let wrist = 0
        static let thumbTip = 4
        static let indexTip = 8
        static let middleTip = 12
        static let ringTip = 16
        static let pinkyTip = 20
        static let indexPIP = 6
        static let middlePIP = 10
        static let ringPIP = 14
        static let pinkyPIP = 18
        static let indexMCP = 5
        static let middleMCP = 9
        static let thumbMCP = 2
    }
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Process hand landmarks and detect ASL signs
    func processLandmarks(_ landmarks: [(x: Float, y: Float, z: Float)]) {
        guard landmarks.count == 21 else { return }
        
        isDetecting = true
        
        if let sign = detectSign(from: landmarks) {
            handleDetectedSign(sign.word, confidence: sign.confidence)
        } else {
            // No sign detected - reset hold timer
            if signHoldStartTime != nil {
                signHoldStartTime = nil
            }
        }
    }
    
    /// Process a camera frame from Meta Glasses to detect ASL signs
    /// This is the main entry point for real-time sign detection
    func processFrame(_ frame: CGImage) {
        let handler = VNImageRequestHandler(cgImage: frame, orientation: .up, options: [:])
        
        do {
            try handler.perform([handPoseRequest])
            
            guard let observation = handPoseRequest.results?.first else {
                // No hand detected
                DispatchQueue.main.async {
                    self.isDetecting = false
                    self.handVisible = false
                    self.detectedSign = nil
                }
                return
            }
            
            // Hand detected!
            DispatchQueue.main.async {
                self.handVisible = true
            }
            
            // Extract landmarks from Vision observation
            let landmarks = extractLandmarks(from: observation)
            
            // Process landmarks to detect signs
            DispatchQueue.main.async {
                self.processLandmarks(landmarks)
            }
            
        } catch {
            logger.error("Hand detection failed: \(error.localizedDescription)")
        }
    }
    
    /// Extract 21 hand landmarks from Vision observation
    private func extractLandmarks(from observation: VNHumanHandPoseObservation) -> [(x: Float, y: Float, z: Float)] {
        var landmarks: [(x: Float, y: Float, z: Float)] = []
        
        // Vision landmark mapping to MediaPipe-style indices
        let jointNames: [VNHumanHandPoseObservation.JointName] = [
            .wrist,                                          // 0: Wrist
            .thumbCMC, .thumbMP, .thumbIP, .thumbTip,        // 1-4: Thumb
            .indexMCP, .indexPIP, .indexDIP, .indexTip,      // 5-8: Index
            .middleMCP, .middlePIP, .middleDIP, .middleTip,  // 9-12: Middle
            .ringMCP, .ringPIP, .ringDIP, .ringTip,          // 13-16: Ring
            .littleMCP, .littlePIP, .littleDIP, .littleTip   // 17-20: Pinky
        ]
        
        for jointName in jointNames {
            if let point = try? observation.recognizedPoint(jointName) {
                // Vision uses normalized coordinates (0-1), with Y inverted
                landmarks.append((
                    x: Float(point.location.x),
                    y: Float(1.0 - point.location.y), // Invert Y for consistency
                    z: 0 // Vision doesn't provide Z, use 0
                ))
            } else {
                landmarks.append((x: 0, y: 0, z: 0))
            }
        }
        
        return landmarks
    }
    
    /// Clear the detected sentence
    func clearSentence() {
        detectedSentence = ""
        signHistory.removeAll()
        detectedSign = nil
        logger.info("Cleared ASL sentence")
    }
    
    /// Add a space (word separator) to sentence
    func addSpace() {
        if !detectedSentence.isEmpty && !detectedSentence.hasSuffix(" ") {
            detectedSentence += " "
        }
    }
    
    // Speech synthesizer
    private let speechSynthesizer = AVSpeechSynthesizer()
    
    /// Speak the detected sentence
    func speakSentence() {
        guard !detectedSentence.isEmpty else { return }
        
        // Stop any current speech
        speechSynthesizer.stopSpeaking(at: .immediate)
        
        // Create utterance with clear voice
        let utterance = AVSpeechUtterance(string: detectedSentence)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9 // Slightly slower
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        
        // Use a high-quality English voice
        if let voice = AVSpeechSynthesisVoice(language: "en-US") {
            utterance.voice = voice
        }
        
        speechSynthesizer.speak(utterance)
        logger.info("Speaking: \(self.detectedSentence)")
    }
    
    /// Simulate a detected sign (for demo/testing in simulator)
    func simulateDetectedSign(_ word: String) {
        logger.info("Simulating ASL sign: \(word)")
        
        // Show as detected
        detectedSign = word
        confidence = 1.0
        isDetecting = true
        
        // Add to sentence directly (skip history check for demo)
        if word.count == 1 {
            // Single letter - add directly
            detectedSentence += word
        } else {
            // Word - add with space
            if !detectedSentence.isEmpty && !detectedSentence.hasSuffix(" ") {
                detectedSentence += " "
            }
            detectedSentence += word
        }
        
        signHistory.append(word)
        logger.info("Added to sentence: \(self.detectedSentence)")
        
        // Clear detected sign after a moment
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.detectedSign = nil
        }
    }
    
    // MARK: - Private Methods
    
    private func handleDetectedSign(_ sign: String, confidence: Float) {
        self.confidence = confidence
        
        if sign == lastDetectedSign {
            // Same sign being held
            if let startTime = signHoldStartTime {
                let holdDuration = Date().timeIntervalSince(startTime)
                if holdDuration >= holdDurationRequired {
                    // Sign confirmed! Add to sentence
                    confirmSign(sign)
                    signHoldStartTime = nil
                    lastDetectedSign = nil
                }
            }
        } else {
            // New sign detected
            lastDetectedSign = sign
            signHoldStartTime = Date()
            detectedSign = sign
            logger.info("Detected ASL sign: \(sign) (hold to confirm)")
        }
    }
    
    private func confirmSign(_ sign: String) {
        // Avoid adding the same sign twice in a row
        if signHistory.last != sign {
            signHistory.append(sign)
            
            // Add to sentence
            if sign.count == 1 {
                // Single letter - add directly (fingerspelling)
                detectedSentence += sign
            } else {
                // Word - add with space
                if !detectedSentence.isEmpty && !detectedSentence.hasSuffix(" ") {
                    detectedSentence += " "
                }
                detectedSentence += sign
            }
            
            logger.info("Confirmed sign: \(sign) → Sentence: \(self.detectedSentence)")
            
            // Auto-speak the confirmed sign through Meta Glasses
            if autoSpeakEnabled {
                speakSign(sign)
            }
        }
    }
    
    /// Speak a single sign through Bluetooth (Meta Glasses speakers)
    private func speakSign(_ sign: String) {
        // Use the shared SpeechSynthesizer for Bluetooth routing
        // This ensures audio goes to Meta Glasses if connected
        
        // Stop any current speech
        speechSynthesizer.stopSpeaking(at: .immediate)
        
        let utterance = AVSpeechUtterance(string: sign)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        
        if let voice = AVSpeechSynthesisVoice(language: "en-US") {
            utterance.voice = voice
        }
        
        // Configure audio session for Bluetooth before speaking
        configureAudioForBluetooth()
        
        speechSynthesizer.speak(utterance)
        logger.info("🔊 Auto-speaking sign: \(sign)")
    }
    
    /// Configure audio session to route through Bluetooth (Meta Glasses)
    private func configureAudioForBluetooth() {
        #if !targetEnvironment(macCatalyst)
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(
                .playback,
                mode: .voicePrompt,
                options: [.allowBluetooth, .allowBluetoothA2DP]
            )
            try audioSession.setActive(true)
        } catch {
            logger.error("Failed to configure audio for Bluetooth: \(error.localizedDescription)")
        }
        #endif
    }
    
    // MARK: - Sign Detection Logic
    
    private struct DetectedSignResult {
        let word: String
        let confidence: Float
    }
    
    private func detectSign(from landmarks: [(x: Float, y: Float, z: Float)]) -> DetectedSignResult? {
        // Count extended fingers
        let indexExtended = isFingerExtended(landmarks, tip: LM.indexTip, pip: LM.indexPIP)
        let middleExtended = isFingerExtended(landmarks, tip: LM.middleTip, pip: LM.middlePIP)
        let ringExtended = isFingerExtended(landmarks, tip: LM.ringTip, pip: LM.ringPIP)
        let pinkyExtended = isFingerExtended(landmarks, tip: LM.pinkyTip, pip: LM.pinkyPIP)
        let thumbExtended = isThumbExtended(landmarks)
        
        let extendedCount = [indexExtended, middleExtended, ringExtended, pinkyExtended]
            .filter { $0 }.count + (thumbExtended ? 1 : 0)
        
        // I LOVE YOU - Thumb, index, pinky extended; middle, ring curled
        if thumbExtended && indexExtended && !middleExtended && !ringExtended && pinkyExtended {
            return DetectedSignResult(word: "I Love You", confidence: 0.90)
        }
        
        // THUMBS UP - Only thumb extended
        if thumbExtended && !indexExtended && !middleExtended && !ringExtended && !pinkyExtended {
            if isThumbUp(landmarks) {
                return DetectedSignResult(word: "Good", confidence: 0.85)
            }
        }
        
        // PEACE / V / 2 - Index and middle extended, spread apart
        if indexExtended && middleExtended && !ringExtended && !pinkyExtended {
            return DetectedSignResult(word: "Peace", confidence: 0.85)
        }
        
        // POINTING / 1 - Only index extended
        if indexExtended && !middleExtended && !ringExtended && !pinkyExtended && !thumbExtended {
            return DetectedSignResult(word: "1", confidence: 0.85)
        }
        
        // Y / HANG LOOSE - Thumb and pinky extended
        if thumbExtended && !indexExtended && !middleExtended && !ringExtended && pinkyExtended {
            return DetectedSignResult(word: "Y", confidence: 0.85)
        }
        
        // L - Thumb and index at 90 degrees
        if thumbExtended && indexExtended && !middleExtended && !ringExtended && !pinkyExtended {
            if isLShape(landmarks) {
                return DetectedSignResult(word: "L", confidence: 0.85)
            }
        }
        
        // OPEN PALM / 5 / HELLO / STOP - All fingers extended
        if extendedCount == 5 {
            return DetectedSignResult(word: "Hello", confidence: 0.80)
        }
        
        // 4 - All fingers except thumb
        if indexExtended && middleExtended && ringExtended && pinkyExtended && !thumbExtended {
            return DetectedSignResult(word: "4", confidence: 0.85)
        }
        
        // 3 - Thumb, index, middle extended
        if thumbExtended && indexExtended && middleExtended && !ringExtended && !pinkyExtended {
            return DetectedSignResult(word: "3", confidence: 0.80)
        }
        
        // FIST / A / YES - All fingers curled
        if !indexExtended && !middleExtended && !ringExtended && !pinkyExtended {
            return DetectedSignResult(word: "Yes", confidence: 0.75)
        }
        
        // W - Index, middle, ring extended
        if indexExtended && middleExtended && ringExtended && !pinkyExtended && !thumbExtended {
            return DetectedSignResult(word: "W", confidence: 0.80)
        }
        
        // I - Only pinky extended
        if !indexExtended && !middleExtended && !ringExtended && pinkyExtended && !thumbExtended {
            return DetectedSignResult(word: "I", confidence: 0.85)
        }
        
        return nil
    }
    
    // MARK: - Helper Methods
    
    private func isFingerExtended(_ landmarks: [(x: Float, y: Float, z: Float)], tip: Int, pip: Int) -> Bool {
        // Finger is extended if tip is above (lower Y value) than PIP joint
        return landmarks[tip].y < landmarks[pip].y
    }
    
    private func isThumbExtended(_ landmarks: [(x: Float, y: Float, z: Float)]) -> Bool {
        let thumbTip = landmarks[LM.thumbTip]
        let thumbMCP = landmarks[LM.thumbMCP]
        let indexMCP = landmarks[LM.indexMCP]
        
        // Thumb is extended if tip is far from index MCP
        let dist = distance2D(thumbTip, indexMCP)
        let refDist = distance2D(thumbMCP, indexMCP)
        
        return dist > refDist * 1.5
    }
    
    private func isThumbUp(_ landmarks: [(x: Float, y: Float, z: Float)]) -> Bool {
        let thumbTip = landmarks[LM.thumbTip]
        let wrist = landmarks[LM.wrist]
        
        // Thumb is up if tip is above wrist
        return thumbTip.y < wrist.y - 0.1
    }
    
    private func isLShape(_ landmarks: [(x: Float, y: Float, z: Float)]) -> Bool {
        let thumbTip = landmarks[LM.thumbTip]
        let indexTip = landmarks[LM.indexTip]
        let wrist = landmarks[LM.wrist]
        
        // Check if thumb and index form roughly 90 degree angle
        let thumbAngle = atan2(thumbTip.y - wrist.y, thumbTip.x - wrist.x)
        let indexAngle = atan2(indexTip.y - wrist.y, indexTip.x - wrist.x)
        
        let angleDiff = abs(thumbAngle - indexAngle)
        return angleDiff > 1.0 && angleDiff < 2.0 // Roughly 60-120 degrees
    }
    
    private func distance2D(_ a: (x: Float, y: Float, z: Float), _ b: (x: Float, y: Float, z: Float)) -> Float {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
    }
}
