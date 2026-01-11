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
    @Published private(set) var unmatchedWord: String?  // Word spoken but no video found
    
    // MARK: - Private Properties
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ProjectUnmute", category: "SpeechRecognizer")
    
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    /// Mapping of spoken words/phrases to avatar video filenames
    private var avatarVideoMap: [String: String] = [:]
    
    /// Current language for speech recognition
    private var currentLanguage: LanguagePreference = .english
    
    /// Track if we've already logged error 1101 to prevent spam
    private var hasLogged1101Error = false
    
    /// Retry count for speech recognition
    private var retryCount = 0
    private let maxRetries = 5
    
    /// Track if this is the first start (needs longer delay)
    private var isFirstStart = true
    
    // MARK: - Initialization
    
    init() {
        loadAvatarAssets()
        updateRecognizerLanguage()
    }
    
    /// Update the speech recognizer to use the currently selected language
    func updateRecognizerLanguage() {
        let language = LanguageSettingsManager.shared.selectedLanguage
        currentLanguage = language
        speechRecognizer = SFSpeechRecognizer(locale: language.speechRecognitionLocale)
        logger.info("Updated speech recognizer to language: \(language.displayName)")
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
    /// Returns the exact matching video filename, or nil if not found
    func videoFilename(for text: String) -> String? {
        let lowercased = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // First, translate to English if using another language
        let language = LanguageSettingsManager.shared.selectedLanguage
        let englishWord = language.toEnglish(from: lowercased)
        
        // Direct match with English word (EXACT match only)
        if let filename = avatarVideoMap[englishWord] {
            logger.info("Found exact match for '\(englishWord)' -> \(filename)")
            return filename
        }
        
        // Also try the original word in case it's already English (EXACT match only)
        if let filename = avatarVideoMap[lowercased] {
            logger.info("Found exact match for '\(lowercased)' -> \(filename)")
            return filename
        }
        
        // Try with underscores replaced by spaces and vice versa
        let withSpaces = lowercased.replacingOccurrences(of: "_", with: " ")
        let withUnderscores = lowercased.replacingOccurrences(of: " ", with: "_")
        
        if let filename = avatarVideoMap[withSpaces] {
            logger.info("Found match with spaces for '\(withSpaces)' -> \(filename)")
            return filename
        }
        
        if let filename = avatarVideoMap[withUnderscores] {
            logger.info("Found match with underscores for '\(withUnderscores)' -> \(filename)")
            return filename
        }
        
        // NO partial matching - this caused wrong videos to play
        // (e.g., "grandfather" matching "father", "yesterday" matching "yes")
        
        logger.warning("No video found for: '\(lowercased)' (english: '\(englishWord)')")
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
        
        // Reset error tracking
        hasLogged1101Error = false
        
        // On first start, add a longer delay to let the system initialize
        if isFirstStart {
            isFirstStart = false
            retryCount = 0  // Reset retry count on first start
            logger.info("First start - waiting for system to initialize...")
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 second delay on first start
        }
        
        // Check if running in simulator or Mac - audio engine has compatibility issues
        if isSimulator || isRunningOnMac {
            let platform = isRunningOnMac ? "Mac" : "Simulator"
            logger.warning("Running on \(platform) - audio engine not compatible")
            error = "🎤 Live microphone not available on \(platform). Use Demo Mode to type words or tap buttons to test the full speech-to-video flow!"
            return
        }
        
        // Check permissions
        guard await requestPermissions() else { return }
        
        guard let speechRecognizer = speechRecognizer else {
            let language = LanguageSettingsManager.shared.selectedLanguage
            error = "Speech recognizer not available for \(language.displayName). Please check your device settings."
            logger.error("Speech recognizer is nil for locale: \(language.speechRecognitionLocale.identifier)")
            return
        }
        
        guard speechRecognizer.isAvailable else {
            let language = LanguageSettingsManager.shared.selectedLanguage
            error = "Speech recognition for \(language.displayName) is not available. Please download the language pack in Settings → General → Keyboard → Dictation."
            logger.error("Speech recognizer not available for locale: \(language.speechRecognitionLocale.identifier)")
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
        // Stop audio engine first
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        
        // Remove tap safely
        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        
        // End recognition request
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
        
        // Deactivate audio session on iOS
        #if !targetEnvironment(macCatalyst)
        if !ProcessInfo.processInfo.isiOSAppOnMac {
            do {
                try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            } catch {
                logger.warning("Failed to deactivate audio session: \(error.localizedDescription)")
            }
        }
        #endif
        
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
                // First deactivate to reset state
                try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
                
                // Small delay to let audio system settle
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                
                // Configure for speech recognition - use .default mode instead of .measurement
                // .measurement mode can cause issues on some devices
                try audioSession.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth, .defaultToSpeaker, .mixWithOthers])
                try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
                
                // Another small delay after activation
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                
                logger.info("Audio session configured successfully")
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
        recognitionRequest.addsPunctuation = false  // Reduce processing overhead
        recognitionRequest.taskHint = .dictation    // Optimize for dictation
        
        // Use on-device recognition (user preference)
        if speechRecognizer?.supportsOnDeviceRecognition == true {
            recognitionRequest.requiresOnDeviceRecognition = true
            logger.info("Using on-device speech recognition")
        } else {
            // Fall back to server only if on-device not available at all
            recognitionRequest.requiresOnDeviceRecognition = false
            logger.warning("On-device recognition not available, falling back to server")
        }
        
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
        
        // Wait for audio engine to stabilize before starting recognition
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
        
        // Start recognition task
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor in
                self?.handleRecognitionResult(result: result, error: error)
            }
        }
    }
    
    private func handleRecognitionResult(result: SFSpeechRecognitionResult?, error: Error?) {
        if let error = error {
            let nsError = error as NSError
            
            // Handle known AFAssistant errors silently to prevent spam
            if nsError.domain == "kAFAssistantErrorDomain" {
                switch nsError.code {
                case 1110:
                    // Recognition was cancelled, not an error
                    return
                case 1101:
                    // Speech recognition service unavailable or failed to start
                    // This can happen when the service is busy or unavailable
                    // Try to restart recognition if we haven't exceeded retries
                    let currentRetry = self.retryCount
                    let maxRetryCount = self.maxRetries
                    
                    if currentRetry < maxRetryCount {
                        self.retryCount += 1
                        let delaySeconds = Double(self.retryCount) * 0.5 // Increasing delay: 0.5s, 1s, 1.5s, etc.
                        if !self.hasLogged1101Error {
                            self.hasLogged1101Error = true
                            logger.warning("Speech recognition error (1101). Retry \(self.retryCount)/\(maxRetryCount) in \(delaySeconds)s...")
                        }
                        
                        Task { @MainActor in
                            self.stopListening()
                            // Wait with increasing delay before retrying
                            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
                            self.hasLogged1101Error = false // Reset so we can log next retry
                            await self.startListening()
                        }
                    } else {
                        if !self.hasLogged1101Error {
                            self.hasLogged1101Error = true
                            logger.error("Speech recognition failed after \(maxRetryCount) retries")
                            self.stopListening()
                            self.error = "Speech recognition unavailable. Please check your internet connection and try again."
                        }
                    }
                    return
                case 1107:
                    // No speech detected - this is normal, not an error
                    return
                default:
                    break
                }
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
            
            // Check for matching avatar video - prioritize the LAST word first
            if let videoFile = videoFilename(for: lastWord) {
                // Only update if it's a NEW match to avoid replaying the same video
                if videoFile != matchedAvatarVideo {
                    unmatchedWord = nil  // Clear unmatched state
                    matchedAvatarVideo = videoFile
                    logger.info("Matched avatar video: \(videoFile) for word: \(lastWord)")
                }
            } else {
                // No video found for this word - trigger "No ASL sign found" message
                // Only update if it's a new unmatched word
                if lastWord != unmatchedWord {
                    matchedAvatarVideo = nil  // Clear any previous match
                    unmatchedWord = lastWord
                    logger.info("No video for word: \(lastWord) - showing 'No ASL sign found'")
                }
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
        unmatchedWord = nil
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
            unmatchedWord = nil
            matchedAvatarVideo = videoFile
            logger.info("Simulated phrase matched video: \(videoFile)")
        } else {
            // No match found - show "No ASL sign found"
            matchedAvatarVideo = nil
            unmatchedWord = text
            logger.info("No video for simulated speech: \(text)")
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
