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
        // Map common phrases to video files
        // Users should add videos named after the phrase (e.g., "hello.mp4", "thank_you.mp4")
        let commonPhrases = [
            "hello", "hi", "hey",
            "goodbye", "bye", "see you",
            "thank you", "thanks",
            "please", "sorry",
            "yes", "no", "maybe",
            "help", "stop", "wait",
            "i love you", "love",
            "good morning", "good night",
            "how are you", "i'm fine",
            "water", "food", "hungry", "thirsty",
            "bathroom", "pain", "tired",
            "happy", "sad", "angry"
        ]
        
        for phrase in commonPhrases {
            let filename = phrase.replacingOccurrences(of: " ", with: "_").lowercased()
            avatarVideoMap[phrase.lowercased()] = filename
        }
        
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
    
    /// Start listening for speech
    func startListening() async {
        guard !isListening else { return }
        
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
            self.error = error.localizedDescription
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
        
        // Configure audio session for Bluetooth input (Meta Glasses mic)
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.allowBluetooth, .defaultToSpeaker])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        guard let recognitionRequest = recognitionRequest else {
            throw SpeechError.requestCreationFailed
        }
        
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = false // Use server for better accuracy
        
        // Get input node
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // Install tap on input
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
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
