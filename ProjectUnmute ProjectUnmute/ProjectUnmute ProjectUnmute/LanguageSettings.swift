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
                // Case-insensitive comparison and handle accent variations
                let normalizedSpanish = spanish.lowercased()
                let normalizedWord = word.folding(options: .diacriticInsensitive, locale: .current).lowercased()
                let normalizedSpanishNoAccent = normalizedSpanish.folding(options: .diacriticInsensitive, locale: .current)
                
                if normalizedSpanish == word || normalizedSpanishNoAccent == normalizedWord {
                    return english
                }
            }
            // Complete Spanish reverse lookup - all 100 words for video mapping
            let spanishVariations: [String: String] = [
                // Greetings
                "hola": "hello", "ola": "hello",
                "adios": "bye", "adiós": "bye", "chao": "bye", "chau": "bye",
                "buenos dias": "morning", "buenos días": "morning", "buen dia": "morning",
                "buenas noches": "night",
                // Responses
                "si": "yes", "sí": "yes",
                "no": "no",
                "quizas": "maybe", "quizás": "maybe", "tal vez": "maybe",
                "ok": "ok", "vale": "ok", "esta bien": "ok", "está bien": "ok",
                "por favor": "please", "porfavor": "please",
                "lo siento": "sorry", "perdon": "sorry", "perdón": "sorry", "disculpa": "sorry",
                "gracias": "thank you", "muchas gracias": "thank you",
                "disculpe": "excuse", "con permiso": "excuse",
                // Feelings
                "feliz": "happy", "contento": "happy", "alegre": "happy",
                "triste": "sad",
                "enojado": "angry", "enfadado": "angry", "molesto": "angry",
                "amor": "love",
                "te quiero": "i love you", "te amo": "i love you",
                "estoy bien": "fine",
                "cansado": "tired", "cansada": "tired",
                "hambriento": "hungry", "hambre": "hungry", "tengo hambre": "hungry",
                "sediento": "thirsty", "sed": "thirsty", "tengo sed": "thirsty",
                "enfermo": "sick", "enferma": "sick",
                "herido": "hurt", "herida": "hurt", "lastimado": "hurt",
                "dolor": "pain", "duele": "pain", "me duele": "pain",
                // Actions
                "ayuda": "help", "ayudar": "help", "ayudame": "help", "ayúdame": "help",
                "para": "stop", "parar": "stop", "alto": "stop", "detente": "stop",
                "espera": "wait", "esperar": "wait", "espere": "wait",
                "ve": "go", "ir": "go", "vamos": "go", "vete": "go",
                "ven": "come", "venir": "come", "venga": "come",
                "sientate": "sit", "siéntate": "sit", "sentar": "sit",
                "levantate": "stand", "levántate": "stand", "parate": "stand", "párate": "stand",
                "abre": "open", "abrir": "open",
                "cierra": "close", "cerrar": "close",
                "come": "eat", "comer": "eat",
                "bebe": "drink", "beber": "drink", "toma": "drink",
                "quiero": "want", "querer": "want",
                "necesito": "need", "necesitar": "need",
                "me gusta": "like", "gusta": "like", "gustar": "like",
                "se": "know", "sé": "know", "saber": "know", "conozco": "know",
                "entiendo": "understand", "entender": "understand", "comprendo": "understand",
                "terminar": "finish", "termino": "finish", "acabar": "finish",
                "hecho": "done", "listo": "done", "terminado": "done",
                "trabajo": "work", "trabajar": "work",
                // Questions
                "que": "what", "qué": "what",
                "donde": "where", "dónde": "where", "adonde": "where", "adónde": "where",
                "cuando": "when", "cuándo": "when",
                "quien": "who", "quién": "who",
                "por que": "why", "por qué": "why", "porque": "why",
                "como": "how", "cómo": "how",
                "cual": "which", "cuál": "which",
                // People
                "familia": "family",
                "amigo": "friend", "amiga": "friend",
                "padre": "father", "papa": "father", "papá": "father",
                "madre": "mother", "mama": "mother", "mamá": "mother",
                "hermano": "brother",
                "hermana": "sister",
                "doctor": "doctor", "doctora": "doctor", "medico": "doctor", "médico": "doctor",
                // Places
                "casa": "home", "hogar": "home",
                "escuela": "school", "colegio": "school",
                "bano": "bathroom", "baño": "bathroom",
                // Time
                "ahora": "now", "ya": "now",
                "despues": "later", "después": "later", "luego": "later", "mas tarde": "later",
                "hoy": "today",
                "manana": "tomorrow", "mañana": "tomorrow",
                "dia": "day", "día": "day",
                "semana": "week",
                "ano": "year", "año": "year",
                "otra vez": "again", "de nuevo": "again", "nuevamente": "again",
                // Numbers
                "uno": "one", "una": "one", "1": "one",
                "dos": "two", "2": "two",
                "tres": "three", "3": "three",
                "cuatro": "four", "4": "four",
                "cinco": "five", "5": "five",
                "seis": "six", "6": "six",
                "siete": "seven", "7": "seven",
                "ocho": "eight", "8": "eight",
                "nueve": "nine", "9": "nine",
                "diez": "ten", "10": "ten",
                // Colors
                "rojo": "red", "roja": "red",
                "azul": "blue",
                "verde": "green",
                "amarillo": "yellow", "amarilla": "yellow",
                "naranja": "orange", "anaranjado": "orange",
                "morado": "purple", "purpura": "purple", "púrpura": "purple", "violeta": "purple",
                "rosa": "pink", "rosado": "pink",
                "negro": "black", "negra": "black",
                "blanco": "white", "blanca": "white",
                "marron": "brown", "marrón": "brown", "cafe": "brown", "café": "brown",
                // Descriptions
                "bueno": "good", "buena": "good", "bien": "good",
                "malo": "bad", "mala": "bad",
                "grande": "big",
                "pequeno": "small", "pequeño": "small", "pequena": "small", "pequeña": "small", "chico": "small",
                "caliente": "hot",
                "frio": "cold", "frío": "cold", "fria": "cold", "fría": "cold",
                "genial": "cool", "chevere": "cool", "chévere": "cool", "guay": "cool",
                "mas": "more", "más": "more",
                "todo": "all", "todos": "all", "toda": "all", "todas": "all",
                "nombre": "name",
                "agua": "water",
                "comida": "food"
            ]
            if let english = spanishVariations[word] {
                return english
            }
            return word  // Return as-is if not found
            
        case .mandarin:
            // Reverse lookup: find English word that maps to this Mandarin word
            for (english, mandarin) in mandarinTranslations {
                if mandarin == word {
                    return english
                }
            }
            // Complete Mandarin reverse lookup - all 100 words for video mapping
            let mandarinVariations: [String: String] = [
                // Greetings
                "你好": "hello", "嗨": "hello", "哈啰": "hello",
                "再见": "bye", "再見": "bye", "拜拜": "bye",
                "早上好": "morning", "早安": "morning",
                "晚安": "night", "晚上好": "night",
                // Responses
                "是": "yes", "是的": "yes", "对": "yes", "對": "yes",
                "不": "no", "不是": "no", "没有": "no",
                "也许": "maybe", "也許": "maybe", "可能": "maybe",
                "好的": "ok", "可以": "ok", "行": "ok",
                "请": "please", "請": "please",
                "对不起": "sorry", "對不起": "sorry", "抱歉": "sorry",
                "谢谢": "thank you", "謝謝": "thank you", "感谢": "thank you",
                "打扰一下": "excuse", "打擾一下": "excuse", "不好意思": "excuse",
                // Feelings
                "快乐": "happy", "快樂": "happy", "开心": "happy", "高兴": "happy",
                "悲伤": "sad", "悲傷": "sad", "难过": "sad", "伤心": "sad",
                "生气": "angry", "生氣": "angry", "愤怒": "angry",
                "爱": "love", "愛": "love",
                "我爱你": "i love you", "我愛你": "i love you",
                "很好": "fine", "还好": "fine", "不错": "fine",
                "累": "tired", "疲倦": "tired", "疲劳": "tired",
                "饿": "hungry", "餓": "hungry", "饥饿": "hungry",
                "渴": "thirsty", "口渴": "thirsty",
                "生病": "sick", "病了": "sick", "不舒服": "sick",
                "受伤": "hurt", "受傷": "hurt", "疼": "hurt",
                "疼痛": "pain", "痛": "pain",
                // Actions
                "帮助": "help", "幫助": "help", "帮忙": "help",
                "停": "stop", "停止": "stop",
                "等": "wait", "等待": "wait", "等一下": "wait",
                "去": "go", "走": "go",
                "来": "come", "來": "come", "过来": "come",
                "坐": "sit", "坐下": "sit",
                "站": "stand", "站起来": "stand",
                "开": "open", "開": "open", "打开": "open",
                "关": "close", "關": "close", "关闭": "close",
                "吃": "eat", "吃饭": "eat",
                "喝": "drink", "喝水": "drink",
                "想要": "want", "要": "want",
                "需要": "need",
                "喜欢": "like", "喜歡": "like",
                "知道": "know",
                "明白": "understand", "理解": "understand", "懂": "understand",
                "完成": "finish",
                "完成了": "done", "做完了": "done", "好了": "done",
                "工作": "work",
                // Questions
                "什么": "what", "什麼": "what",
                "哪里": "where", "哪裡": "where", "在哪": "where",
                "什么时候": "when", "什麼時候": "when", "几点": "when",
                "谁": "who", "誰": "who",
                "为什么": "why", "為什麼": "why",
                "怎么": "how", "怎麼": "how", "如何": "how",
                "哪个": "which", "哪個": "which",
                // People
                "家人": "family", "家庭": "family",
                "朋友": "friend",
                "父亲": "father", "父親": "father", "爸爸": "father",
                "母亲": "mother", "母親": "mother", "妈妈": "mother",
                "兄弟": "brother", "哥哥": "brother", "弟弟": "brother",
                "姐妹": "sister", "姐姐": "sister", "妹妹": "sister",
                "医生": "doctor", "醫生": "doctor",
                // Places
                "家": "home", "房子": "home",
                "学校": "school", "學校": "school",
                "洗手间": "bathroom", "洗手間": "bathroom", "厕所": "bathroom", "卫生间": "bathroom",
                // Time
                "现在": "now", "現在": "now",
                "稍后": "later", "稍後": "later", "以后": "later", "之后": "later",
                "今天": "today",
                "明天": "tomorrow",
                "天": "day", "日": "day",
                "周": "week", "週": "week", "星期": "week",
                "年": "year",
                "再次": "again", "再": "again", "又": "again",
                // Numbers
                "一": "one", "1": "one",
                "二": "two", "两": "two", "兩": "two", "2": "two",
                "三": "three", "3": "three",
                "四": "four", "4": "four",
                "五": "five", "5": "five",
                "六": "six", "6": "six",
                "七": "seven", "7": "seven",
                "八": "eight", "8": "eight",
                "九": "nine", "9": "nine",
                "十": "ten", "10": "ten",
                // Colors
                "红色": "red", "紅色": "red", "红": "red",
                "蓝色": "blue", "藍色": "blue", "蓝": "blue",
                "绿色": "green", "綠色": "green", "绿": "green",
                "黄色": "yellow", "黃色": "yellow", "黄": "yellow",
                "橙色": "orange", "橙": "orange",
                "紫色": "purple", "紫": "purple",
                "粉色": "pink", "粉红": "pink", "粉": "pink",
                "黑色": "black", "黑": "black",
                "白色": "white", "白": "white",
                "棕色": "brown", "褐色": "brown",
                // Descriptions
                "好": "good", "棒": "good",
                "坏": "bad", "壞": "bad", "不好": "bad",
                "大": "big",
                "小": "small",
                "热": "hot", "熱": "hot",
                "冷": "cold",
                "酷": "cool", "凉快": "cool",
                "更多": "more", "多": "more",
                "全部": "all", "所有": "all", "都": "all",
                "名字": "name", "姓名": "name",
                "水": "water",
                "食物": "food", "吃的": "food"
            ]
            if let english = mandarinVariations[word] {
                return english
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
