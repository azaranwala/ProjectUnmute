import Foundation

/// ASL Sign Classifier using neural network or template matching with hand landmarks
/// Works with MediaPipe hand landmark output (21 landmarks × 3 coordinates = 63 features)
final class ASLModelClassifier {
    
    // MARK: - Properties
    
    private var classes: [String] = []
    private var scalerMean: [Double] = []
    private var scalerScale: [Double] = []
    private var centroids: [String: [Double]] = [:]
    private var isLoaded = false
    
    // MLP Neural Network properties
    private var modelType: String = "centroid"
    private var weights: [[[Double]]] = []
    private var biases: [[Double]] = []
    private var hiddenLayers: [Int] = []
    
    // MARK: - Temporal Smoothing (addresses jitter/instability)
    
    /// EMA decay factor (0.7 = 70% weight to smoothed, 30% to new)
    private let emaDecay: Double = 0.7
    
    /// Smoothed probability distribution (EMA)
    private var smoothedProbabilities: [Double] = []
    
    /// Sliding window of recent predictions for N-of-M agreement
    private var predictionHistory: [String] = []
    private let historySize: Int = 5  // Keep last 5 predictions
    private let agreementThreshold: Int = 3  // Need 3 of 5 to agree
    
    /// Last raw prediction (before smoothing/agreement)
    private var lastRawPrediction: String = ""
    
    static let shared = ASLModelClassifier()
    
    // MARK: - Initialization
    
    private init() {
        loadModel()
    }
    
    // MARK: - Model Loading
    
    private func loadModel() {
        guard let url = Bundle.main.url(forResource: "ASLModelData", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("ASLModelClassifier: Failed to load ASLModelData.json")
            return
        }
        
        if let classesArray = json["classes"] as? [String] {
            classes = classesArray
        }
        
        if let mean = json["scaler_mean"] as? [Double] {
            scalerMean = mean
        }
        
        if let scale = json["scaler_scale"] as? [Double] {
            scalerScale = scale
        }
        
        // Check model type
        if let type = json["model_type"] as? String {
            modelType = type
        }
        
        if modelType == "mlp" {
            // Load MLP weights and biases
            if let weightsArray = json["weights"] as? [[[Double]]] {
                weights = weightsArray
            }
            if let biasesArray = json["biases"] as? [[Double]] {
                biases = biasesArray
            }
            if let layers = json["hidden_layers"] as? [Int] {
                hiddenLayers = layers
            }
            isLoaded = !classes.isEmpty && !weights.isEmpty && !biases.isEmpty
            if isLoaded {
                print("ASLModelClassifier: Loaded MLP model with \(classes.count) classes, \(hiddenLayers) hidden layers")
            }
        } else {
            // Load centroid-based model
            if let centroidsDict = json["centroids"] as? [String: [Double]] {
                centroids = centroidsDict
            }
            isLoaded = !classes.isEmpty && !scalerMean.isEmpty && !centroids.isEmpty
            if isLoaded {
                print("ASLModelClassifier: Loaded centroid model with \(classes.count) sign classes")
            }
        }
    }
    
    // MARK: - Classification
    
    // Minimum confidence threshold (15% - softmax over 79 classes with tight temperature)
    private let confidenceThreshold: Float = 0.15
    
    /// Classify hand landmarks to ASL sign with temporal smoothing
    /// - Parameter landmarks: Array of 63 values (21 landmarks × 3 coordinates: x, y, z)
    /// - Returns: Tuple of (predicted class, confidence 0-1). Returns "Unable to recognize the sign" if confidence < 80%
    func classify(landmarks: [Float]) -> (sign: String, confidence: Float)? {
        guard isLoaded, landmarks.count == 63 else {
            print("ASLModelClassifier: Invalid input - loaded=\(isLoaded), count=\(landmarks.count)")
            return nil
        }
        
        // Preprocess landmarks with rotation invariance
        let processed = preprocessLandmarks(landmarks)
        
        // Get raw probabilities
        var rawProbabilities: [Double] = []
        var rawPrediction: String = ""
        var rawConfidence: Float = 0
        
        if modelType == "mlp" {
            rawProbabilities = getMLPProbabilities(processed)
            if let (pred, conf) = getBestFromProbabilities(rawProbabilities) {
                rawPrediction = pred
                rawConfidence = conf
            }
        } else {
            // For centroid, build a full probability distribution from distances
            rawProbabilities = getCentroidProbabilities(processed)
            if let (pred, conf) = getBestFromProbabilities(rawProbabilities) {
                rawPrediction = pred
                rawConfidence = conf
            }
        }
        
        // Apply EMA smoothing (reduces frame-to-frame jitter)
        let smoothedResult = applyTemporalSmoothing(rawProbabilities, rawPrediction: rawPrediction)
        
        // Apply N-of-M agreement (requires consistent predictions)
        let agreedResult = applyPredictionAgreement(smoothedResult.sign)
        
        // Use agreed prediction with smoothed confidence
        let finalSign = agreedResult ?? smoothedResult.sign
        let finalConfidence = smoothedResult.confidence
        
        // Check confidence threshold
        if finalConfidence < confidenceThreshold {
            print("ASLModelClassifier: Low confidence (\(finalConfidence)) - returning unrecognized")
            return ("Unable to recognize the sign", finalConfidence)
        }
        
        // If no agreement yet, show stabilizing message
        if agreedResult == nil && !predictionHistory.isEmpty {
            return ("\(finalSign) (stabilizing...)", finalConfidence)
        }
        
        return (finalSign, finalConfidence)
    }
    
