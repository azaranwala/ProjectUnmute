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
    private let cooldownDuration: TimeInterval = 2.5  // 2.5 seconds cooldown
    
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
        
        // Check I LOVE YOU first - it's a static sign that should take priority
        if let result = detectILoveYou(frame), !isInCooldown(result.sign) { return result }
        
        // Check for each dynamic sign pattern (with cooldown filtering)
        // Order matters: check more specific signs first
        if let result = detectHello(frame), !isInCooldown(result.sign) { return result }
        if let result = detectYes(frame), !isInCooldown(result.sign) { return result }
        if let result = detectNo(frame), !isInCooldown(result.sign) { return result }
        if let result = detectBye(frame), !isInCooldown(result.sign) { return result }
        if let result = detectGood(frame), !isInCooldown(result.sign) { return result }
        // PLEASE and THANK YOU last - they have loose requirements
        if let result = detectThankYou(frame), !isInCooldown(result.sign) { return result }
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
    private func isInCooldown(_ sign: String) -> Bool {
        guard let lastSign = lastConfirmedSign,
              let lastTime = lastConfirmationTime else {
            return false
        }
        
        let elapsed = Date().timeIntervalSince(lastTime)
        
        // Same sign needs full cooldown
        if sign == lastSign && elapsed < cooldownDuration {
            return true
        }
        
        // Different sign needs shorter cooldown (0.5s) to allow transitions
        if sign != lastSign && elapsed < 0.5 {
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
            return tipDist > 0.06
        }
        
        // For fingers, tip should be further from wrist than PIP
        let tipToWrist = distance(tip, wrist)
        let pipToWrist = distance(pip, wrist)
        let mcpToWrist = distance(mcp, wrist)
        
        // Pinky is shorter and needs more lenient thresholds
        // Also check if tip is extended outward from MCP (spread out)
        if isPinky {
            // Pinky extended if:
            // 1. Tip is farther from wrist than MCP (finger pointing outward)
            // 2. OR tip is above PIP (finger not curled)
            let tipFartherThanMcp = tipToWrist > mcpToWrist * 0.85
            let tipAbovePip = tip.y < pip.y + 0.05  // More lenient for pinky
            let tipFartherThanPip = tipToWrist > pipToWrist * 0.85  // More lenient
            
            return (tipFartherThanMcp && tipAbovePip) || (tipFartherThanPip && tipAbovePip)
        }
        
        // For other fingers, tip should be further from wrist than PIP
        // Also check that tip is above (lower Y in image coords) PIP
        let tipAbovePip = tip.y < pip.y + 0.02
        
        return tipToWrist > pipToWrist * 0.9 && tipAbovePip
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
        guard frameHistory.count >= 10 else { return false }
        
        let recent = Array(frameHistory.suffix(15))
        var directionChanges = 0
        var lastDirection: Float = 0
        
        for i in 1..<recent.count {
            let delta = recent[i].palmCenter[keyPath: axis] - recent[i-1].palmCenter[keyPath: axis]
            if abs(delta) > 0.005 {
                let direction: Float = delta > 0 ? 1.0 : -1.0
                if lastDirection != 0 && direction != lastDirection {
                    directionChanges += 1
                }
                lastDirection = direction
            }
        }
        
        return directionChanges >= minCycles * 2
    }
    
    private func hasCircularMotion(minRadius: Float = 0.05) -> Bool {
        guard frameHistory.count >= 20 else { return false }
        
        let recent = Array(frameHistory.suffix(25))
        
        // Check for circular pattern by tracking quadrants visited
        var quadrantsVisited: Set<Int> = []
        let center = recent.map { $0.palmCenter }.reduce(.zero, +) / Float(recent.count)
        
        // Also check that motion has sufficient radius
        var maxDist: Float = 0
        for frame in recent {
            let offset = frame.palmCenter - center
            let dist = simd_length(SIMD2<Float>(offset.x, offset.y))
            maxDist = max(maxDist, dist)
            
            // Only count quadrant if offset is significant
            guard dist > minRadius else { continue }
            
            let quadrant: Int
            if offset.x >= 0 && offset.y >= 0 { quadrant = 0 }
            else if offset.x < 0 && offset.y >= 0 { quadrant = 1 }
            else if offset.x < 0 && offset.y < 0 { quadrant = 2 }
            else { quadrant = 3 }
            quadrantsVisited.insert(quadrant)
        }
        
        // Must visit ALL 4 quadrants with sufficient radius for true circular motion
        return quadrantsVisited.count >= 4 && maxDist > minRadius
    }
    
    // MARK: - Sign Detection Methods
    
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
    
    /// HELLO: Flat hand salute from forehead outward
    /// Detected as: open hand at forehead level with outward sweep motion
    private func detectHello(_ frame: HandFrame) -> MotionResult? {
        // Hand should be open (all fingers extended)
        guard frame.fingerStates.allExtended || frame.fingerStates.extendedCount >= 4 else {
            return nil
        }
        
        // Check for I LOVE YOU pattern - suppress HELLO if detected
        let recentFrames = Array(frameHistory.suffix(10))
        if hasPotentialILoveYou(in: recentFrames) {
            return nil  // User might be forming I LOVE YOU
        }
        
        // Require stable open hand for multiple frames
        let openHandFrames = recentFrames.filter { $0.fingerStates.extendedCount >= 4 }.count
        guard openHandFrames >= 6 else { return nil }  // Need 6 of last 10 frames as open hand
        
        // HELLO is an outward sweep - check for horizontal motion
        // Note: Vision doesn't provide Z, so we detect as horizontal sweep from center
        let horizontalMotion = abs(getHorizontalMotion(frames: 10))
        let verticalMotion = abs(getVerticalMotion(frames: 10))
        
        // HELLO: horizontal sweep motion (salute outward)
        let hasWaveMotion = horizontalMotion > 0.04
        
        // Hand should be relatively high (near forehead/face level)
        let isHighPosition = frame.palmCenter.y < 0.45
        
        // Distinguish from NO: HELLO is a single sweep, not rapid oscillation
        let notOscillating = !hasOscillation(axis: \.x, minCycles: 2)
        
        // Check that we don't have strong vertical motion (would be YES or GOOD)
        let notVerticalDominant = verticalMotion < horizontalMotion * 1.5
        
        if hasWaveMotion && isHighPosition && notVerticalDominant && notOscillating {
            let confidence = min(1.0, horizontalMotion / 0.06 + 0.4)
            return MotionResult(sign: "HELLO", confidence: confidence, isComplete: confidence > 0.70)
        }
        
        return nil
    }
    
    /// THANK YOU: Flat hand from chin outward (single forward motion, not oscillating)
    /// Note: Vision doesn't provide Z, so we detect outward motion via downward arc from chin
    private func detectThankYou(_ frame: HandFrame) -> MotionResult? {
        // Hand should be open (4+ fingers to be more specific)
        guard frame.fingerStates.extendedCount >= 4 else {
            return nil
        }
        
        // Check for I LOVE YOU pattern - suppress THANK YOU if detected
        let recentFrames = Array(frameHistory.suffix(10))
        if hasPotentialILoveYou(in: recentFrames) {
            return nil
        }
        
        // Check for outward motion from chin area
        // Since Vision doesn't provide Z, detect as: hand starts high, moves down and outward
        let verticalMotion = getVerticalMotion(frames: 10)  // Positive = downward
        let horizontalMotion = abs(getHorizontalMotion(frames: 10))
        
        // THANK YOU: downward arc motion (chin to outward)
        // Require some downward motion (sign moves from chin outward which appears as down in 2D)
        let hasOutwardArc = verticalMotion > 0.03 || horizontalMotion > 0.03
        
        // Hand should be in upper area (chin/face region)
        let nearCenter = abs(frame.palmCenter.x - 0.5) < 0.35
        let inUpperArea = frame.palmCenter.y < 0.55
        
        // Should NOT be oscillating (that would be NO, BYE, or YES)
        let notOscillatingX = !hasOscillation(axis: \.x, minCycles: 2)
        let notOscillatingY = !hasOscillation(axis: \.y, minCycles: 2)
        
        // Require stable open hand
        let openHandFrames = recentFrames.filter { $0.fingerStates.extendedCount >= 4 }.count
        guard openHandFrames >= 5 else { return nil }
        
        if nearCenter && inUpperArea && hasOutwardArc && notOscillatingX && notOscillatingY {
            let motionMag = max(verticalMotion, horizontalMotion)
            let confidence = min(1.0, motionMag / 0.05 + 0.4)
            return MotionResult(sign: "THANK YOU", confidence: confidence, isComplete: confidence > 0.70)
        }
        
        return nil
    }
    
    /// PLEASE: Flat hand circles on chest - ONLY circular motion, no fallback
    private func detectPlease(_ frame: HandFrame) -> MotionResult? {
        // Hand should be open/flat (4+ fingers to be more specific)
        guard frame.fingerStates.extendedCount >= 4 else {
            return nil
        }
        
        // Hand should be in chest/torso area - stricter bounds
        let inChestArea = frame.palmCenter.y > 0.4 && frame.palmCenter.y < 0.75
        let inCenterX = frame.palmCenter.x > 0.25 && frame.palmCenter.x < 0.75
        
        guard inChestArea && inCenterX else { return nil }
        
        // ONLY circular motion - no fallback to general movement
        let hasCircle = hasCircularMotion(minRadius: 0.04)
        
        if hasCircle {
            let motionMag = getMotionMagnitude(frames: 15)
            let confidence = min(1.0, motionMag / 0.05 + 0.4)
            return MotionResult(sign: "PLEASE", confidence: confidence, isComplete: confidence > 0.70)
        }
        
        return nil
    }
    
    /// YES: Fist pumping up and down (nodding motion)
    private func detectYes(_ frame: HandFrame) -> MotionResult? {
        // YES requires closed fist - only thumb can be out (0 or 1 finger)
        guard frame.fingerStates.extendedCount <= 1 else { return nil }
        
        // Check for potential I LOVE YOU formation - suppress YES if detected
        let recentFrames = Array(frameHistory.suffix(10))
        if hasPotentialILoveYou(in: recentFrames) {
            return nil  // User might be forming I LOVE YOU
        }
        
        // Also check for pinky extension alone (early ILY formation)
        let framesWithPinky = recentFrames.filter { $0.fingerStates.pinkyExtended }.count
        if framesWithPinky >= 2 {
            return nil  // Pinky extending suggests I LOVE YOU formation
        }
        
        // Require fist shape to be stable for multiple frames
        let fistFrames = recentFrames.filter { $0.fingerStates.extendedCount <= 1 }.count
        guard fistFrames >= 7 else { return nil }  // Need at least 7 of last 10 frames as fist
        
        // Must have primarily VERTICAL motion, not horizontal
        let verticalMag = abs(getVerticalMotion(frames: 15))
        let horizontalMag = abs(getHorizontalMotion(frames: 15))
        
        // Vertical must STRONGLY dominate horizontal (at least 2.5x)
        guard verticalMag > horizontalMag * 2.5 else { return nil }
        guard verticalMag > 0.04 else { return nil }  // Increased threshold
        
        // Check for vertical oscillation - require 3 cycles for reliability
        if hasOscillation(axis: \.y, minCycles: 3) {
            let confidence = min(1.0, verticalMag / 0.06 + 0.3)
            return MotionResult(sign: "YES", confidence: confidence, isComplete: confidence > 0.75)
        }
        
        return nil
    }
    
    /// NO: Finger wagging side to side
    private func detectNo(_ frame: HandFrame) -> MotionResult? {
        // NO requires pointing finger (1-3 fingers) - NOT a fist, NOT fully open hand
        guard frame.fingerStates.extendedCount >= 1 && frame.fingerStates.extendedCount <= 3 else { return nil }
        
        // Check for potential I LOVE YOU formation - suppress NO if detected
        let recentFrames = Array(frameHistory.suffix(10))
        if hasPotentialILoveYou(in: recentFrames) {
            return nil  // User might be forming I LOVE YOU
        }
        
        // Must have primarily HORIZONTAL motion, not vertical
        let horizontalMag = abs(getHorizontalMotion(frames: 15))
        let verticalMag = abs(getVerticalMotion(frames: 15))
        
        // Horizontal must STRONGLY dominate vertical (at least 2.5x)
        guard horizontalMag > verticalMag * 2.5 else { return nil }
        guard horizontalMag > 0.04 else { return nil }  // Increased threshold
        
        // Check for horizontal oscillation - require 3 cycles for reliability
        if hasOscillation(axis: \.x, minCycles: 3) {
            let confidence = min(1.0, horizontalMag / 0.06 + 0.3)
            return MotionResult(sign: "NO", confidence: confidence, isComplete: confidence > 0.75)
        }
        
        return nil
    }
    
    /// GOOD: Flat hand from chin moving outward and down
    /// Note: Vision doesn't provide Z, so we detect as downward motion from chin area
    private func detectGood(_ frame: HandFrame) -> MotionResult? {
        // GOOD requires open hand (4+ fingers) with specific down+out motion from chin area
        guard frame.fingerStates.extendedCount >= 4 else {
            return nil
        }
        
        // Check for I LOVE YOU pattern - suppress GOOD if detected
        let recentFrames = Array(frameHistory.suffix(10))
        if hasPotentialILoveYou(in: recentFrames) {
            return nil
        }
        
        // Hand should START in upper portion of frame (chin area)
        // Check first frames in history for starting position
        guard frameHistory.count >= 8 else { return nil }
        let startFrame = frameHistory[frameHistory.count - 8]
        let startedHigh = startFrame.palmCenter.y < 0.45
        
        guard startedHigh else { return nil }
        
        // Check for downward motion (chin to chest/out)
        let downwardMotion = getVerticalMotion(frames: 10)  // Positive = down
        let horizontalMotion = abs(getHorizontalMotion(frames: 10))
        
        // GOOD: primarily downward motion from chin
        // Must have significant downward movement
        guard downwardMotion > 0.04 else { return nil }
        
        // Downward should dominate horizontal (not a wave)
        guard downwardMotion > horizontalMotion else { return nil }
        
        // Should NOT be oscillating (that would be YES)
        let notOscillatingY = !hasOscillation(axis: \.y, minCycles: 2)
        
        // Require stable open hand
        let openHandFrames = recentFrames.filter { $0.fingerStates.extendedCount >= 4 }.count
        guard openHandFrames >= 5 else { return nil }
        
        if notOscillatingY {
            let confidence = min(1.0, downwardMotion / 0.06 + 0.4)
            return MotionResult(sign: "GOOD", confidence: confidence, isComplete: confidence > 0.75)
        }
        
        return nil
    }
    
    /// BYE / GOODBYE: Open hand waving
    private func detectBye(_ frame: HandFrame) -> MotionResult? {
        // BYE requires open hand (4+ fingers)
        guard frame.fingerStates.extendedCount >= 4 else {
            return nil
        }
        
        // Check for I LOVE YOU pattern - suppress BYE if detected
        let recentFrames = Array(frameHistory.suffix(10))
        if hasPotentialILoveYou(in: recentFrames) {
            return nil  // User might be forming I LOVE YOU
        }
        
        // Require stable open hand for multiple frames
        let openHandFrames = recentFrames.filter { $0.fingerStates.extendedCount >= 4 }.count
        guard openHandFrames >= 6 else { return nil }  // Need 6 of last 10 frames as open hand
        
        // Must have horizontal oscillation (waving motion)
        let horizontalMag = abs(getHorizontalMotion(frames: 15))
        let verticalMag = abs(getVerticalMotion(frames: 15))
        
        // Horizontal must strongly dominate for wave motion
        guard horizontalMag > verticalMag * 1.5 else { return nil }
        guard horizontalMag > 0.04 else { return nil }  // Increased threshold
        
        // Require oscillation with at least 2 cycles for reliable detection
        let hasWave = hasOscillation(axis: \.x, minCycles: 2)
        
        // Hand should be in upper 50% of frame
        let isHighEnough = frame.palmCenter.y < 0.5
        
        if hasWave && isHighEnough {
            let confidence = min(1.0, horizontalMag / 0.06 + 0.3)
            return MotionResult(sign: "BYE", confidence: confidence, isComplete: confidence > 0.75)
        }
        
        return nil
    }
    
    /// I LOVE YOU: Thumb, index, and pinky extended (ILY hand shape)
    /// This is a static sign but included here for robust detection
    /// Works for both front camera (selfie) and back camera (viewer perspective)
    private func detectILoveYou(_ frame: HandFrame) -> MotionResult? {
        // ILY hand shape: thumb, index, and pinky extended; middle and ring curled
        // Allow 2-3 extended count to be more lenient (pinky detection can be tricky)
        let extCount = frame.fingerStates.extendedCount
        guard extCount >= 2 && extCount <= 4 else { return nil }
        
        let thumbOut = frame.fingerStates.thumbExtended
        let indexOut = frame.fingerStates.indexExtended
        let middleCurled = !frame.fingerStates.middleExtended
        let ringCurled = !frame.fingerStates.ringExtended
        let pinkyOut = frame.fingerStates.pinkyExtended
        
        // Primary check: thumb + index + pinky configuration
        let hasILYFingers = thumbOut && indexOut && middleCurled && ringCurled && pinkyOut
        
        // Alternative check for back camera: use geometric analysis
        // Even if pinky isn't detected as "extended", check if it's spread out from ring finger
        let pinkyTip = frame.landmarks[LM.pinkyTip]
        let ringTip = frame.landmarks[LM.ringTip]
        let indexTip = frame.landmarks[LM.indexTip]
        let middleTip = frame.landmarks[LM.middleTip]
        
        let pinkyRingDist = distance(pinkyTip, ringTip)
        let pinkyIndexDist = distance(pinkyTip, indexTip)
        let middleRingDist = distance(middleTip, ringTip)
        
        // Pinky is spread if it's far from ring (more than middle-ring distance)
        let pinkySpread = pinkyRingDist > middleRingDist * 1.2
        
        // Alternative ILY detection: thumb + index extended, middle/ring curled, pinky spread out
        let hasILYGeometry = thumbOut && indexOut && middleCurled && ringCurled && pinkySpread
        
        if hasILYFingers || hasILYGeometry {
            // Pinky should be spread from index
            guard pinkyIndexDist > 0.04 else { return nil }
            
            // Check stability over recent frames (relaxed to 2 frames)
            let recentFrames = Array(frameHistory.suffix(3))
            var matchingFrames = 0
            
            for f in recentFrames {
                let fPinkyTip = f.landmarks[LM.pinkyTip]
                let fRingTip = f.landmarks[LM.ringTip]
                let fMiddleTip = f.landmarks[LM.middleTip]
                let fPinkyRingDist = distance(fPinkyTip, fRingTip)
                let fMiddleRingDist = distance(fMiddleTip, fRingTip)
                let fPinkySpread = fPinkyRingDist > fMiddleRingDist * 1.2
                
                let fHasILYFingers = f.fingerStates.thumbExtended && 
                                      f.fingerStates.indexExtended && 
                                      !f.fingerStates.middleExtended && 
                                      !f.fingerStates.ringExtended && 
                                      f.fingerStates.pinkyExtended
                
                let fHasILYGeometry = f.fingerStates.thumbExtended && 
                                       f.fingerStates.indexExtended && 
                                       !f.fingerStates.middleExtended && 
                                       !f.fingerStates.ringExtended && 
                                       fPinkySpread
                
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
