import SwiftUI

// MARK: - ASL Detection View

/// View displaying detected ASL signs and converted text
struct ASLDetectionView: View {
    @ObservedObject var detector = ASLSignDetector.shared
    @ObservedObject private var languageSettings = LanguageSettingsManager.shared
    
    /// Translate the detected sentence to the selected language
    private var translatedSentence: String {
        guard !detector.detectedSentence.isEmpty else { return "" }
        let words = detector.detectedSentence.components(separatedBy: " ")
        let translatedWords = words.map { languageSettings.selectedLanguage.translatedPhrase(for: $0) }
        return translatedWords.joined(separator: " ")
    }
    
    /// Translate a single detected sign
    private var translatedSign: String? {
        guard let sign = detector.detectedSign else { return nil }
        if sign == "Do not recognize" {
            return sign
        }
        return languageSettings.selectedLanguage.translatedPhrase(for: sign)
    }
    
    /// Localized label for sentence section
    private var sentenceLabel: String {
        switch languageSettings.selectedLanguage {
        case .english: return "Sentence:"
        case .spanish: return "Oración:"
        case .mandarin: return "句子："
        }
    }
    
    /// Localized placeholder text
    private var placeholderText: String {
        switch languageSettings.selectedLanguage {
        case .english: return "Show ASL signs to build a sentence..."
        case .spanish: return "Muestra señas ASL para formar una oración..."
        case .mandarin: return "展示ASL手语来构建句子..."
        }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "hand.raised.fill")
                    .foregroundColor(.blue)
                Text("ASL → Speech")
                    .font(.headline)
                Spacer()
                
                // Hand visibility indicator
                HStack(spacing: 4) {
                    Circle()
                        .fill(detector.handVisible ? Color.green : Color.gray)
                        .frame(width: 10, height: 10)
                    Text(detector.handVisible ? "Hand Visible" : "No Hand")
                        .font(.caption)
                        .foregroundColor(detector.handVisible ? .green : .secondary)
                }
            }
            
            // Currently detected sign with confidence
            if let sign = detector.detectedSign, let displaySign = translatedSign {
                VStack(spacing: 4) {
                    HStack {
                        Text("🖐 Detected:")
                            .foregroundColor(.orange)
                        Text(displaySign)
                            .font(.title.bold())
                            .foregroundColor(sign == "Do not recognize" ? .red : .blue)
                    }
                    
                    // Confidence bar with threshold indicator
                    HStack {
                        Text("Confidence:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        ZStack(alignment: .leading) {
                            ProgressView(value: Double(detector.confidence))
                                .tint(detector.confidence >= 0.70 ? .green : .red)
                            // 70% threshold marker
                            GeometryReader { geo in
                                Rectangle()
                                    .fill(Color.orange)
                                    .frame(width: 2)
                                    .offset(x: geo.size.width * 0.70)
                            }
                        }
                        Text("\(Int(detector.confidence * 100))%")
                            .font(.caption2)
                            .foregroundColor(detector.confidence >= 0.70 ? .green : .red)
                    }
                    
                    // Status message based on confidence
                    if sign == "Do not recognize" {
                        Text("⚠️ Confidence below 70% threshold")
                            .font(.caption2)
                            .foregroundColor(.red)
                    } else {
                        Text("Hold sign for 1 second to confirm")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(8)
                .background(sign == "Do not recognize" ? Color.red.opacity(0.1) : Color.yellow.opacity(0.1))
                .cornerRadius(8)
            } else if detector.isDetecting {
                Text("👀 Looking for hand signs...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // Detected sentence (translated)
            VStack(alignment: .leading, spacing: 8) {
                Text(sentenceLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(translatedSentence.isEmpty ? placeholderText : translatedSentence)
                    .font(.title3)
                    .foregroundColor(translatedSentence.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            
            // Auto-speak toggle
            HStack {
                Image(systemName: detector.autoSpeakEnabled ? "speaker.wave.3.fill" : "speaker.slash.fill")
                    .foregroundColor(detector.autoSpeakEnabled ? .green : .gray)
                Toggle("Auto-speak signs", isOn: $detector.autoSpeakEnabled)
                    .font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(.systemGray6))
            .cornerRadius(8)
            
            // Action buttons
            HStack(spacing: 12) {
                // Add space
                Button(action: { detector.addSpace() }) {
                    Label("Space", systemImage: "space")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                
                // Speak sentence
                Button(action: { detector.speakSentence() }) {
                    Label("Speak", systemImage: "speaker.wave.2.fill")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .disabled(detector.detectedSentence.isEmpty)
                
                // Clear
                Button(action: { detector.clearSentence() }) {
                    Label("Clear", systemImage: "xmark.circle")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 2)
    }
}

// MARK: - ASL Signs Reference Card

/// Quick reference of detectable ASL signs
struct ASLSignsReferenceView: View {
    let signs = [
        ("👋", "Hello", "Open palm"),
        ("👍", "Good", "Thumbs up"),
        ("✌️", "Peace/2", "V sign"),
        ("🤟", "I Love You", "Thumb+Index+Pinky"),
        ("☝️", "1/Point", "Index only"),
        ("✋", "Stop/5", "Open hand"),
        ("🤘", "Y", "Thumb+Pinky"),
        ("✊", "Yes/A", "Fist"),
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Detectable Signs")
                .font(.caption.bold())
                .foregroundColor(.secondary)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(signs, id: \.1) { emoji, word, desc in
                    HStack {
                        Text(emoji)
                        VStack(alignment: .leading) {
                            Text(word)
                                .font(.caption.bold())
                            Text(desc)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(6)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .padding()
    }
}

// MARK: - Preview

#Preview {
    VStack {
        ASLDetectionView()
        ASLSignsReferenceView()
    }
    .padding()
}
