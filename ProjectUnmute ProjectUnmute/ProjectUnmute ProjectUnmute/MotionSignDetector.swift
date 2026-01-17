import Foundation
import simd

/// Detects dynamic ASL signs that require motion tracking over multiple frames
/// These signs cannot be detected from a single static pose
final class MotionSignDetector {
    
    // MARK: - Singleton
    
    static let shared = MotionSignDetector()
    
    // MARK: - Types
    
    struct HandFrame {
        let landmarks: [(x: Float, y: Float, z: Float)]
        let timestamp: Date
        let wristPosition: SIMD3<Float>
        let palmCenter: SIMD3<Float>
        let fingerStates: FingerStates
    }
    
    struct FingerStates {
        let thumbExtended: Bool
        let indexExtended: Bool
        let middleExtended: Bool
        let ringExtended: Bool
        let pinkyExtended: Bool
        
        var extendedCount: Int {
            [thumbExtended, indexExtended, middleExtended, ringExtended, pinkyExtended]
                .filter { $0 }.count
        }
        
        var allExtended: Bool { extendedCount == 5 }
        var allCurled: Bool { extendedCount == 0 }
        var isFist: Bool { !thumbExtended && !indexExtended && !middleExtended && !ringExtended && !pinkyExtended }
    }
    
    struct MotionResult {
        let sign: String
        let confidence: Float
        let isComplete: Bool  // Motion pattern fully matched
    }
    
    // MARK: - Properties
    
    private var frameHistory: [HandFrame] = []
    private let maxHistoryFrames = 30  // ~1 second at 30fps
    private let minFramesForMotion = 5  // Minimum frames to detect motion
    
    // Motion detection state
    private var currentMotionSign: String?
    private var motionStartTime: Date?
    private var motionConfidence: Float = 0
    
    // Cooldown to prevent repeated triggers during transitions
    private var lastConfirmedSign: String?
    private var lastConfirmationTime: Date?
    private let cooldownDuration: TimeInterval = 8.0  // 8 seconds cooldown for same sign
    private let transitionDelay: TimeInterval = 5.0   // 5 seconds wait between ANY signs
    
    // Thresholds
    private let motionThreshold: Float = 0.02  // Minimum movement to register
    private let significantMotion: Float = 0.03  // Significant movement
    
    // MARK: - Landmark Indices
    
    private enum LM {
        static let wrist = 0
        static let thumbCMC = 1, thumbMCP = 2, thumbIP = 3, thumbTip = 4
        static let indexMCP = 5, indexPIP = 6, indexDIP = 7, indexTip = 8
        static let middleMCP = 9, middlePIP = 10, middleDIP = 11, middleTip = 12
        static let ringMCP = 13, ringPIP = 14, ringDIP = 15, ringTip = 16
        static let pinkyMCP = 17, pinkyPIP = 18, pinkyDIP = 19, pinkyTip = 20
    }
    
    // MARK: - Public Methods
    
