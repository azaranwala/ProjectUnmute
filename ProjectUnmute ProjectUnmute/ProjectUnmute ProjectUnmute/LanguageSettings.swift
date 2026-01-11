import Foundation
import SwiftUI

/// Supported languages for speech recognition and text-to-speech
enum LanguagePreference: String, CaseIterable, Identifiable {
    case english = "en-US"
    case spanish = "es-ES"
    case mandarin = "zh-Hans-CN"  // Use zh-Hans-CN for better iOS compatibility
    
    var id: String { rawValue }
    
    /// Display name for the language
    var displayName: String {
        switch self {
        case .english: return "English"
        case .spanish: return "Español"
        case .mandarin: return "中文"
        }
    }
    
    /// Flag emoji for visual identification
    var flag: String {
        switch self {
        case .english: return "🇺🇸"
        case .spanish: return "🇪🇸"
        case .mandarin: return "🇨🇳"
        }
    }
    
    /// Locale identifier for speech recognition
    var speechRecognitionLocale: Locale {
        switch self {
        case .english: return Locale(identifier: "en-US")
        case .spanish: return Locale(identifier: "es-ES")
        case .mandarin: return Locale(identifier: "zh-CN")  // iOS speech recognizer uses zh-CN
        }
    }
    
    /// Voice identifier for text-to-speech (AVSpeechSynthesizer)
    var ttsLanguageCode: String {
        switch self {
        case .english: return "en-US"
        case .spanish: return "es-ES"
        case .mandarin: return "zh-CN"
        }
    }
    
    /// Common words mapping - maps English ASL signs to translated phrases
    func translatedPhrase(for englishSign: String) -> String {
        let sign = englishSign.lowercased()
        
        switch self {
        case .english:
            return englishSign
            
        case .spanish:
            return spanishTranslations[sign] ?? englishSign
            
        case .mandarin:
            return mandarinTranslations[sign] ?? englishSign
        }
    }
    
    /// Reverse translation - maps spoken word in current language back to English for video lookup
    func toEnglish(from spokenWord: String) -> String {
        let word = spokenWord.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        switch self {
        case .english:
            return word
            
        case .spanish:
            // Reverse lookup: find English word that maps to this Spanish word
            for (english, spanish) in spanishTranslations {
                if spanish.lowercased() == word {
                    return english
                }
            }
            return word  // Return as-is if not found
            
        case .mandarin:
            // Reverse lookup: find English word that maps to this Mandarin word
            for (english, mandarin) in mandarinTranslations {
                if mandarin == word {
                    return english
                }
            }
            return word  // Return as-is if not found
        }
    }
    
    // Spanish translations for common ASL signs
    // Maps English word -> Spanish word (for TTS output)
    // The toEnglish() function reverses this for speech recognition input
    private var spanishTranslations: [String: String] {
        [
            // Greetings
            "hello": "hola",
            "hi": "hola",
            "bye": "adiós",
            "goodbye": "adiós",
            "morning": "buenos días",
            "night": "buenas noches",
            // Responses
            "yes": "sí",
            "no": "no",
            "maybe": "quizás",
            "ok": "ok",
            "please": "por favor",
            "sorry": "lo siento",
            "thank you": "gracias",
            "thank_you": "gracias",
            "excuse": "perdón",
            // Feelings
            "happy": "feliz",
            "sad": "triste",
            "angry": "enojado",
            "love": "amor",
            "i love you": "te quiero",
            "fine": "bien",
            "tired": "cansado",
            "hungry": "hambriento",
            "thirsty": "sediento",
            "sick": "enfermo",
            "hurt": "herido",
            "pain": "dolor",
            // Actions
            "help": "ayuda",
            "stop": "para",
            "wait": "espera",
            "go": "ve",
            "come": "ven",
            "sit": "siéntate",
            "stand": "levántate",
            "open": "abre",
            "close": "cierra",
            "eat": "come",
            "drink": "bebe",
            "want": "quiero",
            "need": "necesito",
            "like": "me gusta",
            "know": "sé",
            "understand": "entiendo",
            "finish": "terminar",
            "done": "hecho",
            "work": "trabajo",
            // Questions
            "what": "qué",
            "where": "dónde",
            "when": "cuándo",
            "who": "quién",
            "why": "por qué",
            "how": "cómo",
            "which": "cuál",
            // People
            "family": "familia",
            "friend": "amigo",
            "father": "padre",
            "mother": "madre",
            "brother": "hermano",
            "sister": "hermana",
            "doctor": "doctor",
            // Places
            "home": "casa",
            "school": "escuela",
            "bathroom": "baño",
            // Time
            "now": "ahora",
            "later": "después",
            "today": "hoy",
            "tomorrow": "mañana",
            "day": "día",
            "week": "semana",
            "year": "año",
            "again": "otra vez",
            // Numbers
            "one": "uno",
            "two": "dos",
            "three": "tres",
            "four": "cuatro",
            "five": "cinco",
            "six": "seis",
            "seven": "siete",
            "eight": "ocho",
            "nine": "nueve",
            "ten": "diez",
            // Colors
            "red": "rojo",
            "blue": "azul",
            "green": "verde",
            "yellow": "amarillo",
            "orange": "naranja",
            "purple": "morado",
            "pink": "rosa",
            "black": "negro",
            "white": "blanco",
            "brown": "marrón",
            // Descriptions
            "good": "bueno",
            "bad": "malo",
            "big": "grande",
            "small": "pequeño",
            "hot": "caliente",
            "cold": "frío",
            "cool": "genial",
            "more": "más",
            "all": "todo",
            "name": "nombre",
            "water": "agua",
            "food": "comida"
        ]
    }
    
