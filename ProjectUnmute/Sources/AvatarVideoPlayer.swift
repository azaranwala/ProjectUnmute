import SwiftUI
import AVKit
import os.log

// MARK: - Avatar Video Player

/// Plays sign language avatar videos based on recognized speech
struct AvatarVideoPlayer: View {
    let videoName: String?
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    
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
                    
                    Text("Avatar Video")
                        .font(.headline)
                        .foregroundColor(.gray)
                    
                    if let name = videoName {
                        Text("Loading: \(name)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
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
        .onChange(of: videoName) { _, newName in
            loadVideo(named: newName)
        }
        .onAppear {
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
        
        for ext in videoExtensions {
            if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "AvatarAssets") {
                videoURL = url
                break
            }
            // Also try without subdirectory (flat bundle)
            if let url = Bundle.main.url(forResource: name, withExtension: ext) {
                videoURL = url
                break
            }
            // Try with "AvatarAssets/" prefix in resource name
            if let url = Bundle.main.url(forResource: "AvatarAssets/\(name)", withExtension: ext) {
                videoURL = url
                break
            }
        }
        
        if let url = videoURL {
            logger.info("Loading avatar video: \(url.lastPathComponent)")
            let newPlayer = AVPlayer(url: url)
            newPlayer.actionAtItemEnd = .none
            
            // Loop the video
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: newPlayer.currentItem,
                queue: .main
            ) { _ in
                newPlayer.seek(to: .zero)
                newPlayer.play()
            }
            
            player = newPlayer
            player?.play()
            isPlaying = true
        } else {
            logger.warning("Avatar video not found: \(name)")
            player = nil
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
        
        // Check if video exists
        if availableVideos.contains(normalized) {
            currentVideoName = normalized
            logger.info("Playing avatar video: \(normalized)")
        } else {
            // Try partial matching
            for video in availableVideos {
                if normalized.contains(video) || video.contains(normalized) {
                    currentVideoName = video
                    logger.info("Playing matched avatar video: \(video) for phrase: \(phrase)")
                    return
                }
            }
            
            logger.info("No avatar video found for: \(phrase)")
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