    /// Process a new frame and detect motion-based signs
    /// - Parameter landmarks: 21 hand landmarks
    /// - Returns: Detected motion sign with confidence, or nil if no motion sign detected
    func processFrame(landmarks: [(x: Float, y: Float, z: Float)]) -> MotionResult? {
        guard landmarks.count == 21 else { return nil }
        
        // Create frame data
        let frame = createHandFrame(landmarks: landmarks)
        
        // Add to history
        frameHistory.append(frame)
        if frameHistory.count > maxHistoryFrames {
            frameHistory.removeFirst()
        }
        
        // Need minimum frames for motion detection
        guard frameHistory.count >= minFramesForMotion else { return nil }
        
        // =============================================================
        // DEBUG LOGGING - Comprehensive hand state info
        // =============================================================
        let motionMag = getMotionMagnitude(frames: 12)
        let isMoving = motionMag > 0.02
        let extCount = frame.fingerStates.extendedCount
        let vertMag = abs(getVerticalMotion(frames: 12))
        let horzMag = abs(getHorizontalMotion(frames: 12))
        let hasVertOsc = hasOscillation(axis: \.y, minCycles: 1)
        let hasHorzOsc = hasOscillation(axis: \.x, minCycles: 1)
        
        // Log every 20 frames for better debugging
        if frameHistory.count % 20 == 0 {
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
            print("🖐️ HAND STATE [Frame \(frameHistory.count)]")
            print("   Fingers: \(extCount) extended | T:\(frame.fingerStates.thumbExtended ? "✓" : "✗") I:\(frame.fingerStates.indexExtended ? "✓" : "✗") M:\(frame.fingerStates.middleExtended ? "✓" : "✗") R:\(frame.fingerStates.ringExtended ? "✓" : "✗") P:\(frame.fingerStates.pinkyExtended ? "✓" : "✗")")
            print("   Motion: \(String(format: "%.3f", motionMag)) | H:\(String(format: "%.3f", horzMag)) V:\(String(format: "%.3f", vertMag)) | Moving: \(isMoving ? "YES" : "NO")")
            print("   Oscillation: Horiz=\(hasHorzOsc ? "YES" : "NO") Vert=\(hasVertOsc ? "YES" : "NO")")
            print("   Cooldown: \(lastConfirmationTime != nil ? "ACTIVE" : "NONE")")
            print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        }
        
        // =============================================================
        // DETECTION ORDER - Check MOTION signs FIRST, then STATIC signs
        // This prevents static signs from triggering during motion
        // =============================================================
        
        // TIER 1: Motion-based signs (check FIRST when hand is moving)
        
        // YES (fist + vertical pump)
        if let result = detectYes(frame), !isInCooldown(result.sign) {
            print("✅ DETECTED: \(result.sign) conf=\(String(format: "%.2f", result.confidence))")
            return result
        }
        
        // NO - DISABLED (replaced with PLEASE)
        // if let result = detectNo(frame), !isInCooldown(result.sign) {
        //     print("✅ DETECTED: \(result.sign) conf=\(String(format: "%.2f", result.confidence))")
        //     return result
        // }
        
        // PLEASE (circular motion on chest)
        if let result = detectPlease(frame), !isInCooldown(result.sign) {
            print("✅ DETECTED: \(result.sign) conf=\(String(format: "%.2f", result.confidence))")
            return result
        }
        
        // BYE (open hand wave - oscillating)
        if let result = detectBye(frame), !isInCooldown(result.sign) {
            print("✅ DETECTED: \(result.sign) conf=\(String(format: "%.2f", result.confidence))")
            return result
        }
        
        // HELLO (open hand single sweep)
        if let result = detectHello(frame), !isInCooldown(result.sign) {
            print("✅ DETECTED: \(result.sign) conf=\(String(format: "%.2f", result.confidence))")
            return result
        }
        
        // THANK YOU (open hand downward)
        if let result = detectThankYou(frame), !isInCooldown(result.sign) {
            print("✅ DETECTED: \(result.sign) conf=\(String(format: "%.2f", result.confidence))")
            return result
        }
        
        // TIER 2: Static signs (only check if hand is NOT moving much)
        // This prevents PEACE/STOP from triggering during gestures
        
        if !isMoving {
            // GOOD / Thumbs Up (fist + thumb)
            if let result = detectGood(frame), !isInCooldown(result.sign) {
                print("✅ DETECTED: \(result.sign) conf=\(String(format: "%.2f", result.confidence))")
                return result
            }
            
            // PEACE (index + middle only)
            if let result = detectPeace(frame), !isInCooldown(result.sign) {
                print("✅ DETECTED: \(result.sign) conf=\(String(format: "%.2f", result.confidence))")
                return result
            }
            
            // I LOVE YOU (thumb + index + pinky)
            if let result = detectILoveYou(frame), !isInCooldown(result.sign) {
                print("✅ DETECTED: \(result.sign) conf=\(String(format: "%.2f", result.confidence))")
                return result
            }
            
            // STOP (open palm, fingers together)
            if let result = detectStop(frame), !isInCooldown(result.sign) {
                print("✅ DETECTED: \(result.sign) conf=\(String(format: "%.2f", result.confidence))")
                return result
            }
        }
        
        // 10. PLEASE (circular motion on chest) - Requires open hand + circular motion
        if let result = detectPlease(frame), !isInCooldown(result.sign) { return result }
        
        return nil
    }
    
    /// Reset motion detection state (call when hand leaves frame)
    func reset() {
        frameHistory.removeAll()
        currentMotionSign = nil
        motionStartTime = nil
        motionConfidence = 0
    }
    
    /// Called when a sign is confirmed - triggers cooldown
    func signConfirmed(_ sign: String) {
        lastConfirmedSign = sign
        lastConfirmationTime = Date()
        // Clear history to prevent immediate re-detection
        frameHistory.removeAll()
    }
    
    /// Check if a sign is in cooldown period
    /// GLOBAL COOLDOWN: After ANY sign is confirmed, ALL signs are blocked for transitionDelay
    private func isInCooldown(_ sign: String) -> Bool {
        guard let lastTime = lastConfirmationTime else {
            return false
        }
        
        let elapsed = Date().timeIntervalSince(lastTime)
        
        // GLOBAL COOLDOWN: Block ALL signs for transitionDelay (3 seconds) after any detection
        // This prevents rapid transitions and double-word detection
        if elapsed < transitionDelay {
            if Int(elapsed * 10) % 10 == 0 { // Log occasionally
                print("⏳ COOLDOWN: \(String(format: "%.1f", transitionDelay - elapsed))s remaining before next detection")
            }
            return true
        }
        
        // Same sign needs even longer cooldown (full 5s)
        if let lastSign = lastConfirmedSign, sign == lastSign && elapsed < cooldownDuration {
            return true
        }
        
        return false
    }
    
    // MARK: - Frame Processing
    
    private func createHandFrame(landmarks: [(x: Float, y: Float, z: Float)]) -> HandFrame {
        let wrist = landmarks[LM.wrist]
        let wristPos = SIMD3<Float>(wrist.x, wrist.y, wrist.z)
        
        // Calculate palm center (average of MCP joints)
        let mcps = [landmarks[LM.indexMCP], landmarks[LM.middleMCP], 
                    landmarks[LM.ringMCP], landmarks[LM.pinkyMCP]]
        let palmX = mcps.map { $0.x }.reduce(0, +) / 4
        let palmY = mcps.map { $0.y }.reduce(0, +) / 4
        let palmZ = mcps.map { $0.z }.reduce(0, +) / 4
        let palmCenter = SIMD3<Float>(palmX, palmY, palmZ)
        
        // Determine finger states
        let fingers = analyzeFingers(landmarks: landmarks)
        
        return HandFrame(
            landmarks: landmarks,
            timestamp: Date(),
            wristPosition: wristPos,
            palmCenter: palmCenter,
            fingerStates: fingers
        )
    }
    
