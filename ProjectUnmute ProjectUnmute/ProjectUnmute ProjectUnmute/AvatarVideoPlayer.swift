import SwiftUI
import AVKit
import os.log

// MARK: - Avatar Video Player

/// Plays sign language avatar videos based on recognized speech
struct AvatarVideoPlayer: View {
    let videoName: String?
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var playerObserver: NSKeyValueObservation?
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ProjectUnmute", category: "AvatarPlayer")
    
    var body: some View {
        ZStack {
            Color.black
            
            if let player = player {
                VideoPlayer(player: player)
                    .onAppear {
                        player.play()
                        isPlaying = true
                    }
                    .onDisappear {
                        player.pause()
                        isPlaying = false
                    }
            } else {
                // Placeholder when no video
                VStack(spacing: 16) {
                    Image(systemName: "person.crop.rectangle")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    
                    if let name = videoName, !name.isEmpty {
                        // Video was requested but not found
                        Text("Unable to find ASL sign")
                            .font(.headline)
                            .foregroundColor(.orange)
                        
                        Text("for: \"\(name)\"")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Avatar Video")
                            .font(.headline)
                            .foregroundColor(.gray)
                        
                        Text("Speak to see avatar")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Playing indicator
            if isPlaying {
                VStack {
                    HStack {
                        Spacer()
                        Label("Playing", systemImage: "play.fill")
                            .font(.caption)
                            .padding(6)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Capsule())
                            .foregroundColor(.white)
                            .padding(8)
                    }
                    Spacer()
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onChange(of: videoName) { oldName, newName in
            logger.info("onChange triggered: '\(oldName ?? "nil")' -> '\(newName ?? "nil")'")
            loadVideo(named: newName)
        }
        .onAppear {
            logger.info("onAppear triggered with videoName: '\(videoName ?? "nil")'")
            loadVideo(named: videoName)
        }
        .task(id: videoName) {
            // This ensures video loads when videoName changes, even if view is recreated
            logger.info("task(id:) triggered with videoName: '\(videoName ?? "nil")'")
            loadVideo(named: videoName)
        }
    }
    
    private func loadVideo(named name: String?) {
        guard let name = name else {
            player = nil
            isPlaying = false
            return
        }
        
        // Try to find video in AvatarAssets folder
        let videoExtensions = ["mp4", "mov", "m4v"]
        var videoURL: URL?
        
        // Method 1: Standard Bundle API with subdirectory
        for ext in videoExtensions {
            if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "AvatarAssets") {
                videoURL = url
                logger.info("Found video via subdirectory: \(url.path)")
                break
            }
        }
        
        // Method 2: Direct path construction (for folder references)
        if videoURL == nil, let resourcePath = Bundle.main.resourcePath {
            for ext in videoExtensions {
                let directPath = (resourcePath as NSString).appendingPathComponent("AvatarAssets/\(name).\(ext)")
                if FileManager.default.fileExists(atPath: directPath) {
                    videoURL = URL(fileURLWithPath: directPath)
                    logger.info("Found video via direct path: \(directPath)")
                    break
                }
            }
        }
        
        // Method 3: Bundle URL with path components
        if videoURL == nil {
            for ext in videoExtensions {
                if let bundleURL = Bundle.main.resourceURL {
                    let fileURL = bundleURL.appendingPathComponent("AvatarAssets").appendingPathComponent("\(name).\(ext)")
                    if FileManager.default.fileExists(atPath: fileURL.path) {
                        videoURL = fileURL
                        logger.info("Found video via bundle URL: \(fileURL.path)")
                        break
                    }
                }
            }
        }
        
        // Method 4: Flat bundle (no subdirectory)
        if videoURL == nil {
            for ext in videoExtensions {
                if let url = Bundle.main.url(forResource: name, withExtension: ext) {
                    videoURL = url
                    logger.info("Found video in flat bundle: \(url.path)")
                    break
                }
            }
        }
        
        // Debug: List what's in AvatarAssets folder
        if videoURL == nil {
            logger.warning("Video '\(name)' not found. Checking AvatarAssets contents...")
            if let resourcePath = Bundle.main.resourcePath {
                let avatarPath = (resourcePath as NSString).appendingPathComponent("AvatarAssets")
                if let contents = try? FileManager.default.contentsOfDirectory(atPath: avatarPath) {
                    logger.info("AvatarAssets contains \(contents.count) files")
                    let matching = contents.filter { $0.lowercased().contains(name.lowercased()) }
                    if !matching.isEmpty {
                        logger.info("Matching files: \(matching)")
                    }
                } else {
                    logger.warning("Could not read AvatarAssets directory at: \(avatarPath)")
                }
            }
        }
        
        if let url = videoURL {
            logger.info("Loading avatar video: \(url.lastPathComponent)")
            
            // Create player item first
            let playerItem = AVPlayerItem(url: url)
            let newPlayer = AVPlayer(playerItem: playerItem)
            newPlayer.actionAtItemEnd = .none
            
            // Wait for player item to be ready before playing
            playerObserver = playerItem.observe(\.status, options: [.new]) { [self] item, _ in
                DispatchQueue.main.async {
                    switch item.status {
                    case .readyToPlay:
                        logger.info("Player ready - starting playback for: \(url.lastPathComponent)")
                        newPlayer.seek(to: .zero)
                        newPlayer.play()
                        isPlaying = true
                    case .failed:
                        logger.error("Player failed to load: \(item.error?.localizedDescription ?? "unknown error")")
                        isPlaying = false
                    case .unknown:
                        logger.info("Player status unknown, waiting...")
                    @unknown default:
                        break
                    }
                }
            }
            
            // Loop the video
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: playerItem,
                queue: .main
            ) { _ in
                newPlayer.seek(to: .zero)
                newPlayer.play()
            }
            
            player = newPlayer
            
            // Also try to play immediately in case it's already ready
            if playerItem.status == .readyToPlay {
                newPlayer.play()
                isPlaying = true
            }
        } else {
            logger.warning("Avatar video not found: \(name)")
            player = nil
            playerObserver = nil
            isPlaying = false
        }
    }
}

// MARK: - Avatar Video Manager

/// Manages avatar video assets and playback
@MainActor
final class AvatarVideoManager: ObservableObject {
    
    @Published private(set) var currentVideoName: String?
    @Published private(set) var availableVideos: [String] = []
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ProjectUnmute", category: "AvatarManager")
    
    init() {
        scanAvatarAssets()
    }
    
    /// Scan the AvatarAssets folder for available videos
    private func scanAvatarAssets() {
        var videos: [String] = []
        
        // Get all video files from bundle
        let videoExtensions = ["mp4", "mov", "m4v"]
        
        if let resourcePath = Bundle.main.resourcePath {
            let avatarPath = (resourcePath as NSString).appendingPathComponent("AvatarAssets")
            let fileManager = FileManager.default
            
            if let files = try? fileManager.contentsOfDirectory(atPath: avatarPath) {
                for file in files {
                    let ext = (file as NSString).pathExtension.lowercased()
                    if videoExtensions.contains(ext) {
                        let name = (file as NSString).deletingPathExtension
                        videos.append(name)
                    }
                }
            }
        }
        
        // Also check root bundle
        for ext in videoExtensions {
            if let urls = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) {
                for url in urls {
                    let name = url.deletingPathExtension().lastPathComponent
                    if !videos.contains(name) {
                        videos.append(name)
                    }
                }
            }
        }
        
        availableVideos = videos.sorted()
        logger.info("Found \(videos.count) avatar videos: \(videos)")
    }
    
    /// Play avatar video for the given phrase
    func playVideo(for phrase: String) {
        let normalized = phrase.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "_")
        
        logger.info("Attempting to play video for: '\(phrase)' (normalized: '\(normalized)')")
        logger.info("Available videos count: \(self.availableVideos.count)")
        
        // Debug: Check if 'again' is in the list
        let containsAgain = self.availableVideos.contains("again")
        let containsNormalized = self.availableVideos.contains(normalized)
        let first10 = Array(self.availableVideos.prefix(10))
        logger.info("DEBUG: availableVideos.contains('again') = \(containsAgain)")
        logger.info("DEBUG: availableVideos.contains('\(normalized)') = \(containsNormalized)")
        if self.availableVideos.count > 0 {
            logger.info("DEBUG: First 10 videos: \(first10)")
        }
        
        // EXACT match only - no partial matching to avoid wrong videos
        // (e.g., "grandfather" should NOT match "father")
        
        // Check if video exists in our list (exact match)
        if availableVideos.contains(normalized) {
            currentVideoName = normalized
            logger.info("Playing avatar video: \(normalized)")
        } else if availableVideos.contains(normalized.replacingOccurrences(of: "_", with: " ")) {
            // Try with spaces instead of underscores
            let withSpaces = normalized.replacingOccurrences(of: "_", with: " ")
            currentVideoName = withSpaces
            logger.info("Playing avatar video (with spaces): \(withSpaces)")
        } else if availableVideos.contains(normalized.replacingOccurrences(of: " ", with: "_")) {
            // Try with underscores instead of spaces
            let withUnderscores = normalized.replacingOccurrences(of: " ", with: "_")
            currentVideoName = withUnderscores
            logger.info("Playing avatar video (with underscores): \(withUnderscores)")
        } else if availableVideos.isEmpty {
            // If no videos were scanned, try playing anyway (scan might have failed)
            currentVideoName = normalized
            logger.info("No videos scanned, trying to play: \(normalized)")
        } else {
            // NO partial matching - set to nil to show "Unable to find ASL sign"
            currentVideoName = nil
            logger.warning("No avatar video found for: '\(phrase)' (normalized: '\(normalized)')")
        }
    }
    
    /// Stop current video
    func stopVideo() {
        currentVideoName = nil
    }
}

// MARK: - Transcription Display View

/// Displays real-time speech transcription
struct TranscriptionView: View {
    let text: String
    let lastWord: String?
    let isListening: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: isListening ? "mic.fill" : "mic.slash")
                    .foregroundColor(isListening ? .green : .gray)
                    .symbolEffect(.pulse, isActive: isListening)
                
                Text(isListening ? "Listening..." : "Microphone Off")
                    .font(.caption)
                    .foregroundColor(isListening ? .green : .gray)
                
                Spacer()
                
                if let word = lastWord {
                    Text("Last: \"\(word)\"")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Transcription text
            if text.isEmpty {
                Text("Speak to see transcription...")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                Text(text)
                    .font(.title3)
                    .foregroundColor(.white)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Preview

#Preview {
    VStack {
        AvatarVideoPlayer(videoName: nil)
            .frame(height: 300)
        
        TranscriptionView(
            text: "Hello, how are you?",
            lastWord: "you",
            isListening: true
        )
    }
    .padding()
    .background(Color.black)
}