    // Mandarin translations for common ASL signs
    private var mandarinTranslations: [String: String] {
        [
            // Greetings
            "hello": "你好",
            "hi": "嗨",
            "bye": "再见",
            "goodbye": "再见",
            "morning": "早上好",
            "night": "晚安",
            // Responses
            "yes": "是",
            "no": "不",
            "maybe": "也许",
            "ok": "好的",
            "please": "请",
            "sorry": "对不起",
            "thank you": "谢谢",
            "thank_you": "谢谢",
            "excuse": "打扰一下",
            // Feelings
            "happy": "快乐",
            "sad": "悲伤",
            "angry": "生气",
            "love": "爱",
            "i love you": "我爱你",
            "fine": "很好",
            "tired": "累",
            "hungry": "饿",
            "thirsty": "渴",
            "sick": "生病",
            "hurt": "受伤",
            "pain": "疼痛",
            // Actions
            "help": "帮助",
            "stop": "停",
            "wait": "等",
            "go": "去",
            "come": "来",
            "sit": "坐",
            "stand": "站",
            "open": "开",
            "close": "关",
            "eat": "吃",
            "drink": "喝",
            "want": "想要",
            "need": "需要",
            "like": "喜欢",
            "know": "知道",
            "understand": "明白",
            "finish": "完成",
            "done": "完成了",
            "work": "工作",
            // Questions
            "what": "什么",
            "where": "哪里",
            "when": "什么时候",
            "who": "谁",
            "why": "为什么",
            "how": "怎么",
            "which": "哪个",
            // People
            "family": "家人",
            "friend": "朋友",
            "father": "父亲",
            "mother": "母亲",
            "brother": "兄弟",
            "sister": "姐妹",
            "doctor": "医生",
            // Places
            "home": "家",
            "school": "学校",
            "bathroom": "洗手间",
            // Time
            "now": "现在",
            "later": "稍后",
            "today": "今天",
            "tomorrow": "明天",
            "day": "天",
            "week": "周",
            "year": "年",
            "again": "再次",
            // Numbers
            "one": "一",
            "two": "二",
            "three": "三",
            "four": "四",
            "five": "五",
            "six": "六",
            "seven": "七",
            "eight": "八",
            "nine": "九",
            "ten": "十",
            // Colors
            "red": "红色",
            "blue": "蓝色",
            "green": "绿色",
            "yellow": "黄色",
            "orange": "橙色",
            "purple": "紫色",
            "pink": "粉色",
            "black": "黑色",
            "white": "白色",
            "brown": "棕色",
            // Descriptions
            "good": "好",
            "bad": "坏",
            "big": "大",
            "small": "小",
            "hot": "热",
            "cold": "冷",
            "cool": "酷",
            "more": "更多",
            "all": "全部",
            "name": "名字",
            "water": "水",
            "food": "食物"
        ]
    }
}

/// Singleton manager for language settings
final class LanguageSettingsManager: ObservableObject {
    static let shared = LanguageSettingsManager()
    
    @Published var selectedLanguage: LanguagePreference {
        didSet {
            UserDefaults.standard.set(selectedLanguage.rawValue, forKey: "selectedLanguage")
        }
    }
    
    private init() {
        if let savedLanguage = UserDefaults.standard.string(forKey: "selectedLanguage"),
           let language = LanguagePreference(rawValue: savedLanguage) {
            self.selectedLanguage = language
        } else {
            self.selectedLanguage = .english
        }
    }
}

/// Sheet view for selecting language preference
struct LanguagePickerSheet: View {
    @Binding var selectedLanguage: LanguagePreference
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Select Language")
                    .font(.headline)
                    .padding(.top)
                
                ForEach(LanguagePreference.allCases) { language in
                    Button(action: {
                        selectedLanguage = language
                        dismiss()
                    }) {
                        HStack {
                            Text(language.flag)
                                .font(.title)
                            Text(language.displayName)
                                .font(.title3)
                            Spacer()
                            if selectedLanguage == language {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                        }
                        .padding()
                        .background(selectedLanguage == language ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer()
            }
            .padding(.horizontal)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