    private func analyzeFingers(landmarks: [(x: Float, y: Float, z: Float)]) -> FingerStates {
        let wrist = landmarks[LM.wrist]
        
        // Check each finger extension
        let thumbExtended = isFingerExtended(
            tip: landmarks[LM.thumbTip],
            pip: landmarks[LM.thumbIP],
            mcp: landmarks[LM.thumbMCP],
            wrist: wrist,
            isThumb: true
        )
        
        let indexExtended = isFingerExtended(
            tip: landmarks[LM.indexTip],
            pip: landmarks[LM.indexPIP],
            mcp: landmarks[LM.indexMCP],
            wrist: wrist
        )
        
        let middleExtended = isFingerExtended(
            tip: landmarks[LM.middleTip],
            pip: landmarks[LM.middlePIP],
            mcp: landmarks[LM.middleMCP],
            wrist: wrist
        )
        
        let ringExtended = isFingerExtended(
            tip: landmarks[LM.ringTip],
            pip: landmarks[LM.ringPIP],
            mcp: landmarks[LM.ringMCP],
            wrist: wrist
        )
        
        let pinkyExtended = isFingerExtended(
            tip: landmarks[LM.pinkyTip],
            pip: landmarks[LM.pinkyPIP],
            mcp: landmarks[LM.pinkyMCP],
            wrist: wrist,
            isPinky: true
        )
        
        // Debug logging for finger state detection (occasional)
        if Int.random(in: 0..<20) == 0 {
            let indexTip = landmarks[LM.indexTip]
            let indexPip = landmarks[LM.indexPIP]
            let pinkyTip = landmarks[LM.pinkyTip]
            let pinkyPip = landmarks[LM.pinkyPIP]
            let count = (thumbExtended ? 1 : 0) + (indexExtended ? 1 : 0) + (middleExtended ? 1 : 0) + (ringExtended ? 1 : 0) + (pinkyExtended ? 1 : 0)
            print("🖐️ FINGERS: T=\(thumbExtended ? "✓" : "✗") I=\(indexExtended ? "✓" : "✗") M=\(middleExtended ? "✓" : "✗") R=\(ringExtended ? "✓" : "✗") P=\(pinkyExtended ? "✓" : "✗") count=\(count)")
            // Show index and pinky details (key for I LOVE YOU)
            let iDist = distance(indexTip, wrist) / distance(indexPip, wrist)
            let pDist = distance(pinkyTip, wrist) / distance(pinkyPip, wrist)
            print("   I: tip.y=\(String(format: "%.3f", indexTip.y)) pip.y=\(String(format: "%.3f", indexPip.y)) ratio=\(String(format: "%.2f", iDist)) | P: tip.y=\(String(format: "%.3f", pinkyTip.y)) pip.y=\(String(format: "%.3f", pinkyPip.y)) ratio=\(String(format: "%.2f", pDist))")
        }
        
        return FingerStates(
            thumbExtended: thumbExtended,
            indexExtended: indexExtended,
            middleExtended: middleExtended,
            ringExtended: ringExtended,
            pinkyExtended: pinkyExtended
        )
    }
    
    private func isFingerExtended(
        tip: (x: Float, y: Float, z: Float),
        pip: (x: Float, y: Float, z: Float),
        mcp: (x: Float, y: Float, z: Float),
        wrist: (x: Float, y: Float, z: Float),
        isThumb: Bool = false,
        isPinky: Bool = false
    ) -> Bool {
        // For thumb, check horizontal extension
        if isThumb {
            let tipDist = abs(tip.x - wrist.x)
            return tipDist > 0.04
        }
        
        let tipToWrist = distance(tip, wrist)
        let pipToWrist = distance(pip, wrist)
        let mcpToWrist = distance(mcp, wrist)
        
        // CRITICAL: With Y inverted (1.0 - y), LOWER y = HIGHER position on screen
        // Extended finger: tip.y < pip.y (tip is ABOVE pip)
        // Curled finger: tip.y > pip.y (tip is BELOW pip)
        
        // Y-position check: tip above PIP indicates extension
        let tipAbovePip = tip.y < pip.y  // Basic check: tip is above pip
        let tipClearlyAbovePip = tip.y < pip.y - 0.015  // Stricter check
        
        // Distance check: tip farther from wrist than PIP
        let distRatio = tipToWrist / pipToWrist
        let distanceExtended = distRatio > 0.80  // Balanced threshold
        
        // For PINKY: more lenient (harder to detect)
        if isPinky {
            let tipAboveMcp = tip.y < mcp.y
            let pinkyDistOk = tipToWrist > mcpToWrist * 0.70 && tipToWrist > pipToWrist * 0.70
            return (pinkyDistOk && tipAboveMcp) || (distanceExtended && tipAbovePip)
        }
        
        // BALANCED approach: Either (distance AND Y-position) OR (very clear distance)
        // This catches both front camera perspectives and back camera perspectives
        let clearlyExtended = distRatio > 0.90  // Very clear extension by distance alone
        let normalExtended = distanceExtended && tipAbovePip  // Normal check
        let yBasedExtended = tipClearlyAbovePip && distRatio > 0.75  // Y-based with loose distance
        
        return clearlyExtended || normalExtended || yBasedExtended
    }
    
    // MARK: - Motion Analysis Helpers
    
    private func getRecentMotion(frames: Int = 10) -> SIMD3<Float> {
        guard frameHistory.count >= frames else { return .zero }
        
        let recent = Array(frameHistory.suffix(frames))
        let start = recent.first!.palmCenter
        let end = recent.last!.palmCenter
        
        return end - start
    }
    
    private func getMotionDirection(frames: Int = 10) -> SIMD3<Float> {
        let motion = getRecentMotion(frames: frames)
        let length = simd_length(motion)
        return length > 0.001 ? motion / length : .zero
    }
    
    private func getMotionMagnitude(frames: Int = 10) -> Float {
        return simd_length(getRecentMotion(frames: frames))
    }
    