    /// Reset temporal state (call when hand leaves frame or switching cameras)
    func resetTemporalState() {
        smoothedProbabilities = []
        predictionHistory = []
        lastRawPrediction = ""
        print("ASLModelClassifier: Temporal state reset")
    }
    
    // MARK: - Temporal Smoothing Helpers
    
    /// Apply exponential moving average to probabilities
    private func applyTemporalSmoothing(_ rawProbs: [Double], rawPrediction: String) -> (sign: String, confidence: Float) {
        guard !rawProbs.isEmpty else {
            return (rawPrediction, 0)
        }
        
        // Initialize smoothed probs if needed
        if smoothedProbabilities.isEmpty || smoothedProbabilities.count != rawProbs.count {
            smoothedProbabilities = rawProbs
        } else {
            // EMA: smoothed = decay * smoothed + (1-decay) * raw
            for i in 0..<rawProbs.count {
                smoothedProbabilities[i] = emaDecay * smoothedProbabilities[i] + (1 - emaDecay) * rawProbs[i]
            }
        }
        
        // Get best from smoothed
        if let (sign, conf) = getBestFromProbabilities(smoothedProbabilities) {
            return (sign, conf)
        }
        return (rawPrediction, 0)
    }
    
    /// Apply N-of-M frame agreement
    private func applyPredictionAgreement(_ currentPrediction: String) -> String? {
        // Add to history
        predictionHistory.append(currentPrediction)
        if predictionHistory.count > historySize {
            predictionHistory.removeFirst()
        }
        
        // Count occurrences of current prediction in history
        let count = predictionHistory.filter { $0 == currentPrediction }.count
        
        // Return prediction only if it appears enough times
        if count >= agreementThreshold {
            return currentPrediction
        }
        
        // Check if any prediction has enough agreement
        let counts = Dictionary(grouping: predictionHistory, by: { $0 }).mapValues { $0.count }
        if let (agreed, cnt) = counts.max(by: { $0.value < $1.value }), cnt >= agreementThreshold {
            return agreed
        }
        
        return nil
    }
    
    /// Get best prediction from probability array
    private func getBestFromProbabilities(_ probs: [Double]) -> (sign: String, confidence: Float)? {
        guard !probs.isEmpty, probs.count == classes.count else { return nil }
        
        var bestIdx = 0
        var bestProb = probs[0]
        for i in 1..<probs.count {
            if probs[i] > bestProb {
                bestProb = probs[i]
                bestIdx = i
            }
        }
        
        return (classes[bestIdx], Float(bestProb))
    }
    
    /// Get raw MLP probabilities (without temporal smoothing)
    private func getMLPProbabilities(_ input: [Double]) -> [Double] {
        guard !weights.isEmpty, !biases.isEmpty else { return [] }
        
        var activation = input
        for i in 0..<weights.count {
            activation = matmul(activation, weights[i])
            activation = add(activation, biases[i])
            if i < weights.count - 1 {
                activation = relu(activation)
            }
        }
        
        return softmax(activation)
    }
    
    // MARK: - Preprocessing
    
