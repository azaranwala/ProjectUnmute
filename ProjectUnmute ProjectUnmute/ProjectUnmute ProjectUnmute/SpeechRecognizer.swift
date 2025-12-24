import Foundation
import Speech
import AVFoundation
import os.log

// MARK: - Speech Recognition Manager

/// Handles real-time speech-to-text using SFSpeechRecognizer
@MainActor
final class SpeechRecognitionManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var transcribedText: String = ""
    @Published private(set) var isListening = false
    @Published private(set) var error: String?
    @Published private(set) var lastRecognizedWord: String?
    @Published private(set) var matchedAvatarVideo: String?
    
    // MARK: - Private Properties
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ProjectUnmute", category: "SpeechRecognizer")
    
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    /// Mapping of spoken words/phrases to avatar video filenames
    private var avatarVideoMap: [String: String] = [:]
    
    // MARK: - Initialization
    
    init() {
        loadAvatarAssets()
    }
    
    // MARK: - Avatar Assets
    
    /// Load avatar video mappings from AvatarAssets folder
    private func loadAvatarAssets() {
        // All available ASL videos - single words and phrases
        let availableVideos = [
            // Greetings
            "hello", "hi", "bye", "goodbye", "morning", "night",
            // Responses
            "yes", "no", "maybe", "ok", "please", "sorry", "thank you", "excuse",
            // Feelings
            "happy", "sad", "angry", "love", "fine", "tired", "hungry", "thirsty", "sick", "hurt", "pain",
            // Actions
            "help", "stop", "wait", "go", "come", "sit", "stand", "open", "close", "eat", "drink", "want", "need", "like", "know", "understand", "finish", "done", "work",
            // Questions
            "what", "where", "when", "who", "why", "how", "which",
            // People
            "family", "friend", "father", "mother", "brother", "sister", "doctor",
            // Places
            "home", "school", "bathroom",
            // Time
            "now", "later", "today", "tomorrow", "day", "week", "year", "again",
            // Numbers
            "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
            // Colors
            "red", "blue", "green", "yellow", "orange", "purple", "pink", "black", "white", "brown",
            // Descriptions
            "good", "bad", "big", "small", "hot", "cold", "cool", "more", "all", "name", "water", "food"
        ]
        
        for phrase in availableVideos {
            let filename = phrase.replacingOccurrences(of: " ", with: "_").lowercased()
            avatarVideoMap[phrase.lowercased()] = filename
        }
        
        // Also add common phrase variations
        avatarVideoMap["thanks"] = "thank_you"
        avatarVideoMap["thank"] = "thank_you"
        avatarVideoMap["i love you"] = "love"
        avatarVideoMap["good morning"] = "morning"
        avatarVideoMap["good night"] = "night"
        avatarVideoMap["i'm fine"] = "fine"
        avatarVideoMap["i am fine"] = "fine"
        
        logger.info("Loaded \(self.avatarVideoMap.count) avatar video mappings")
    }
    
    /// Get video filename for a recognized phrase
    func videoFilename(for text: String) -> String? {
        let lowercased = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Direct match
        if let filename = avatarVideoMap[lowercased] {
            return filename
        }
        
        // Partial match - check if any mapped phrase is contained in the text
        for (phrase, filename) in avatarVideoMap {
            if lowercased.contains(phrase) {
                return filename
            }
        }
        
        return nil
    }
    
    // MARK: - Permissions
    
    /// Request speech recognition and microphone permissions
    func requestPermissions() async -> Bool {
        // Request speech recognition permission
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        
        guard speechStatus == .authorized else {
            error = "Speech recognition not authorized"
            logger.error("Speech recognition authorization failed: \(String(describing: speechStatus))")
            return false
        }
        
        // Request microphone permission
        let micStatus = await AVAudioApplication.requestRecordPermission()
        
        guard micStatus else {
            error = "Microphone access not authorized"
            logger.error("Microphone authorization failed")
            return false
        }
        
        logger.info("Speech recognition and microphone permissions granted")
        return true
    }
    
    // MARK: - Speech Recognition
    
    /// Check if running in simulator (not Mac Catalyst)
    private var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
    
    /// Check if running on Mac (Catalyst or Designed for iPad)
    private var isMacCatalyst: Bool {
        #if targetEnvironment(macCatalyst)
        return true
        #else
        return ProcessInfo.processInfo.isiOSAppOnMac
        #endif
    }
    
    /// Check if running on Mac (any mode)
    private var isRunningOnMac: Bool {
        ProcessInfo.processInfo.isiOSAppOnMac
    }
    
    /// Start listening for speech
    func startListening() async {
        guard !isListening else { return }
        
        // Check if running in simulator or Mac - audio engine has compatibility issues
        if isSimulator || isRunningOnMac {
            let platform = isRunningOnMac ? "Mac" : "Simulator"
            logger.warning("Running on \(platform) - audio engine not compatible")
            error = "🎤 Live microphone not available on \(platform). Use Demo Mode to type words or tap buttons to test the full speech-to-video flow!"
            return
        }
        
        // Check permissions
        guard await requestPermissions() else { return }
        
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            error = "Speech recognizer not available"
            return
        }
        
        do {
            try await startRecognition()
            isListening = true
            error = nil
            logger.info("Started speech recognition")
        } catch {
            self.error = "Speech recognition failed: \(error.localizedDescription)"
            logger.error("Failed to start speech recognition: \(error.localizedDescription)")
        }
    }
    
    /// Stop listening for speech
    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
        
        logger.info("Stopped speech recognition")
    }
    
    private func startRecognition() async throws {
        // Cancel any existing task
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Configure audio session (iOS device only, skip on Mac - both Catalyst and Designed for iPad)
        let isRunningOnMac = ProcessInfo.processInfo.isiOSAppOnMac
        
        if !isRunningOnMac {
            #if !targetEnvironment(macCatalyst)
            let audioSession = AVAudioSession.sharedInstance()
            
            do {
                try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.allowBluetooth, .defaultToSpeaker])
                try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            } catch {
                logger.error("Audio session configuration failed: \(error.localizedDescription)")
                throw SpeechError.audioEngineError
            }
            #endif
        } else {
            logger.info("Running on Mac - skipping AVAudioSession configuration")
        }
        
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        guard let recognitionRequest = recognitionRequest else {
            throw SpeechError.requestCreationFailed
        }
        
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = false // Use server for better accuracy
        
        // Get input node
        let inputNode = audioEngine.inputNode
        let recordingFormat: AVAudioFormat
        
        // On Mac, we might need to use a different format
        if isRunningOnMac {
            // Try to get native format first
            let nativeFormat = inputNode.inputFormat(forBus: 0)
            if nativeFormat.sampleRate > 0 && nativeFormat.channelCount > 0 {
                recordingFormat = nativeFormat
                logger.info("Mac: Using native input format - SR: \(nativeFormat.sampleRate), CH: \(nativeFormat.channelCount)")
            } else {
                // Fallback to output format
                let outputFormat = inputNode.outputFormat(forBus: 0)
                if outputFormat.sampleRate > 0 && outputFormat.channelCount > 0 {
                    recordingFormat = outputFormat
                    logger.info("Mac: Using output format - SR: \(outputFormat.sampleRate), CH: \(outputFormat.channelCount)")
                } else {
                    // No valid format available
                    logger.error("Mac: No valid audio format available")
                    throw SpeechError.audioEngineError
                }
            }
        } else {
            recordingFormat = inputNode.outputFormat(forBus: 0)
        }
        
        // Check if format is valid (simulator may have 0 channels)
        guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
            logger.error("Invalid audio format: sampleRate=\(recordingFormat.sampleRate), channels=\(recordingFormat.channelCount)")
            throw SpeechError.audioEngineError
        }
        
        // Install tap on input - use nil format on Mac for automatic conversion
        let tapFormat: AVAudioFormat? = isRunningOnMac ? nil : recordingFormat
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        
        // Start audio engine
        audioEngine.prepare()
        try audioEngine.start()
        
        // Start recognition task
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor in
                self?.handleRecognitionResult(result: result, error: error)
            }
        }
    }
    
    private func handleRecognitionResult(result: SFSpeechRecognitionResult?, error: Error?) {
        if let error = error {
            // Check if it's just a cancellation
            let nsError = error as NSError
            if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1110 {
                // Recognition was cancelled, not an error
                return
            }
            
            self.error = error.localizedDescription
            logger.error("Recognition error: \(error.localizedDescription)")
            return
        }
        
        guard let result = result else { return }
        
        let text = result.bestTranscription.formattedString
        transcribedText = text
        
        // Get the last segment (most recent word/phrase)
        if let lastSegment = result.bestTranscription.segments.last {
            let lastWord = lastSegment.substring.lowercased()
            lastRecognizedWord = lastWord
            
            // Check for matching avatar video
            if let videoFile = videoFilename(for: text) {
                matchedAvatarVideo = videoFile
                logger.info("Matched avatar video: \(videoFile) for text: \(text)")
            }
        }
        
        // If recognition is final, log it
        if result.isFinal {
            logger.info("Final transcription: \(text)")
        }
    }
    
    /// Clear the current transcription
    func clearTranscription() {
        transcribedText = ""
        lastRecognizedWord = nil
        matchedAvatarVideo = nil
    }
    
    /// Simulate speech input (for testing without microphone)
    /// This processes text as if it was spoken, triggering the full recognition flow
    func simulateSpeech(_ text: String) {
        logger.info("Simulating speech input: '\(text)'")
        
        // Update transcription as if it was heard
        transcribedText = text
        
        // Extract individual words and process
        let words = text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
        
        // Process each word looking for matches
        for word in words {
            lastRecognizedWord = word
            
            // Check for video match
            if let videoFile = videoFilename(for: word) {
                matchedAvatarVideo = videoFile
                logger.info("Simulated speech matched video: \(videoFile)")
                return  // Found a match, stop processing
            }
        }
        
        // Also check the full phrase
        if let videoFile = videoFilename(for: text) {
            matchedAvatarVideo = videoFile
            logger.info("Simulated phrase matched video: \(videoFile)")
        }
    }
}

// MARK: - Speech Errors

enum SpeechError: LocalizedError {
    case requestCreationFailed
    case recognizerNotAvailable
    case audioEngineError
    
    var errorDescription: String? {
        switch self {
        case .requestCreationFailed:
            return "Failed to create speech recognition request"
        case .recognizerNotAvailable:
            return "Speech recognizer is not available"
        case .audioEngineError:
            return "Audio engine error"
        }
    }
}