    private func getVerticalMotion(frames: Int = 10) -> Float {
        return getRecentMotion(frames: frames).y
    }
    
    private func getHorizontalMotion(frames: Int = 10) -> Float {
        return getRecentMotion(frames: frames).x
    }
    
    private func getForwardMotion(frames: Int = 10) -> Float {
        return getRecentMotion(frames: frames).z
    }
    
    private func hasOscillation(axis: KeyPath<SIMD3<Float>, Float>, minCycles: Int = 2) -> Bool {
        guard frameHistory.count >= 8 else { return false }
        
        // Use more frames and smoother detection
        let recent = Array(frameHistory.suffix(20))
        var directionChanges = 0
        var lastDirection: Float = 0
        var consecutiveSameDir = 0
        
        for i in 1..<recent.count {
            let delta = recent[i].palmCenter[keyPath: axis] - recent[i-1].palmCenter[keyPath: axis]
            // Lower threshold to detect smaller movements
            if abs(delta) > 0.002 {
                let direction: Float = delta > 0 ? 1.0 : -1.0
                if direction == lastDirection {
                    consecutiveSameDir += 1
                } else if lastDirection != 0 {
                    // Only count direction change if we had at least 2 frames in same direction
                    if consecutiveSameDir >= 1 {
                        directionChanges += 1
                    }
                    consecutiveSameDir = 0
                }
                lastDirection = direction
            }
        }
        
        // Need at least minCycles * 2 direction changes (back and forth)
        return directionChanges >= minCycles * 2 - 1
    }
    
    private func hasCircularMotion(minRadius: Float = 0.05) -> Bool {
        // STRICT: Need more frames for reliable circular detection
        guard frameHistory.count >= 25 else { return false }
        
        let recent = Array(frameHistory.suffix(30))
        
        // Check for circular pattern by tracking quadrants visited IN ORDER
        var quadrantsVisited: Set<Int> = []
        var quadrantSequence: [Int] = []
        let center = recent.map { $0.palmCenter }.reduce(.zero, +) / Float(recent.count)
        
        // Track motion magnitude and ensure it's consistent (circular = steady motion)
        var maxDist: Float = 0
        var minDist: Float = Float.infinity
        var validFrames = 0
        
        for frame in recent {
            let offset = frame.palmCenter - center
            let dist = simd_length(SIMD2<Float>(offset.x, offset.y))
            
            // Only count if offset is significant (stricter threshold)
            guard dist > minRadius * 1.5 else { continue }
            
            validFrames += 1
            maxDist = max(maxDist, dist)
            minDist = min(minDist, dist)
            
            let quadrant: Int
            if offset.x >= 0 && offset.y >= 0 { quadrant = 0 }
            else if offset.x < 0 && offset.y >= 0 { quadrant = 1 }
            else if offset.x < 0 && offset.y < 0 { quadrant = 2 }
            else { quadrant = 3 }
            quadrantsVisited.insert(quadrant)
            
            // Track sequence for order checking
            if quadrantSequence.isEmpty || quadrantSequence.last != quadrant {
                quadrantSequence.append(quadrant)
            }
        }
        
        // STRICT requirements for circular motion:
        // 1. Must visit ALL 4 quadrants
        // 2. Must have sufficient radius (increased)
        // 3. Must have enough valid frames
        // 4. Radius should be relatively consistent (not just random movement)
        let hasAllQuadrants = quadrantsVisited.count >= 4
        let hasSufficientRadius = maxDist > minRadius * 2
        let hasEnoughFrames = validFrames >= 15
        let hasConsistentRadius = minDist > maxDist * 0.3  // Motion is roughly circular
        
        return hasAllQuadrants && hasSufficientRadius && hasEnoughFrames && hasConsistentRadius
    }
    
    // MARK: - Sign Detection Methods
    
    /// Check if the current frame shows a PEACE sign (index + middle extended, others curled)
    /// CRITICAL: Thumb must NOT be extended - distinguishes from other signs
    private func isPeaceSign(_ frame: HandFrame) -> Bool {
        // PEACE = Index + Middle ONLY (thumb should be curled or neutral)
        let thumbCurled = !frame.fingerStates.thumbExtended
        let indexOut = frame.fingerStates.indexExtended
        let middleOut = frame.fingerStates.middleExtended
        let ringCurled = !frame.fingerStates.ringExtended
        let pinkyCurled = !frame.fingerStates.pinkyExtended
        
        // Must have index + middle, WITHOUT thumb
        let hasPeaceFingers = indexOut && middleOut && ringCurled && pinkyCurled && thumbCurled
        let extCount = frame.fingerStates.extendedCount
        // 2-3 fingers OK (thumb detection can be inconsistent)
        let correctCount = extCount >= 2 && extCount <= 3
        
        // Method 2: Geometric detection for back camera / Meta Glasses
        // Peace sign has index and middle tips far from wrist, ring and pinky tips close to wrist
        let indexTip = frame.landmarks[LM.indexTip]
        let middleTip = frame.landmarks[LM.middleTip]
        let ringTip = frame.landmarks[LM.ringTip]
        let pinkyTip = frame.landmarks[LM.pinkyTip]
        let wrist = frame.landmarks[LM.wrist]
        
        let indexToWrist = distance(indexTip, wrist)
        let middleToWrist = distance(middleTip, wrist)
        let ringToWrist = distance(ringTip, wrist)
        let pinkyToWrist = distance(pinkyTip, wrist)
        
        // Index and middle should be significantly farther from wrist than ring and pinky
        let indexMiddleAvg = (indexToWrist + middleToWrist) / 2
        let ringPinkyAvg = (ringToWrist + pinkyToWrist) / 2
        
        // Peace: index+middle extended (far), ring+pinky curled (close)
        // Relaxed ratio for front camera compatibility
        let hasGeometricPeace = indexMiddleAvg > ringPinkyAvg * 1.08  // Relaxed from 1.15
        
        // Also check that index and middle are close together (V shape)
        let indexMiddleDist = distance(indexTip, middleTip)
        let indexMiddleClose = indexMiddleDist < indexToWrist * 0.6  // Relaxed from 0.5
        
        // Method 3: Check that pinky is NOT spread (distinguishes from I LOVE YOU)
        let pinkyRingDist = distance(pinkyTip, ringTip)
        let middleRingDist = distance(middleTip, ringTip)
        let pinkyNotSpread = pinkyRingDist < middleRingDist * 1.8  // Relaxed from 1.5
        
        // Debug logging for PEACE detection
        if Int.random(in: 0..<30) == 0 {  // Log occasionally
            print("✌️ PEACE check: fingers=\(hasPeaceFingers) geo=\(hasGeometricPeace) close=\(indexMiddleClose) pinkyOK=\(pinkyNotSpread) ratio=\(String(format: "%.2f", indexMiddleAvg/ringPinkyAvg))")
        }
        
        // Return true if either method detects Peace (with pinky not spread check)
        let fingerStateMatch = hasPeaceFingers && correctCount
        let geometricMatch = hasGeometricPeace && indexMiddleClose && pinkyNotSpread
        
        return (fingerStateMatch || geometricMatch) && pinkyNotSpread
    }
    