    private func preprocessLandmarks(_ landmarks: [Float]) -> [Double] {
        // Step 1: Make landmarks WRIST-RELATIVE
        let wristX = Double(landmarks[0])
        let wristY = Double(landmarks[1])
        let wristZ = Double(landmarks[2])
        
        var relativeLandmarks: [Double] = []
        for i in stride(from: 0, to: landmarks.count, by: 3) {
            relativeLandmarks.append(Double(landmarks[i]) - wristX)
            relativeLandmarks.append(Double(landmarks[i+1]) - wristY)
            relativeLandmarks.append(Double(landmarks[i+2]) - wristZ)
        }
        
        // Step 2: Rotation normalization (align hand to canonical orientation)
        // Use wrist→middle MCP as primary axis for rotation invariance
        let rotatedLandmarks = applyRotationNormalization(relativeLandmarks)
        
        // Step 3: Scale by hand size (makes invariant to distance from camera)
        var maxDist = 0.0
        for i in stride(from: 0, to: rotatedLandmarks.count, by: 3) {
            let x = rotatedLandmarks[i]
            let y = rotatedLandmarks[i+1]
            let z = rotatedLandmarks[i+2]
            let dist = sqrt(x*x + y*y + z*z)
            if dist > maxDist {
                maxDist = dist
            }
        }
        if maxDist < 0.001 { maxDist = 1.0 }
        
        let scaledLandmarks = rotatedLandmarks.map { $0 / maxDist }
        
        // Step 4: Apply StandardScaler normalization
        return normalize(scaledLandmarks)
    }
    
    /// Apply rotation normalization to make features invariant to hand rotation
    /// Aligns hand so that wrist→middle_finger_mcp points in consistent direction
    private func applyRotationNormalization(_ landmarks: [Double]) -> [Double] {
        guard landmarks.count == 63 else { return landmarks }
        
        // Middle finger MCP is at index 9 (landmark indices: 0=wrist, 9=middle_mcp)
        // Each landmark has 3 values (x, y, z)
        let middleMcpIdx = 9 * 3  // = 27
        
        // Get middle MCP position (relative to wrist which is at origin)
        let mcpX = landmarks[middleMcpIdx]
        let mcpY = landmarks[middleMcpIdx + 1]
        
        // Calculate angle to rotate so middle MCP points "up" (negative Y in image coords)
        let angle = atan2(mcpX, -mcpY)  // Angle from vertical
        
        // Only apply rotation if angle is significant (>5 degrees)
        guard abs(angle) > 0.087 else { return landmarks }  // 5 degrees in radians
        
        let cosA = cos(-angle)  // Rotate back to vertical
        let sinA = sin(-angle)
        
        var rotated = [Double](repeating: 0, count: 63)
        for i in stride(from: 0, to: 63, by: 3) {
            let x = landmarks[i]
            let y = landmarks[i + 1]
            let z = landmarks[i + 2]
            
            // 2D rotation around Z axis (in XY plane)
            rotated[i] = x * cosA - y * sinA
            rotated[i + 1] = x * sinA + y * cosA
            rotated[i + 2] = z  // Z unchanged
        }
        
        return rotated
    }
    
    // MARK: - MLP Classification
    
    private func classifyMLP(_ input: [Double]) -> (sign: String, confidence: Float)? {
        guard !weights.isEmpty, !biases.isEmpty else { return nil }
        
        var activation = input
        
        // Forward pass through hidden layers
        for i in 0..<weights.count {
            activation = matmul(activation, weights[i])
            activation = add(activation, biases[i])
            
            // ReLU for hidden layers, no activation for output
            if i < weights.count - 1 {
                activation = relu(activation)
            }
        }
        
        // Softmax for output probabilities
        let probabilities = softmax(activation)
        
        // Find best class
        var bestIdx = 0
        var bestProb = probabilities[0]
        for i in 1..<probabilities.count {
            if probabilities[i] > bestProb {
                bestProb = probabilities[i]
                bestIdx = i
            }
        }
        
        let bestClass = classes[bestIdx]
        let confidence = Float(bestProb)
        
        // Debug: Print top 3
        let indexed = probabilities.enumerated().sorted { $0.element > $1.element }
        let top3 = indexed.prefix(3).map { "\(classes[$0.offset]):\(String(format: "%.2f", $0.element))" }
        print("ASLModelClassifier [MLP]: Top 3 - \(top3.joined(separator: ", "))")
        
        return (bestClass, confidence)
    }
    
    // MARK: - Centroid Classification
    
    /// Get probability distribution from centroid distances (for temporal smoothing compatibility)
    private func getCentroidProbabilities(_ normalized: [Double]) -> [Double] {
        guard !classes.isEmpty else { return [] }
        
        // Calculate distances to all centroids
        var distances: [Double] = []
        for className in classes {
            if let centroid = centroids[className] {
                let distance = euclideanDistance(normalized, centroid)
                distances.append(distance)
            } else {
                distances.append(Double.infinity)
            }
        }
        
        // Debug: print top 3
        let indexed = distances.enumerated().sorted { $0.element < $1.element }
        let top3 = indexed.prefix(3).map { "\(classes[$0.offset]):\(String(format: "%.2f", $0.element))" }
        print("ASLModelClassifier [Centroid]: Top 3 - \(top3.joined(separator: ", "))")
        
        // Convert distances to probabilities using softmax over negative distances
        // Lower distance = higher probability
        // Use very low temperature for peaked distribution with many classes
        let temperature = 0.1  // Very low = very peaked distribution
        let negDistances = distances.map { -$0 / temperature }
        
        // Softmax
        let maxNegDist = negDistances.max() ?? 0
        let expVals = negDistances.map { exp($0 - maxNegDist) }
        let sumExp = expVals.reduce(0, +)
        
        return expVals.map { $0 / sumExp }
    }
    
