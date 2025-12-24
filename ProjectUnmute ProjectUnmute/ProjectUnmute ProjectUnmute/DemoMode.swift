import SwiftUI
import AVKit

// MARK: - Demo Mode Controller
// Allows testing all app features without a real iPhone

@MainActor
class DemoModeController: ObservableObject {
    static let shared = DemoModeController()
    
    @Published var isDemoMode = true
    @Published var simulatedWord: String = ""
    @Published var showDemoControls = true
    
    // Available demo words that have matching videos
    let demoWords = [
        "hello", "bye", "thank", "please", "sorry",
        "yes", "no", "help", "stop", "wait",
        "happy", "sad", "angry", "hungry", "thirsty",
        "water", "food", "bathroom", "tired", "pain",
        "good", "bad", "love", "family", "friend"
    ]
    
    // Simulated gestures for demo
    let demoGestures = [
        "Open_Palm", "Closed_Fist", "Pointing_Up", 
        "Thumb_Up", "Victory", "ILoveYou"
    ]
    
    private init() {}
    
    func simulateWord(_ word: String) {
        simulatedWord = word
    }
    
    func clearSimulation() {
        simulatedWord = ""
    }
}

// MARK: - Demo Control Panel

struct DemoControlPanel: View {
    @ObservedObject var demoController = DemoModeController.shared
    @ObservedObject var speechManager: SpeechRecognitionManager
    @ObservedObject var avatarManager: AvatarVideoManager
    @Binding var showAvatarView: Bool
    
    @State private var selectedCategory = 0
    @State private var customWord = ""
    let categories = ["Greetings", "Responses", "Feelings", "Needs", "People"]
    
    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Image(systemName: "play.circle.fill")
                    .foregroundColor(.green)
                Text("Demo Mode")
                    .font(.headline)
                Spacer()
                Button("Hide") {
                    withAnimation {
                        demoController.showDemoControls = false
                    }
                }
                .font(.caption)
            }
            .padding(.horizontal)
            
            // Text input for custom word
            HStack {
                TextField("Type any word...", text: $customWord)
                    .textFieldStyle(.roundedBorder)
                
                Button("Play") {
                    if !customWord.isEmpty {
                        simulateSpokenWord(customWord.lowercased())
                        customWord = ""
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(customWord.isEmpty)
            }
            .padding(.horizontal)
            
            // Category picker
            Picker("Category", selection: $selectedCategory) {
                ForEach(0..<categories.count, id: \.self) { index in
                    Text(categories[index]).tag(index)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            
            // Word buttons grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                ForEach(wordsForCategory(selectedCategory), id: \.self) { word in
                    DemoWordButton(word: word) {
                        simulateSpokenWord(word)
                    }
                }
            }
            .padding(.horizontal)
            
            // Clear button
            Button(action: {
                avatarManager.stopVideo()
                speechManager.clearTranscription()
            }) {
                Label("Clear", systemImage: "xmark.circle")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 12)
        .background(Color(.systemBackground).opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 5)
        .padding()
    }
    
    private func wordsForCategory(_ index: Int) -> [String] {
        switch index {
        case 0: return ["hello", "bye", "good", "please", "sorry"]
        case 1: return ["yes", "no", "help", "stop", "wait"]
        case 2: return ["happy", "sad", "angry", "love", "fine"]
        case 3: return ["hungry", "thirsty", "water", "food", "tired"]
        case 4: return ["family", "friend", "father", "mother", "brother"]
        default: return []
        }
    }
    
    private func simulateSpokenWord(_ word: String) {
        // Switch to avatar view
        showAvatarView = true
        
        // Go through full speech recognition pipeline
        // This simulates the complete flow as if the word was spoken
        speechManager.simulateSpeech(word)
    }
}

// MARK: - Demo Word Button

struct DemoWordButton: View {
    let word: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(word.capitalized)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Color.blue.opacity(0.15))
                .foregroundColor(.blue)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - Demo Mode Toggle Button

struct DemoModeToggle: View {
    @ObservedObject var demoController = DemoModeController.shared
    
    var body: some View {
        Button(action: {
            withAnimation {
                demoController.showDemoControls.toggle()
            }
        }) {
            Image(systemName: demoController.showDemoControls ? "play.circle.fill" : "play.circle")
                .foregroundColor(.green)
        }
    }
}

// MARK: - Simulated Gesture Overlay

struct SimulatedGestureView: View {
    let gestureName: String
    
    var gestureEmoji: String {
        switch gestureName {
        case "Open_Palm": return "🖐️"
        case "Closed_Fist": return "✊"
        case "Pointing_Up": return "☝️"
        case "Thumb_Up": return "👍"
        case "Thumb_Down": return "👎"
        case "Victory": return "✌️"
        case "ILoveYou": return "🤟"
        default: return "👋"
        }
    }
    
    var body: some View {
        VStack {
            Text(gestureEmoji)
                .font(.system(size: 60))
            Text(gestureName.replacingOccurrences(of: "_", with: " "))
                .font(.caption)
                .foregroundColor(.white)
        }
        .padding()
        .background(Color.black.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