    /// Check if recent frames show Peace sign pattern
    private func hasPeacePattern(in recentFrames: [HandFrame]) -> Bool {
        let peaceFrames = recentFrames.filter { isPeaceSign($0) }.count
        return peaceFrames >= 2  // 2 of last frames show Peace
    }
    
    /// PEACE / V / 2: Index and middle finger extended, others curled
    /// STATIC sign - requires hand to be STILL
    private func detectPeace(_ frame: HandFrame) -> MotionResult? {
        // Check if current frame is a Peace sign
        guard isPeaceSign(frame) else { return nil }
        
        // CRITICAL: Require LOW motion - static sign should not trigger during gestures
        let motion = getMotionMagnitude(frames: 8)
        guard motion < 0.025 else { return nil }  // Relaxed from 0.015
        
        // Check stability over recent frames (need 3 of last 6 frames to match)
        let recentFrames = Array(frameHistory.suffix(6))
        let peaceFrames = recentFrames.filter { isPeaceSign($0) }.count
        
        if peaceFrames >= 3 {  // Relaxed from 4
            print("✌️ PEACE DETECTED via MotionSignDetector")
            return MotionResult(sign: "PEACE", confidence: 0.90, isComplete: true)
        }
        
        return nil
    }
    
    /// Check if this is a STOP sign (open palm, fingers together, facing forward)
    /// Works for front camera (selfie), back camera, and Meta Glasses
    private func isStopSign(_ frame: HandFrame) -> Bool {
        // STOP sign: All 5 fingers extended AND fingers close together (not spread)
        let extCount = frame.fingerStates.extendedCount
        guard extCount >= 4 else { return false } // Need 4-5 fingers extended
        
        // Get fingertip positions
        let indexTip = frame.landmarks[LM.indexTip]
        let middleTip = frame.landmarks[LM.middleTip]
        let ringTip = frame.landmarks[LM.ringTip]
        let pinkyTip = frame.landmarks[LM.pinkyTip]
        let wrist = frame.landmarks[LM.wrist]
        
        // All fingertips should be roughly same distance from wrist (fingers straight)
        let indexToWrist = distance(indexTip, wrist)
        let middleToWrist = distance(middleTip, wrist)
        let ringToWrist = distance(ringTip, wrist)
        let pinkyToWrist = distance(pinkyTip, wrist)
        
        // Check fingers are all extended (similar distances from wrist)
        let avgDist = (indexToWrist + middleToWrist + ringToWrist + pinkyToWrist) / 4
        let allExtended = indexToWrist > avgDist * 0.8 && 
                          middleToWrist > avgDist * 0.8 && 
                          ringToWrist > avgDist * 0.7 &&  // Ring/pinky slightly shorter OK
                          pinkyToWrist > avgDist * 0.6
        
        // STOP sign has fingers TOGETHER (not spread like HELLO wave)
        // Check that adjacent fingers are close to each other
        let indexMiddleDist = distance(indexTip, middleTip)
        let middleRingDist = distance(middleTip, ringTip)
        let ringPinkyDist = distance(ringTip, pinkyTip)
        
        // Fingers should be close together (less than 30% of hand length)
        let handLength = avgDist
        let fingersTogether = indexMiddleDist < handLength * 0.35 &&
                              middleRingDist < handLength * 0.35 &&
                              ringPinkyDist < handLength * 0.35
        
        // Also check hand is relatively still (STOP is a static hold, not waving)
        let recentMotion = getMotionMagnitude(frames: 5)
        let isStill = recentMotion < 0.03  // Less motion than wave
        
        return allExtended && fingersTogether && (isStill || extCount == 5)
    }
    