    private func classifyCentroid(_ normalized: [Double]) -> (sign: String, confidence: Float)? {
        var bestClass = ""
        var bestDistance = Double.infinity
        var distances: [(String, Double)] = []
        
        for (className, centroid) in centroids {
            let distance = euclideanDistance(normalized, centroid)
            distances.append((className, distance))
            if distance < bestDistance {
                bestDistance = distance
                bestClass = className
            }
        }
        
        let sortedDistances = distances.sorted { $0.1 < $1.1 }
        print("ASLModelClassifier [Centroid]: Top 3 - \(sortedDistances.prefix(3).map { "\($0.0):\(String(format: "%.2f", $0.1))" }.joined(separator: ", "))")
        
        let confidence = Float(exp(-bestDistance / 15.0))
        return (bestClass, confidence)
    }
    
    // MARK: - MLP Helper Functions
    
    private func matmul(_ input: [Double], _ weights: [[Double]]) -> [Double] {
        let outputSize = weights[0].count
        var result = [Double](repeating: 0.0, count: outputSize)
        
        for j in 0..<outputSize {
            for i in 0..<input.count {
                result[j] += input[i] * weights[i][j]
            }
        }
        return result
    }
    
    private func add(_ a: [Double], _ b: [Double]) -> [Double] {
        return zip(a, b).map { $0 + $1 }
    }
    
    private func relu(_ x: [Double]) -> [Double] {
        return x.map { max(0, $0) }
    }
    
    private func softmax(_ x: [Double]) -> [Double] {
        let maxVal = x.max() ?? 0
        let expVals = x.map { exp($0 - maxVal) }
        let sumExp = expVals.reduce(0, +)
        return expVals.map { $0 / sumExp }
    }
    
    /// Classify and return top N predictions
    func classifyTopN(landmarks: [Float], n: Int = 3) -> [(sign: String, confidence: Float)] {
        guard isLoaded, landmarks.count == 63 else {
            return []
        }
        
        let processed = preprocessLandmarks(landmarks)
        
        if modelType == "mlp" {
            return classifyTopNMLP(processed, n: n)
        } else {
            return classifyTopNCentroid(processed, n: n)
        }
    }
    
    private func classifyTopNMLP(_ input: [Double], n: Int) -> [(sign: String, confidence: Float)] {
        guard !weights.isEmpty, !biases.isEmpty else { return [] }
        
        var activation = input
        for i in 0..<weights.count {
            activation = matmul(activation, weights[i])
            activation = add(activation, biases[i])
            if i < weights.count - 1 {
                activation = relu(activation)
            }
        }
        
        let probabilities = softmax(activation)
        let indexed = probabilities.enumerated().sorted { $0.element > $1.element }
        
        return indexed.prefix(n).map { (classes[$0.offset], Float($0.element)) }
    }
    
    private func classifyTopNCentroid(_ normalized: [Double], n: Int) -> [(sign: String, confidence: Float)] {
        var distances: [(String, Double)] = []
        for (className, centroid) in centroids {
            let distance = euclideanDistance(normalized, centroid)
            distances.append((className, distance))
        }
        
        distances.sort { $0.1 < $1.1 }
        
        return distances.prefix(n).map { (className, dist) in
            (className, Float(exp(-dist / 15.0)))
        }
    }
    
    // MARK: - Private Methods
    
    private func normalize(_ landmarks: [Double]) -> [Double] {
        guard landmarks.count == scalerMean.count else {
            return landmarks
        }
        
        return zip(zip(landmarks, scalerMean), scalerScale).map { (pair, scale) in
            let (value, mean) = pair
            return scale != 0 ? (value - mean) / scale : 0
        }
    }
    
    private func euclideanDistance(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count else { return Double.infinity }
        
        var sum = 0.0
        for i in 0..<a.count {
            let diff = a[i] - b[i]
            sum += diff * diff
        }
        return sqrt(sum)
    }
    
    // MARK: - Public Properties
    
    var availableClasses: [String] {
        return classes
    }
    
    var isModelLoaded: Bool {
        return isLoaded
    }
}
