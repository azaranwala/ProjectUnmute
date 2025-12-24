import SwiftUI

// MARK: - ASL Detection View

/// View displaying detected ASL signs and converted text
struct ASLDetectionView: View {
    @ObservedObject var detector = ASLSignDetector.shared
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "hand.raised.fill")
                    .foregroundColor(.blue)
                Text("ASL → Text")
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
            if let sign = detector.detectedSign {
                VStack(spacing: 4) {
                    HStack {
                        Text("🖐 Detected:")
                            .foregroundColor(.orange)
                        Text(sign)
                            .font(.title.bold())
                            .foregroundColor(.blue)
                    }
                    
                    // Confidence bar
                    HStack {
                        Text("Confidence:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        ProgressView(value: Double(detector.confidence))
                            .tint(detector.confidence > 0.8 ? .green : .orange)
                        Text("\(Int(detector.confidence * 100))%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Text("Hold sign for 1 second to confirm")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .background(Color.yellow.opacity(0.1))
                .cornerRadius(8)
            } else if detector.isDetecting {
                Text("👀 Looking for hand signs...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // Detected sentence
            VStack(alignment: .leading, spacing: 8) {
                Text("Sentence:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(detector.detectedSentence.isEmpty ? "Show ASL signs to build a sentence..." : detector.detectedSentence)
                    .font(.title3)
                    .foregroundColor(detector.detectedSentence.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            
            // Action buttons
            HStack(spacing: 12) {
                // Add space
                Button(action: { detector.addSpace() }) {
                    Label("Space", systemImage: "space")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                
                // Speak
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

// MARK: - ASL Demo Panel (for Simulator)

/// Demo panel to simulate ASL signs in the simulator
struct ASLDemoPanel: View {
    @ObservedObject var detector = ASLSignDetector.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title - using Color() explicitly
            Text("TAP WORDS TO BUILD SENTENCE")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Color(red: 0, green: 0, blue: 0))
            
            // Row 1
            HStack(spacing: 8) {
                WordButton(word: "Hello", detector: detector)
                WordButton(word: "Good", detector: detector)
                WordButton(word: "Yes", detector: detector)
                WordButton(word: "No", detector: detector)
            }
            
            // Row 2
            HStack(spacing: 8) {
                WordButton(word: "Please", detector: detector)
                WordButton(word: "Thanks", detector: detector)
                WordButton(word: "Help", detector: detector)
                WordButton(word: "Stop", detector: detector)
            }
            
            // Numbers row
            HStack(spacing: 8) {
                NumButton(num: "1", detector: detector)
                NumButton(num: "2", detector: detector)
                NumButton(num: "3", detector: detector)
                NumButton(num: "4", detector: detector)
                NumButton(num: "5", detector: detector)
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange, lineWidth: 3)
        )
        .environment(\.colorScheme, .light)
    }
}

// Separate view for word buttons
struct WordButton: View {
    let word: String
    let detector: ASLSignDetector
    
    var body: some View {
        Text(word)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(Color(red: 0, green: 0, blue: 0.8))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(red: 0.9, green: 0.95, blue: 1.0))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.blue, lineWidth: 1)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                detector.simulateDetectedSign(word)
            }
    }
}

// Separate view for number buttons
struct NumButton: View {
    let num: String
    let detector: ASLSignDetector
    
    var body: some View {
        Text(num)
            .font(.system(size: 16, weight: .bold))
            .foregroundColor(Color(red: 0, green: 0.5, blue: 0))
            .frame(width: 44, height: 40)
            .background(Color(red: 0.9, green: 1.0, blue: 0.9))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.green, lineWidth: 1)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                detector.simulateDetectedSign(num)
            }
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