    /// STOP: Open palm with fingers together, held STILL
    /// STATIC sign - requires hand to be VERY still
    private func detectStop(_ frame: HandFrame) -> MotionResult? {
        guard isStopSign(frame) else { return nil }
        
        // CRITICAL: Require VERY LOW motion - static sign should not trigger during gestures
        let motion = getMotionMagnitude(frames: 8)
        guard motion < 0.012 else { return nil }  // Must be very still
        
        // Block if this looks like Peace or I Love You
        if isPeaceSign(frame) { return nil }
        
        // Check stability over recent frames (need 4 of last 6 frames to match)
        let recentFrames = Array(frameHistory.suffix(6))
        let stopFrames = recentFrames.filter { isStopSign($0) }.count
        
        if stopFrames >= 4 {
            return MotionResult(sign: "STOP", confidence: 0.88, isComplete: true)
        }
        
        return nil
    }
    
    /// Check if recent frames show I LOVE YOU pattern (thumb + index + pinky extended)
    private func hasILoveYouPattern(in recentFrames: [HandFrame]) -> Bool {
        let ilyFrames = recentFrames.filter { frame in
            frame.fingerStates.thumbExtended && 
            frame.fingerStates.indexExtended && 
            frame.fingerStates.pinkyExtended &&
            !frame.fingerStates.middleExtended &&
            !frame.fingerStates.ringExtended
        }.count
        return ilyFrames >= 2
    }
    
    /// Check if recent frames show potential I LOVE YOU formation (pinky extending)
    private func hasPotentialILoveYou(in recentFrames: [HandFrame]) -> Bool {
        // Check for pinky + thumb + index pattern even if other fingers vary
        let potentialFrames = recentFrames.filter { frame in
            frame.fingerStates.thumbExtended && 
            frame.fingerStates.indexExtended && 
            frame.fingerStates.pinkyExtended
        }.count
        return potentialFrames >= 2
    }
    
    /// HELLO: Open hand + horizontal sweep (NOT oscillating)
    /// SIMPLIFIED: Open hand + single horizontal motion (relaxed thresholds)
    private func detectHello(_ frame: HandFrame) -> MotionResult? {
        // Open hand (4+ fingers)
        guard frame.fingerStates.extendedCount >= 4 else { return nil }
        
        // Horizontal motion (lowered threshold)
        let horizontalMotion = abs(getHorizontalMotion(frames: 12))
        let verticalMotion = abs(getVerticalMotion(frames: 12))
        
        guard horizontalMotion > 0.025 else { return nil }  // Lowered from 0.03
        guard horizontalMotion > verticalMotion else { return nil }
        
        // NOT oscillating (that's BYE) - check for 2+ cycles
        let isOscillating = hasOscillation(axis: \.x, minCycles: 2)
        guard !isOscillating else { return nil }
        
        let confidence = min(1.0, horizontalMotion / 0.04 + 0.5)
        return MotionResult(sign: "HELLO", confidence: confidence, isComplete: confidence > 0.65)
    }
    
    /// THANK YOU: Open hand + downward motion
    /// SIMPLIFIED: Open hand + vertical (down) motion (relaxed thresholds)
    private func detectThankYou(_ frame: HandFrame) -> MotionResult? {
        // Open hand (4+ fingers)
        guard frame.fingerStates.extendedCount >= 4 else { return nil }
        
        // Need downward motion (positive Y) - lowered threshold
        let verticalMotion = getVerticalMotion(frames: 12)
        let horizontalMotion = abs(getHorizontalMotion(frames: 12))
        
        // Must move DOWN (lowered threshold)
        guard verticalMotion > 0.02 else { return nil }  // Lowered from 0.03
        
        // Vertical should dominate horizontal
        guard verticalMotion > horizontalMotion else { return nil }
        
        // NOT oscillating (that's YES)
        let notOscillating = !hasOscillation(axis: \.y, minCycles: 2)
        guard notOscillating else { return nil }
        
        let confidence = min(1.0, verticalMotion / 0.04 + 0.5)
        return MotionResult(sign: "THANK YOU", confidence: confidence, isComplete: confidence > 0.65)
    }
    
    /// PLEASE: Open hand rubbing chest in circular OR back-and-forth motion
    /// Simplified: Open hand + continuous motion (rubbing pattern)
    private func detectPlease(_ frame: HandFrame) -> MotionResult? {
        // PLEASE requires open hand (4+ fingers)
        guard frame.fingerStates.extendedCount >= 4 else { return nil }
        
        // Need continuous motion (rubbing) - not too much, not too little
        let motionMag = getMotionMagnitude(frames: 15)
        guard motionMag > 0.015 && motionMag < 0.12 else { return nil }
        
        // Check for EITHER circular motion OR mixed horizontal+vertical motion (rubbing)
        let hasCircular = hasCircularMotion(minRadius: 0.015)
        let horzMag = abs(getHorizontalMotion(frames: 15))
        let vertMag = abs(getVerticalMotion(frames: 15))
        let hasMixedMotion = horzMag > 0.01 && vertMag > 0.01  // Both directions = rubbing
        
        guard hasCircular || hasMixedMotion else { return nil }
        
        // Check stability over recent frames - open hand maintained
        let recentFrames = Array(frameHistory.suffix(10))
        let openHandFrames = recentFrames.filter { $0.fingerStates.extendedCount >= 4 }.count
        guard openHandFrames >= 6 else { return nil }
        
        print("🙏 PLEASE detected: circular=\(hasCircular) mixed=\(hasMixedMotion) motion=\(String(format: "%.3f", motionMag))")
        return MotionResult(sign: "PLEASE", confidence: 0.85, isComplete: true)
    }
    
