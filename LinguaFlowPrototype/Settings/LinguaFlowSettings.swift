import Carbon
import Combine
import Foundation
import LinguaFlowCore

enum SettingsSection: String, CaseIterable, Identifiable {
    case overview
    case candidates
    case translation
    case learning
    case vocabulary
    case vocabularyLibrary
    case motion
    case membership

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "概览"
        case .candidates: "候选词"
        case .translation: "翻译"
        case .learning: "学习"
        case .vocabulary: "词汇卡片"
        case .vocabularyLibrary: "词汇库"
        case .motion: "动效与外观"
        case .membership: "LinguaFlow Plus"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "circle.grid.2x2.fill"
        case .candidates: "text.bubble.fill"
        case .translation: "character.book.closed.fill"
        case .learning: "brain.head.profile.fill"
        case .vocabulary: "rectangle.stack.fill"
        case .vocabularyLibrary: "books.vertical.fill"
        case .motion: "waveform.path"
        case .membership: "sparkles"
        }
    }
}

enum TranslationPosition: String, CaseIterable, Identifiable {
    case right
    case below

    var id: String { rawValue }
    var title: String { self == .right ? "右侧" : "下方" }
}

enum TranslationStyle: String, CaseIterable, Identifiable {
    case concise
    case natural
    case professional

    var id: String { rawValue }

    var title: String {
        switch self {
        case .concise: "简洁"
        case .natural: "自然"
        case .professional: "专业"
        }
    }
}

enum LearningLevel: String, CaseIterable, Identifiable {
    case foundation
    case intermediate
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .foundation: "基础"
        case .intermediate: "进阶"
        case .advanced: "高级"
        }
    }

    var detail: String {
        switch self {
        case .foundation: "优先展示高频、直观且易记的释义。"
        case .intermediate: "在常用释义之外，逐步加入自然表达与短语。"
        case .advanced: "强调语境差异、地道搭配与专业表达。"
        }
    }
}

enum LearningDomain: String, CaseIterable, Identifiable {
    case general
    case technology
    case academic
    case business

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "通用"
        case .technology: "科技"
        case .academic: "学术"
        case .business: "商务"
        }
    }
}

enum TargetLanguage: String, CaseIterable, Identifiable {
    case english
    case spanish
    case japanese

    var id: String { rawValue }

    var title: String {
        switch self {
        case .english: "English"
        case .spanish: "Español"
        case .japanese: "日本語"
        }
    }
}

@MainActor
final class LinguaFlowSettings: ObservableObject {
    private enum Key {
        static let candidateScale = "settings.candidateScale"
        static let candidateCount = "settings.candidateCount"
        static let translationPosition = "settings.translationPosition"
        static let translationStyle = "settings.translationStyle"
        static let targetLanguage = "settings.targetLanguage"
        static let learningLevel = "settings.learningLevel"
        static let learningDomain = "settings.learningDomain"
        static let glassEnabled = "settings.glassEnabled"
        static let translationEnabled = "settings.translationEnabled"
        static let quietFlowEnabled = "settings.quietFlowEnabled"
        static let magnifyingHoverEnabled = "settings.magnifyingHoverEnabled"
        static let pointerLightEnabled = "settings.pointerLightEnabled"
        static let vocabularyCardEnabled = "settings.vocabularyCardEnabled"
        static let pronunciationEnabled = "settings.pronunciationEnabled"
        static let exposureCountEnabled = "settings.exposureCountEnabled"
        static let contextHintsEnabled = "settings.contextHintsEnabled"
        static let chineseDefinitionEnabled = "settings.chineseDefinitionEnabled"
        static let englishDefinitionEnabled = "settings.englishDefinitionEnabled"
        static let examplesEnabled = "settings.examplesEnabled"
        static let phrasesEnabled = "settings.phrasesEnabled"
        static let hoverDelay = "settings.hoverDelay"
        static let ambientIntensity = "settings.ambientIntensity"
    }

