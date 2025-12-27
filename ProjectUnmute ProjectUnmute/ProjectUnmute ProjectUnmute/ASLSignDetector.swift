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
        // Count extended fingers with improved detection
        let indexExtended = isFingerExtended(landmarks, tip: LM.indexTip, pip: LM.indexPIP)
        let middleExtended = isFingerExtended(landmarks, tip: LM.middleTip, pip: LM.middlePIP)
        let ringExtended = isFingerExtended(landmarks, tip: LM.ringTip, pip: LM.ringPIP)
        let pinkyExtended = isFingerExtended(landmarks, tip: LM.pinkyTip, pip: LM.pinkyPIP)
        let thumbExtended = isThumbExtended(landmarks)
        
        let fingerCount = countExtendedFingers(landmarks)
        let allFingersCurled = areAllFingersCurled(landmarks)
        
        // ============ PRIORITY 1: Most distinctive signs first ============
        
        // THUMBS UP / GOOD - Fist with thumb pointing up (most reliable)
        if allFingersCurled && thumbExtended && isThumbUp(landmarks) {
            return DetectedSignResult(word: "Good", confidence: 0.92)
        }
        
        // I LOVE YOU - Very distinctive: thumb + index + pinky, middle & ring curled
        if thumbExtended && indexExtended && !middleExtended && !ringExtended && pinkyExtended {
            return DetectedSignResult(word: "I Love You", confidence: 0.90)
        }
        
        // FIST / YES - All fingers curled, thumb not up
        if allFingersCurled && !isThumbUp(landmarks) {
            return DetectedSignResult(word: "Yes", confidence: 0.85)
        }
        
        // ============ PRIORITY 2: Clear finger counts ============
        
        // OPEN PALM / HELLO / 5 - All 5 fingers clearly extended
        if fingerCount == 4 && thumbExtended {
            return DetectedSignResult(word: "Hello", confidence: 0.88)
        }
        
        // 4 - All 4 fingers extended, thumb curled
        if fingerCount == 4 && !thumbExtended {
            return DetectedSignResult(word: "4", confidence: 0.85)
        }
        
        // PEACE / V / 2 - Index and middle extended, others curled
        if indexExtended && middleExtended && !ringExtended && !pinkyExtended && !thumbExtended {
            return DetectedSignResult(word: "Peace", confidence: 0.88)
        }
        
        // 3 - Thumb, index, middle extended
        if thumbExtended && indexExtended && middleExtended && !ringExtended && !pinkyExtended {
            return DetectedSignResult(word: "3", confidence: 0.85)
        }
        
        // W - Index, middle, ring extended (no pinky, no thumb)
        if indexExtended && middleExtended && ringExtended && !pinkyExtended && !thumbExtended {
            return DetectedSignResult(word: "W", confidence: 0.85)
        }
        
        // ============ PRIORITY 3: Single finger signs ============
        
        // POINTING / 1 - Only index extended
        if indexExtended && !middleExtended && !ringExtended && !pinkyExtended && !thumbExtended {
            return DetectedSignResult(word: "1", confidence: 0.88)
        }
        
        // I - Only pinky extended
        if !indexExtended && !middleExtended && !ringExtended && pinkyExtended && !thumbExtended {
            return DetectedSignResult(word: "I", confidence: 0.85)
        }
        
        // Y / HANG LOOSE - Thumb and pinky only
        if thumbExtended && !indexExtended && !middleExtended && !ringExtended && pinkyExtended {
            return DetectedSignResult(word: "Y", confidence: 0.88)
        }
        
        // L - Thumb and index at angle (check L shape)
        if thumbExtended && indexExtended && !middleExtended && !ringExtended && !pinkyExtended {
            return DetectedSignResult(word: "L", confidence: 0.85)
        }
        
        // ============ PRIORITY 4: Less common signs ============
        
        // No sign detected
        return nil
    }
    
    // MARK: - Word Sign Shape Helpers
    
    private func isFlatOShape(_ landmarks: [(x: Float, y: Float, z: Float)]) -> Bool {
        // All fingertips close together (flat O / bunched fingers)
        let indexTip = landmarks[LM.indexTip]
        let middleTip = landmarks[LM.middleTip]
        let ringTip = landmarks[LM.ringTip]
        let thumbTip = landmarks[LM.thumbTip]
        
        let d1 = distance2D(indexTip, middleTip)
        let d2 = distance2D(middleTip, ringTip)
        let d3 = distance2D(indexTip, thumbTip)
        
        return d1 < 0.06 && d2 < 0.06 && d3 < 0.1
    }
    
    private func isClawShape(_ landmarks: [(x: Float, y: Float, z: Float)]) -> Bool {
        // Fingers bent like claws (curved, not fully extended or curled)
        let indexTip = landmarks[LM.indexTip]
        let indexPIP = landmarks[LM.indexPIP]
        let indexMCP = landmarks[LM.indexMCP]
        
        // Tip between PIP and MCP height (partially bent)
        let tipY = indexTip.y
        let pipY = indexPIP.y
        let mcpY = indexMCP.y
        
        return tipY > pipY && tipY < mcpY
    }
    
    private func isTiredShape(_ landmarks: [(x: Float, y: Float, z: Float)]) -> Bool {
        // Bent hands (fingers partially curled)
        let indexTip = landmarks[LM.indexTip]
        let indexPIP = landmarks[LM.indexPIP]
        
        return indexTip.y > indexPIP.y - 0.05 && indexTip.y < indexPIP.y + 0.1
    }
    
    private func isHookedIndex(_ landmarks: [(x: Float, y: Float, z: Float)]) -> Bool {
        // Index finger bent/hooked
        let indexTip = landmarks[LM.indexTip]
        let indexPIP = landmarks[LM.indexPIP]
        let middleExtended = landmarks[LM.middleTip].y < landmarks[LM.middlePIP].y
        
        return indexTip.y > indexPIP.y && !middleExtended
    }
    
    private func isTShape(_ landmarks: [(x: Float, y: Float, z: Float)]) -> Bool {
        // T: Thumb between index and middle (tucked)
        let thumbTip = landmarks[LM.thumbTip]
        let indexMCP = landmarks[LM.indexMCP]
        let middleMCP = landmarks[LM.middleMCP]
        
        let thumbBetween = thumbTip.x > min(indexMCP.x, middleMCP.x) && 
                           thumbTip.x < max(indexMCP.x, middleMCP.x)
        let indexCurled = landmarks[LM.indexTip].y > landmarks[LM.indexPIP].y
        
        return thumbBetween && indexCurled
    }
    
    private func isBentHand(_ landmarks: [(x: Float, y: Float, z: Float)]) -> Bool {
        // All fingers bent at same angle
        let indexBent = landmarks[LM.indexTip].y > landmarks[LM.indexPIP].y
        let middleBent = landmarks[LM.middleTip].y > landmarks[LM.middlePIP].y
        
        return indexBent && middleBent
    }
    
    private func isHShape(_ landmarks: [(x: Float, y: Float, z: Float)]) -> Bool {
        // H: Index and middle extended horizontally
        let indexTip = landmarks[LM.indexTip]
        let indexMCP = landmarks[LM.indexMCP]
        let middleTip = landmarks[LM.middleTip]
        let middleMCP = landmarks[LM.middleMCP]
        
        let indexHorizontal = abs(indexTip.x - indexMCP.x) > abs(indexTip.y - indexMCP.y)
        let middleHorizontal = abs(middleTip.x - middleMCP.x) > abs(middleTip.y - middleMCP.y)
        
        let ringCurled = landmarks[LM.ringTip].y > landmarks[LM.ringPIP].y
        
        return indexHorizontal && middleHorizontal && ringCurled
    }
    
    private func isLikeShape(_ landmarks: [(x: Float, y: Float, z: Float)]) -> Bool {
        // Like: Middle finger and thumb extended, others curled
        let thumbExtended = isThumbExtended(landmarks)
        let middleExtended = landmarks[LM.middleTip].y < landmarks[LM.middlePIP].y
        let indexCurled = landmarks[LM.indexTip].y > landmarks[LM.indexPIP].y
        
        return thumbExtended && middleExtended && indexCurled
    }
    
    // MARK: - Position Detection Helpers
    
    private func isNearFace(_ landmarks: [(x: Float, y: Float, z: Float)]) -> Bool {
        // Hand is in upper portion of frame (near face area)
        let wrist = landmarks[LM.wrist]
        return wrist.y < 0.4  // Upper 40% of frame
    }
    
    private func isNearMouth(_ landmarks: [(x: Float, y: Float, z: Float)]) -> Bool {
        let wrist = landmarks[LM.wrist]
        return wrist.y < 0.35 && wrist.y > 0.2
    }
    
    private func isNearChest(_ landmarks: [(x: Float, y: Float, z: Float)]) -> Bool {
        let wrist = landmarks[LM.wrist]
        return wrist.y > 0.4 && wrist.y < 0.7
    }
    
    private func isNearForehead(_ landmarks: [(x: Float, y: Float, z: Float)]) -> Bool {
        let indexTip = landmarks[LM.indexTip]
        return indexTip.y < 0.25
    }
    
    private func isNearEar(_ landmarks: [(x: Float, y: Float, z: Float)]) -> Bool {
        let indexTip = landmarks[LM.indexTip]
        // Near edge of frame horizontally and upper area
        return (indexTip.x < 0.2 || indexTip.x > 0.8) && indexTip.y < 0.35
    }
    
    private func isNearEyes(_ landmarks: [(x: Float, y: Float, z: Float)]) -> Bool {
        let indexTip = landmarks[LM.indexTip]
        return indexTip.y < 0.3 && indexTip.x > 0.3 && indexTip.x < 0.7
    }
    
    private func isPalmFacingOut(_ landmarks: [(x: Float, y: Float, z: Float)]) -> Bool {
        // Simplified: fingers pointing up, palm would face out
        let indexTip = landmarks[LM.indexTip]
        let wrist = landmarks[LM.wrist]
        return indexTip.y < wrist.y - 0.15
    }
    
    private func isHandMovingDown(_ landmarks: [(x: Float, y: Float, z: Float)]) -> Bool {
        // Static proxy: hand in lower portion
        let wrist = landmarks[LM.wrist]
        return wrist.y > 0.5
    }
    
    private func areFingersSpread(_ landmarks: [(x: Float, y: Float, z: Float)]) -> Bool {
        let indexTip = landmarks[LM.indexTip]
        let pinkyTip = landmarks[LM.pinkyTip]
        
        return abs(indexTip.x - pinkyTip.x) > 0.15
    }
    
    private func isHandSideways(_ landmarks: [(x: Float, y: Float, z: Float)]) -> Bool {
        let indexTip = landmarks[LM.indexTip]
        let wrist = landmarks[LM.wrist]
        
        // Hand is more horizontal than vertical
        return abs(indexTip.x - wrist.x) > abs(indexTip.y - wrist.y)
    }
    
    // MARK: - Advanced Shape Detection
    
    private func isFingersTogether(_ landmarks: [(x: Float, y: Float, z: Float)]) -> Bool {
        // Check if index, middle, ring, pinky tips are close together horizontally
        let indexTip = landmarks[LM.indexTip]
        let middleTip = landmarks[LM.middleTip]
        let ringTip = landmarks[LM.ringTip]
        let pinkyTip = landmarks[LM.pinkyTip]
        
        let maxSpread = max(
            abs(indexTip.x - middleTip.x),
            abs(middleTip.x - ringTip.x),
            abs(ringTip.x - pinkyTip.x)
        )
        
        return maxSpread < 0.08  // Fingers are close together
    }
    
    private func isCShape(_ landmarks: [(x: Float, y: Float, z: Float)]) -> Bool {
        // C shape: fingers curved together, thumb curved opposite
        let thumbTip = landmarks[LM.thumbTip]
        let indexTip = landmarks[LM.indexTip]
        let pinkyTip = landmarks[LM.pinkyTip]
        
        // Tips should form a C-like arc
        let thumbToIndex = distance2D(thumbTip, indexTip)
        let indexToPinky = distance2D(indexTip, pinkyTip)
        
        // C has moderate gap between thumb and index
        return thumbToIndex > 0.1 && thumbToIndex < 0.25 && indexToPinky < 0.15
    }
    
    private func isDShape(_ landmarks: [(x: Float, y: Float, z: Float)]) -> Bool {
        // D: index extended, others touch thumb
        let thumbTip = landmarks[LM.thumbTip]
        let middleTip = landmarks[LM.middleTip]
        
        let thumbToMiddle = distance2D(thumbTip, middleTip)
        return thumbToMiddle < 0.08  // Middle finger touches thumb
    }
    
    private func isEShape(_ landmarks: [(x: Float, y: Float, z: Float)]) -> Bool {
        // E: all fingers curled, tips near palm
        let indexTip = landmarks[LM.indexTip]
        let indexMCP = landmarks[LM.indexMCP]
        
        // Fingertips should be close to MCP joints (curled)
        let tipToMCP = distance2D(indexTip, indexMCP)
        return tipToMCP < 0.1
    }
    
    private func isFShape(_ landmarks: [(x: Float, y: Float, z: Float)]) -> Bool {
        // F: index and thumb touch forming circle, other 3 extended
        let thumbTip = landmarks[LM.thumbTip]
        let indexTip = landmarks[LM.indexTip]
        let middleTip = landmarks[LM.middleTip]
        let middlePIP = landmarks[LM.middlePIP]
        
        let thumbToIndex = distance2D(thumbTip, indexTip)
        let middleExtended = middleTip.y < middlePIP.y
        
        return thumbToIndex < 0.06 && middleExtended  // Thumb and index touching
    }
    
    private func isGShape(_ landmarks: [(x: Float, y: Float, z: Float)]) -> Bool {
        // G: index pointing sideways, thumb parallel
        let indexTip = landmarks[LM.indexTip]
        let indexMCP = landmarks[LM.indexMCP]
        
        // Index should be more horizontal than vertical
        let indexHorizontal = abs(indexTip.x - indexMCP.x) > abs(indexTip.y - indexMCP.y)
        return indexHorizontal
    }
    
    private func isKShape(_ landmarks: [(x: Float, y: Float, z: Float)]) -> Bool {
        // K: V with thumb between index and middle
        let thumbTip = landmarks[LM.thumbTip]
        let indexTip = landmarks[LM.indexTip]
        let middleTip = landmarks[LM.middleTip]
        
        // Thumb should be between index and middle
        let thumbX = thumbTip.x
        let inBetween = (thumbX > min(indexTip.x, middleTip.x)) && (thumbX < max(indexTip.x, middleTip.x))
        return inBetween
    }
    
    private func isOShape(_ landmarks: [(x: Float, y: Float, z: Float)]) -> Bool {
        // O: all fingertips touch thumb (circle)
        let thumbTip = landmarks[LM.thumbTip]
        let indexTip = landmarks[LM.indexTip]
        let middleTip = landmarks[LM.middleTip]
        
        let thumbToIndex = distance2D(thumbTip, indexTip)
        let thumbToMiddle = distance2D(thumbTip, middleTip)
        
        return thumbToIndex < 0.08 && thumbToMiddle < 0.12
    }
    
    private func isRShape(_ landmarks: [(x: Float, y: Float, z: Float)]) -> Bool {
        // R: index and middle crossed
        let indexTip = landmarks[LM.indexTip]
        let indexPIP = landmarks[LM.indexPIP]
        let middlePIP = landmarks[LM.middlePIP]
        
        // Check if fingers cross (index tip closer to middle base)
        let indexCrossed = abs(indexTip.x - middlePIP.x) < abs(indexTip.x - indexPIP.x)
        return indexCrossed
    }
    
    private func isXShape(_ landmarks: [(x: Float, y: Float, z: Float)]) -> Bool {
        // X: index bent/hooked
        let indexTip = landmarks[LM.indexTip]
        let indexPIP = landmarks[LM.indexPIP]
        let indexMCP = landmarks[LM.indexMCP]
        
        // Index tip should be below PIP but PIP above MCP (hooked)
        return indexTip.y > indexPIP.y && indexPIP.y < indexMCP.y
    }
    
    private func isPalmFacingUp(_ landmarks: [(x: Float, y: Float, z: Float)]) -> Bool {
        // Simple heuristic: fingertips above wrist
        let indexTip = landmarks[LM.indexTip]
        let wrist = landmarks[LM.wrist]
        return indexTip.y < wrist.y
    }
    
    private func isNoSign(_ landmarks: [(x: Float, y: Float, z: Float)]) -> Bool {
        // NO: index and middle snap to thumb
        let thumbTip = landmarks[LM.thumbTip]
        let indexTip = landmarks[LM.indexTip]
        let middleTip = landmarks[LM.middleTip]
        
        let thumbToIndex = distance2D(thumbTip, indexTip)
        let thumbToMiddle = distance2D(thumbTip, middleTip)
        
        return thumbToIndex < 0.06 && thumbToMiddle < 0.06
    }
    
    // MARK: - Improved Helper Methods
    
    /// Check if a finger is extended using multiple reference points for accuracy
    private func isFingerExtended(_ landmarks: [(x: Float, y: Float, z: Float)], tip: Int, pip: Int) -> Bool {
        let tipPoint = landmarks[tip]
        let pipPoint = landmarks[pip]
        
        // Use a threshold based on relative position
        // Finger is extended if tip Y is significantly above PIP Y
        // Note: In Vision coordinates, lower Y = higher on screen
        let yDiff = pipPoint.y - tipPoint.y
        
        // Require tip to be at least 0.03 units above PIP (more lenient)
        return yDiff > 0.02
    }
    
    /// Check if finger is clearly curled (not just slightly bent)
    private func isFingerCurled(_ landmarks: [(x: Float, y: Float, z: Float)], tip: Int, pip: Int, mcp: Int) -> Bool {
        let tipPoint = landmarks[tip]
        let pipPoint = landmarks[pip]
        let mcpPoint = landmarks[mcp]
        
        // Finger is curled if tip is below or near PIP level
        let tipBelowPIP = tipPoint.y >= pipPoint.y - 0.02
        
        // And tip is close to MCP horizontally (curled back)
        let tipNearMCP = abs(tipPoint.x - mcpPoint.x) < 0.1
        
        return tipBelowPIP || tipNearMCP
    }
    
    private func isThumbExtended(_ landmarks: [(x: Float, y: Float, z: Float)]) -> Bool {
        let thumbTip = landmarks[LM.thumbTip]
        let indexMCP = landmarks[LM.indexMCP]
        let wrist = landmarks[LM.wrist]
        
        // Calculate hand size for relative measurements
        let handSize = distance2D(wrist, indexMCP)
        guard handSize > 0.01 else { return false }
        
        // Thumb is extended if tip is far from the palm center
        let palmCenterX = (indexMCP.x + wrist.x) / 2
        let palmCenterY = (indexMCP.y + wrist.y) / 2
        let palmCenter = (x: palmCenterX, y: palmCenterY, z: Float(0))
        
        let thumbDist = distance2D(thumbTip, palmCenter)
        
        // Thumb extended if it's more than 50% of hand size away from palm
        return thumbDist > handSize * 0.5
    }
    
    private func isThumbUp(_ landmarks: [(x: Float, y: Float, z: Float)]) -> Bool {
        let thumbTip = landmarks[LM.thumbTip]
        let thumbMCP = landmarks[LM.thumbMCP]
        let wrist = landmarks[LM.wrist]
        
        // Thumb is pointing up if:
        // 1. Thumb tip is above thumb MCP
        // 2. Thumb tip is above wrist
        // 3. Other fingers are curled
        
        let thumbPointingUp = thumbTip.y < thumbMCP.y - 0.03
        let thumbAboveWrist = thumbTip.y < wrist.y
        
        // Check other fingers are curled
        let indexCurled = isFingerCurled(landmarks, tip: LM.indexTip, pip: LM.indexPIP, mcp: LM.indexMCP)
        
        return thumbPointingUp && thumbAboveWrist && indexCurled
    }
    
    private func isLShape(_ landmarks: [(x: Float, y: Float, z: Float)]) -> Bool {
        let thumbTip = landmarks[LM.thumbTip]
        let indexTip = landmarks[LM.indexTip]
        let wrist = landmarks[LM.wrist]
        
        // L shape: thumb pointing sideways, index pointing up
        let indexPointingUp = indexTip.y < wrist.y - 0.1
        let thumbSideways = abs(thumbTip.x - wrist.x) > 0.08
        
        return indexPointingUp && thumbSideways
    }
    
    private func distance2D(_ a: (x: Float, y: Float, z: Float), _ b: (x: Float, y: Float, z: Float)) -> Float {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
    }
    
    /// Get the number of clearly extended fingers (excluding thumb)
    private func countExtendedFingers(_ landmarks: [(x: Float, y: Float, z: Float)]) -> Int {
        var count = 0
        
        if isFingerExtended(landmarks, tip: LM.indexTip, pip: LM.indexPIP) { count += 1 }
        if isFingerExtended(landmarks, tip: LM.middleTip, pip: LM.middlePIP) { count += 1 }
        if isFingerExtended(landmarks, tip: LM.ringTip, pip: LM.ringPIP) { count += 1 }
        if isFingerExtended(landmarks, tip: LM.pinkyTip, pip: LM.pinkyPIP) { count += 1 }
        
        return count
    }
    
    /// Check if all four fingers (not thumb) are curled
    private func areAllFingersCurled(_ landmarks: [(x: Float, y: Float, z: Float)]) -> Bool {
        let indexCurled = !isFingerExtended(landmarks, tip: LM.indexTip, pip: LM.indexPIP)
        let middleCurled = !isFingerExtended(landmarks, tip: LM.middleTip, pip: LM.middlePIP)
        let ringCurled = !isFingerExtended(landmarks, tip: LM.ringTip, pip: LM.ringPIP)
        let pinkyCurled = !isFingerExtended(landmarks, tip: LM.pinkyTip, pip: LM.pinkyPIP)
        
        return indexCurled && middleCurled && ringCurled && pinkyCurled
    }
}