    /// YES: Fist pumping up and down
    /// SIMPLIFIED: Fist + vertical motion
    private func detectYes(_ frame: HandFrame) -> MotionResult? {
        // YES requires closed fist (0-2 fingers max)
        guard frame.fingerStates.extendedCount <= 2 else { return nil }
        
        // Must have VERTICAL motion
        let verticalMag = abs(getVerticalMotion(frames: 10))
        let horizontalMag = abs(getHorizontalMotion(frames: 10))
        
        // Vertical must dominate horizontal (1.5x is enough)
        guard verticalMag > horizontalMag * 1.5 else { return nil }
        guard verticalMag > 0.03 else { return nil }
        
        // Check for vertical oscillation (2 cycles minimum)
        if hasOscillation(axis: \.y, minCycles: 2) {
            let confidence = min(1.0, verticalMag / 0.05 + 0.4)
            return MotionResult(sign: "YES", confidence: confidence, isComplete: confidence > 0.70)
        }
        
        return nil
    }
    
    /// NO: Finger wagging side to side
    /// SIMPLIFIED: 1-3 fingers + horizontal motion (relaxed thresholds)
    private func detectNo(_ frame: HandFrame) -> MotionResult? {
        // NO requires 1-3 fingers (pointing/wagging)
        guard frame.fingerStates.extendedCount >= 1 && frame.fingerStates.extendedCount <= 3 else { return nil }
        
        // Must have HORIZONTAL motion (lowered threshold)
        let horizontalMag = abs(getHorizontalMotion(frames: 12))
        let verticalMag = abs(getVerticalMotion(frames: 12))
        
        // Horizontal must dominate vertical
        guard horizontalMag > verticalMag else { return nil }
        guard horizontalMag > 0.02 else { return nil }  // Lowered from 0.03
        
        // Check for horizontal oscillation (just 1 cycle needed)
        if hasOscillation(axis: \.x, minCycles: 1) {
            let confidence = min(1.0, horizontalMag / 0.04 + 0.5)
            return MotionResult(sign: "NO", confidence: confidence, isComplete: confidence > 0.65)
        }
        
        return nil
    }
    
    /// GOOD / Thumbs Up: Fist with thumb extended
    /// STATIC sign - requires hand to be still
    private func detectGood(_ frame: HandFrame) -> MotionResult? {
        // CRITICAL: Require LOW motion - static sign
        let motion = getMotionMagnitude(frames: 8)
        guard motion < 0.015 else { return nil }
        
        // Thumb must be extended
        guard frame.fingerStates.thumbExtended else { return nil }
        
        // Max 2 fingers extended
        let extCount = frame.fingerStates.extendedCount
        guard extCount <= 2 else { return nil }
        
        // Index and middle should NOT be extended
        guard !frame.fingerStates.indexExtended else { return nil }
        guard !frame.fingerStates.middleExtended else { return nil }
        
        // Check stability (need 3 of last 5 frames)
        let recentFrames = Array(frameHistory.suffix(5))
        let goodFrames = recentFrames.filter { f in
            f.fingerStates.thumbExtended && f.fingerStates.extendedCount <= 2
        }.count
        
        if goodFrames >= 3 {
            return MotionResult(sign: "GOOD", confidence: 0.88, isComplete: true)
        }
        
        return nil
    }
    
    /// BYE / GOODBYE: Open hand waving side to side
    /// SIMPLIFIED: Open hand + horizontal oscillation (relaxed thresholds)
    private func detectBye(_ frame: HandFrame) -> MotionResult? {
        // BYE requires open hand (4+ fingers)
        guard frame.fingerStates.extendedCount >= 4 else { return nil }
        
        // Must have horizontal motion with oscillation (lowered thresholds)
        let horizontalMag = abs(getHorizontalMotion(frames: 12))
        let verticalMag = abs(getVerticalMotion(frames: 12))
        
        // Horizontal must dominate
        guard horizontalMag > verticalMag else { return nil }
        guard horizontalMag > 0.02 else { return nil }  // Lowered from 0.03
        
        // Require oscillation (just 1 cycle)
        let hasWave = hasOscillation(axis: \.x, minCycles: 1)
        guard hasWave else { return nil }
        
        let confidence = min(1.0, horizontalMag / 0.04 + 0.5)
        return MotionResult(sign: "BYE", confidence: confidence, isComplete: confidence > 0.65)
    }
    