    @Published var candidateScale: Double { didSet { defaults.set(candidateScale, forKey: Key.candidateScale) } }
    @Published var candidateCount: Int { didSet { defaults.set(candidateCount, forKey: Key.candidateCount) } }
    @Published var translationPosition: TranslationPosition { didSet { defaults.set(translationPosition.rawValue, forKey: Key.translationPosition) } }
    @Published var translationStyle: TranslationStyle { didSet { defaults.set(translationStyle.rawValue, forKey: Key.translationStyle) } }
    @Published var targetLanguage: TargetLanguage { didSet { defaults.set(targetLanguage.rawValue, forKey: Key.targetLanguage) } }
    @Published var languageDirection: LanguageDirection { didSet { LanguageDirectionStore.shared.set(languageDirection) } }
    @Published var learningLevel: LearningLevel { didSet { defaults.set(learningLevel.rawValue, forKey: Key.learningLevel) } }
    @Published var learningDomain: LearningDomain { didSet { defaults.set(learningDomain.rawValue, forKey: Key.learningDomain) } }
    @Published var glassEnabled: Bool { didSet { defaults.set(glassEnabled, forKey: Key.glassEnabled) } }
    @Published var translationEnabled: Bool { didSet { defaults.set(translationEnabled, forKey: Key.translationEnabled) } }
    @Published var quietFlowEnabled: Bool { didSet { defaults.set(quietFlowEnabled, forKey: Key.quietFlowEnabled) } }
    @Published var magnifyingHoverEnabled: Bool { didSet { defaults.set(magnifyingHoverEnabled, forKey: Key.magnifyingHoverEnabled) } }
    @Published var pointerLightEnabled: Bool { didSet { defaults.set(pointerLightEnabled, forKey: Key.pointerLightEnabled) } }
    @Published var vocabularyCardEnabled: Bool { didSet { defaults.set(vocabularyCardEnabled, forKey: Key.vocabularyCardEnabled) } }
    @Published var pronunciationEnabled: Bool { didSet { defaults.set(pronunciationEnabled, forKey: Key.pronunciationEnabled) } }
    @Published var exposureCountEnabled: Bool { didSet { defaults.set(exposureCountEnabled, forKey: Key.exposureCountEnabled) } }
    @Published var contextHintsEnabled: Bool { didSet { defaults.set(contextHintsEnabled, forKey: Key.contextHintsEnabled) } }
    @Published var chineseDefinitionEnabled: Bool { didSet { defaults.set(chineseDefinitionEnabled, forKey: Key.chineseDefinitionEnabled) } }
    @Published var englishDefinitionEnabled: Bool { didSet { defaults.set(englishDefinitionEnabled, forKey: Key.englishDefinitionEnabled) } }
    @Published var examplesEnabled: Bool { didSet { defaults.set(examplesEnabled, forKey: Key.examplesEnabled) } }
    @Published var phrasesEnabled: Bool { didSet { defaults.set(phrasesEnabled, forKey: Key.phrasesEnabled) } }
    @Published var hoverDelay: Double { didSet { defaults.set(hoverDelay, forKey: Key.hoverDelay) } }
    @Published var ambientIntensity: Double { didSet { defaults.set(ambientIntensity, forKey: Key.ambientIntensity) } }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        candidateScale = defaults.object(forKey: Key.candidateScale) as? Double ?? 1.0
        candidateCount = defaults.object(forKey: Key.candidateCount) as? Int ?? 5
        translationPosition = Self.value(for: Key.translationPosition, in: defaults, fallback: .right)
        translationStyle = Self.value(for: Key.translationStyle, in: defaults, fallback: .professional)
        targetLanguage = Self.value(for: Key.targetLanguage, in: defaults, fallback: .english)
        languageDirection = LanguageDirectionStore.shared.current()
        learningLevel = Self.value(for: Key.learningLevel, in: defaults, fallback: .intermediate)
        learningDomain = Self.value(for: Key.learningDomain, in: defaults, fallback: .technology)
        glassEnabled = Self.bool(for: Key.glassEnabled, in: defaults, fallback: true)
        translationEnabled = Self.bool(for: Key.translationEnabled, in: defaults, fallback: true)
        quietFlowEnabled = Self.bool(for: Key.quietFlowEnabled, in: defaults, fallback: true)
        magnifyingHoverEnabled = Self.bool(for: Key.magnifyingHoverEnabled, in: defaults, fallback: true)
        pointerLightEnabled = Self.bool(for: Key.pointerLightEnabled, in: defaults, fallback: true)
        vocabularyCardEnabled = Self.bool(for: Key.vocabularyCardEnabled, in: defaults, fallback: true)
        pronunciationEnabled = Self.bool(for: Key.pronunciationEnabled, in: defaults, fallback: true)
        exposureCountEnabled = Self.bool(for: Key.exposureCountEnabled, in: defaults, fallback: true)
        contextHintsEnabled = Self.bool(for: Key.contextHintsEnabled, in: defaults, fallback: true)
        chineseDefinitionEnabled = Self.bool(for: Key.chineseDefinitionEnabled, in: defaults, fallback: true)
        englishDefinitionEnabled = Self.bool(for: Key.englishDefinitionEnabled, in: defaults, fallback: true)
        examplesEnabled = Self.bool(for: Key.examplesEnabled, in: defaults, fallback: true)
        phrasesEnabled = Self.bool(for: Key.phrasesEnabled, in: defaults, fallback: true)
        hoverDelay = defaults.object(forKey: Key.hoverDelay) as? Double ?? 0.55
        ambientIntensity = defaults.object(forKey: Key.ambientIntensity) as? Double ?? 0.65
    }

    private static func bool(for key: String, in defaults: UserDefaults, fallback: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }

    private static func value<T: RawRepresentable>(
        for key: String,
        in defaults: UserDefaults,
        fallback: T
    ) -> T where T.RawValue == String {
        guard let rawValue = defaults.string(forKey: key), let value = T(rawValue: rawValue) else {
            return fallback
        }
        return value
    }
}

struct LinguaFlowSystemStatus {
    let isInstalled: Bool
    let isSelected: Bool

    @MainActor
    static func current() -> LinguaFlowSystemStatus {
        let installedURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Input Methods/LinguaFlow.app")
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let identifier: String? = TISGetInputSourceProperty(source, kTISPropertyInputSourceID).flatMap {
            Unmanaged<AnyObject>.fromOpaque($0).takeUnretainedValue() as? String
        }
        return LinguaFlowSystemStatus(
            isInstalled: FileManager.default.fileExists(atPath: installedURL.path),
            isSelected: identifier?.hasPrefix("com.tianxq.inputmethod.LinguaFlow") == true
        )
    }
}
