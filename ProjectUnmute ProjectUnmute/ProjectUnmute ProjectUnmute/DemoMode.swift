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
    @ObservedObject private var languageSettings = LanguageSettingsManager.shared
    
    var categories: [String] {
        let language = languageSettings.selectedLanguage
        switch language {
        case .english:
            return ["Greetings", "Responses", "Feelings", "Needs", "People"]
        case .spanish:
            return ["Saludos", "Respuestas", "Sentimientos", "Necesidades", "Personas"]
        case .mandarin:
            return ["问候", "回应", "感受", "需求", "人物"]
        }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Image(systemName: "play.circle.fill")
                    .foregroundColor(.green)
                Text(headerText)
                    .font(.headline)
                Spacer()
                Button(hideButtonText) {
                    withAnimation {
                        demoController.showDemoControls = false
                    }
                }
                .font(.caption)
            }
            .padding(.horizontal)
            
            // Text input for custom word
            HStack {
                TextField(placeholderText, text: $customWord)
                    .textFieldStyle(.roundedBorder)
                
                Button(playButtonText) {
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
                Label(clearButtonText, systemImage: "xmark.circle")
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
    
    // Localized text properties
    private var headerText: String {
        switch languageSettings.selectedLanguage {
        case .english: return "Demo Mode"
        case .spanish: return "Modo Demo"
        case .mandarin: return "演示模式"
        }
    }
    
    private var hideButtonText: String {
        switch languageSettings.selectedLanguage {
        case .english: return "Hide"
        case .spanish: return "Ocultar"
        case .mandarin: return "隐藏"
        }
    }
    
    private var placeholderText: String {
        switch languageSettings.selectedLanguage {
        case .english: return "Type any word..."
        case .spanish: return "Escribe una palabra..."
        case .mandarin: return "输入任何单词..."
        }
    }
    
    private var playButtonText: String {
        switch languageSettings.selectedLanguage {
        case .english: return "Play"
        case .spanish: return "Reproducir"
        case .mandarin: return "播放"
        }
    }
    
    private var clearButtonText: String {
        switch languageSettings.selectedLanguage {
        case .english: return "Clear"
        case .spanish: return "Borrar"
        case .mandarin: return "清除"
        }
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
    @ObservedObject private var languageSettings = LanguageSettingsManager.shared
    
    var displayWord: String {
        languageSettings.selectedLanguage.translatedPhrase(for: word).capitalized
    }
    
    var body: some View {
        Button(action: action) {
            Text(displayWord)
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

// MARK: - ASL Demo Panel (for ASL→Speech mode)

struct ASLDemoPanel: View {
    @ObservedObject var aslDetector: ASLSignDetector
    @ObservedObject private var languageSettings = LanguageSettingsManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "hand.tap.fill")
                    .foregroundColor(.orange)
                Text(headerText)
                    .font(.caption.bold())
                    .foregroundColor(.black)
            }
            
            // Word buttons - Row 1
            HStack(spacing: 6) {
                ForEach(["Hello", "Good", "Yes", "No"], id: \.self) { word in
                    ASLDemoButton(word: word, color: .blue) {
                        aslDetector.simulateDetectedSign(word)
                    }
                }
            }
            
            // Word buttons - Row 2
            HStack(spacing: 6) {
                ForEach(["Please", "Thanks", "Help", "Stop"], id: \.self) { word in
                    ASLDemoButton(word: word, color: .green) {
                        aslDetector.simulateDetectedSign(word)
                    }
                }
            }
            
            // Numbers
            HStack(spacing: 6) {
                ForEach(["1", "2", "3", "4", "5"], id: \.self) { num in
                    Button(num) {
                        aslDetector.simulateDetectedSign(num)
                    }
                    .font(.caption.bold())
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.orange)
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange, lineWidth: 3)
        )
    }
    
    private var headerText: String {
        switch languageSettings.selectedLanguage {
        case .english: return "DEMO MODE - Tap to simulate signs"
        case .spanish: return "MODO DEMO - Toca para simular señas"
        case .mandarin: return "演示模式 - 点击模拟手语"
        }
    }
}

struct ASLDemoButton: View {
    let word: String
    let color: Color
    let action: () -> Void
    @ObservedObject private var languageSettings = LanguageSettingsManager.shared
    
    var displayWord: String {
        languageSettings.selectedLanguage.translatedPhrase(for: word).capitalized
    }
    
    var body: some View {
        Button(displayWord) {
            action()
        }
        .font(.caption.bold())
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(color)
        .cornerRadius(8)
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