    /// I LOVE YOU: Thumb, index, and pinky extended (ILY hand shape)
    /// STATIC sign - requires hand to be still
    private func detectILoveYou(_ frame: HandFrame) -> MotionResult? {
        // CRITICAL: Require LOW motion - static sign (relaxed for front camera)
        let motion = getMotionMagnitude(frames: 8)
        guard motion < 0.025 else { return nil }  // Relaxed from 0.015
        
        // Block if this is a Peace sign
        if isPeaceSign(frame) { return nil }
        
        let recentFrames = Array(frameHistory.suffix(5))
        if hasPeacePattern(in: recentFrames) { return nil }
        
        // ILY hand shape: thumb, index, and pinky extended; middle and ring curled
        let extCount = frame.fingerStates.extendedCount
        
        // STRICT: Need exactly 3 fingers extended (thumb + index + pinky)
        // This prevents Peace sign (2 fingers: index + middle) from matching
        guard extCount >= 2 && extCount <= 4 else { return nil }
        
        let thumbOut = frame.fingerStates.thumbExtended
        let indexOut = frame.fingerStates.indexExtended
        let middleCurled = !frame.fingerStates.middleExtended
        let ringCurled = !frame.fingerStates.ringExtended
        let pinkyOut = frame.fingerStates.pinkyExtended
        
        // CRITICAL: Middle finger MUST be curled - this distinguishes from Peace sign
        // Peace = index + middle extended, ILY = index extended + middle curled
        guard middleCurled else { return nil }
        
        // CRITICAL: Thumb MUST be extended - Peace sign has thumb curled
        guard thumbOut else { return nil }
        
        // Primary check: thumb + index + pinky configuration
        let hasILYFingers = thumbOut && indexOut && middleCurled && ringCurled && pinkyOut
        
        // Alternative check for back camera: use geometric analysis
        // Even if pinky isn't detected as "extended", check if it's spread out from ring finger
        let pinkyTip = frame.landmarks[LM.pinkyTip]
        let ringTip = frame.landmarks[LM.ringTip]
        let indexTip = frame.landmarks[LM.indexTip]
        let middleTip = frame.landmarks[LM.middleTip]
        let wrist = frame.landmarks[LM.wrist]
        
        let pinkyRingDist = distance(pinkyTip, ringTip)
        let pinkyIndexDist = distance(pinkyTip, indexTip)
        let middleRingDist = distance(middleTip, ringTip)
        
        // Additional check: middle finger should be closer to wrist than index (curled)
        let middleToWrist = distance(middleTip, wrist)
        let indexToWrist = distance(indexTip, wrist)
        let middleIsCurled = middleToWrist < indexToWrist * 1.05  // Relaxed from 0.95 for front camera
        
        // Pinky is spread if it's far from ring AND pinky tip is far from wrist (extended outward)
        let pinkyToWrist = distance(pinkyTip, wrist)
        let ringToWrist = distance(ringTip, wrist)
        // Relaxed thresholds for front camera compatibility
        let pinkySpread = pinkyRingDist > middleRingDist * 1.1 && pinkyToWrist > ringToWrist * 0.75  // Relaxed from 1.3, 0.9
        
        // Alternative ILY detection: thumb + index extended, middle/ring curled, pinky spread out
        // Added middleIsCurled geometric check to prevent Peace sign false positives
        let hasILYGeometry = thumbOut && indexOut && middleCurled && ringCurled && pinkySpread && middleIsCurled
        
        // Debug logging for I LOVE YOU detection
        if Int.random(in: 0..<30) == 0 {
            print("🤟 ILY check: T=\(thumbOut) I=\(indexOut) M=\(!middleCurled) R=\(!ringCurled) P=\(pinkyOut) ext=\(extCount)")
            print("   geometry: pinkySpread=\(pinkySpread) middleCurled=\(middleIsCurled) hasFingers=\(hasILYFingers) hasGeo=\(hasILYGeometry)")
        }
        
        if hasILYFingers || hasILYGeometry {
            // Pinky should be spread from index (relaxed threshold)
            guard pinkyIndexDist > 0.03 else { return nil }  // Relaxed from 0.04
            
            // Check stability over recent frames (relaxed to 2 frames)
            let recentFrames = Array(frameHistory.suffix(3))
            var matchingFrames = 0
            
            for f in recentFrames {
                // CRITICAL: Skip frames where middle finger is extended (Peace sign)
                guard !f.fingerStates.middleExtended else { continue }
                // CRITICAL: Skip frames where thumb is not extended
                guard f.fingerStates.thumbExtended else { continue }
                
                let fPinkyTip = f.landmarks[LM.pinkyTip]
                let fRingTip = f.landmarks[LM.ringTip]
                let fMiddleTip = f.landmarks[LM.middleTip]
                let fIndexTip = f.landmarks[LM.indexTip]
                let fWrist = f.landmarks[LM.wrist]
                
                let fPinkyRingDist = distance(fPinkyTip, fRingTip)
                let fMiddleRingDist = distance(fMiddleTip, fRingTip)
                
                // Geometric check: middle finger closer to wrist than index (curled)
                let fMiddleToWrist = distance(fMiddleTip, fWrist)
                let fIndexToWrist = distance(fIndexTip, fWrist)
                let fMiddleIsCurled = fMiddleToWrist < fIndexToWrist * 1.05  // Relaxed for front camera
                
                // Stricter pinky spread check
                let fPinkyToWrist = distance(fPinkyTip, fWrist)
                let fRingToWrist = distance(fRingTip, fWrist)
                let fPinkySpread = fPinkyRingDist > fMiddleRingDist * 1.1 && fPinkyToWrist > fRingToWrist * 0.75  // Relaxed
                
                let fHasILYFingers = f.fingerStates.thumbExtended && 
                                      f.fingerStates.indexExtended && 
                                      !f.fingerStates.middleExtended && 
                                      !f.fingerStates.ringExtended && 
                                      f.fingerStates.pinkyExtended
                
                let fHasILYGeometry = f.fingerStates.thumbExtended && 
                                       f.fingerStates.indexExtended && 
                                       !f.fingerStates.middleExtended && 
                                       !f.fingerStates.ringExtended && 
                                       fPinkySpread && fMiddleIsCurled
                
                if fHasILYFingers || fHasILYGeometry {
                    matchingFrames += 1
                }
            }
            
            // Need at least 2 of last 3 frames to match
            if matchingFrames >= 2 {
                return MotionResult(sign: "I LOVE YOU", confidence: 0.95, isComplete: true)
            } else if matchingFrames >= 1 {
                return MotionResult(sign: "I LOVE YOU", confidence: 0.75, isComplete: false)
            }
        }
        
        return nil
    }
    
    // MARK: - Utility
    
    private func distance(_ a: (x: Float, y: Float, z: Float), _ b: (x: Float, y: Float, z: Float)) -> Float {
        let dx = a.x - b.x
        let dy = a.y - b.y
        let dz = a.z - b.z
        return sqrt(dx*dx + dy*dy + dz*dz)
    }
}
