import Foundation

public protocol LexiconRepository: Sendable {
    func candidates(for input: String, targetLanguage: String, limit: Int) -> [Candidate]
    func prefixCandidates(for input: String, targetLanguage: String, limit: Int) -> [Candidate]
    func abbreviationCandidates(for initials: String, targetLanguage: String, limit: Int) -> [Candidate]
    func correctionCandidates(for input: String, targetLanguage: String, limit: Int) -> [Candidate]
    func continuationCandidates(
        after sourcePrefix: String,
        matchingPinyinPrefix input: String,
        targetLanguage: String,
        limit: Int
    ) -> [Candidate]
    func metadata(for sourceTexts: [String], targetLanguage: String) -> [String: Candidate]
}

public extension LexiconRepository {
    func candidates(for input: String, limit: Int) -> [Candidate] {
        candidates(for: input, targetLanguage: "en", limit: limit)
    }

    func prefixCandidates(for input: String, limit: Int) -> [Candidate] {
        prefixCandidates(for: input, targetLanguage: "en", limit: limit)
    }

    func abbreviationCandidates(for initials: String, limit: Int) -> [Candidate] {
        abbreviationCandidates(for: initials, targetLanguage: "en", limit: limit)
    }

    func correctionCandidates(for input: String, limit: Int) -> [Candidate] {
        correctionCandidates(for: input, targetLanguage: "en", limit: limit)
    }

    func continuationCandidates(
        after sourcePrefix: String,
        matchingPinyinPrefix input: String,
        limit: Int
    ) -> [Candidate] {
        continuationCandidates(
            after: sourcePrefix,
            matchingPinyinPrefix: input,
            targetLanguage: "en",
            limit: limit
        )
    }

    func metadata(for sourceTexts: [String]) -> [String: Candidate] {
        metadata(for: sourceTexts, targetLanguage: "en")
    }
}

public struct InMemoryLexicon: LexiconRepository {
    private let candidatesByInput: [String: [Candidate]]

    public init(candidates: [Candidate]) {
        candidatesByInput = Dictionary(grouping: candidates) {
            PinyinNormalizer.normalize($0.pinyin)
        }
    }

    public func candidates(
        for input: String,
        targetLanguage: String,
        limit: Int
    ) -> [Candidate] {
        guard limit > 0 else { return [] }
        return candidatesByInput[PinyinNormalizer.normalize(input), default: []]
            .filter { $0.targetLanguage == targetLanguage }
            .prefix(limit)
            .map { $0 }
    }

    public func prefixCandidates(
        for input: String,
        targetLanguage: String,
        limit: Int
    ) -> [Candidate] {
        let normalized = PinyinNormalizer.normalize(input)
        guard !normalized.isEmpty, limit > 0 else { return [] }
        return candidatesByInput
            .filter { $0.key.hasPrefix(normalized) }
            .flatMap(\.value)
            .filter { $0.targetLanguage == targetLanguage }
            .sorted { $0.frequency > $1.frequency }
            .prefix(limit)
            .map { $0 }
    }

    public func abbreviationCandidates(
        for initials: String,
        targetLanguage: String,
        limit: Int
    ) -> [Candidate] {
        let normalized = PinyinNormalizer.normalize(initials)
        guard !normalized.isEmpty, limit > 0 else { return [] }
        return candidatesByInput.values
            .flatMap { $0 }
            .filter {
                $0.targetLanguage == targetLanguage
                    && PinyinNormalizer.initials(for: $0.pinyin) == normalized
            }
            .sorted { $0.frequency > $1.frequency }
            .prefix(limit)
            .map { $0 }
    }

    public func correctionCandidates(
        for input: String,
        targetLanguage: String,
        limit: Int
    ) -> [Candidate] {
        let normalized = PinyinNormalizer.normalize(input)
        guard normalized.count >= 4, limit > 0 else { return [] }
        return candidatesByInput.values
            .flatMap { $0 }
            .filter {
                $0.targetLanguage == targetLanguage
                    && PinyinNormalizer.isSingleEditCorrection(
                        input: normalized,
                        candidate: PinyinNormalizer.normalize($0.pinyin)
                    )
            }
            .sorted { $0.frequency > $1.frequency }
            .prefix(limit)
            .map { $0 }
    }

    public func continuationCandidates(
        after sourcePrefix: String,
        matchingPinyinPrefix input: String,
        targetLanguage: String,
        limit: Int
    ) -> [Candidate] {
        let normalized = PinyinNormalizer.normalize(input)
        guard sourcePrefix.count >= 2, normalized.count >= 4, limit > 0 else { return [] }
        return candidatesByInput.values
            .flatMap { $0 }
            .filter {
                $0.targetLanguage == targetLanguage
                    && $0.sourceText.count > sourcePrefix.count
                    && $0.sourceText.hasPrefix(sourcePrefix)
                    && PinyinNormalizer.normalize($0.pinyin).hasPrefix(normalized)
                    && PinyinNormalizer.normalize($0.pinyin).count > normalized.count
            }
            .sorted {
                if $0.frequency != $1.frequency { return $0.frequency > $1.frequency }
                return $0.sourceText.count < $1.sourceText.count
            }
            .prefix(limit)
            .map { $0 }
    }

    public func metadata(
        for sourceTexts: [String],
        targetLanguage: String
    ) -> [String: Candidate] {
        let requested = Set(sourceTexts)
        var result: [String: Candidate] = [:]
        for candidate in candidatesByInput.values.flatMap({ $0 }) where
            requested.contains(candidate.sourceText)
                && candidate.targetLanguage == targetLanguage
                && !candidate.translation.isEmpty
        {
            if result[candidate.sourceText] == nil {
                result[candidate.sourceText] = candidate
            }
        }
        return result
    }
}

enum EnglishWordCatalog {
    private struct Entry {
        let word: String
        let meaning: String
    }

    static func candidates(for input: String, limit: Int) -> [Candidate] {
        let prefix = PinyinNormalizer.normalize(input)
        guard prefix.count >= 3, limit > 0 else { return [] }

        return entries.enumerated().compactMap { index, entry -> Candidate? in
            let isExact = entry.word == prefix
            let isPrefixCompletion = entry.word.hasPrefix(prefix)
            let isSingleEdit = PinyinNormalizer.isSingleEditCorrection(
                input: prefix,
                candidate: entry.word
            )
            guard isExact || isPrefixCompletion || isSingleEdit else { return nil }
            return Candidate(
                id: "english:\(entry.word)",
                pinyin: entry.word,
                sourceText: entry.word,
                translation: entry.meaning,
                frequency: (entries.count - index) * 10_000,
                targetLanguage: "en",
                partOfSpeech: "english",
                domain: "english",
                style: "neutral"
            )
        }
        .prefix(limit)
        .map { $0 }
    }

    // A deliberately small, reviewed starter list. It keeps the input method
    // lightweight and can later be replaced by a licensed frequency corpus.
    private static let entries: [Entry] = [
        Entry(word: "the", meaning: "这个；那个"),
        Entry(word: "this", meaning: "这个"),
        Entry(word: "that", meaning: "那个"),
        Entry(word: "there", meaning: "那里"),
        Entry(word: "their", meaning: "他们的"),
        Entry(word: "they", meaning: "他们"),
        Entry(word: "thank", meaning: "感谢"),
        Entry(word: "thanks", meaning: "谢谢"),
        Entry(word: "you", meaning: "你；你们"),
        Entry(word: "your", meaning: "你的；你们的"),
        Entry(word: "yes", meaning: "是；好的"),
        Entry(word: "hello", meaning: "你好"),
        Entry(word: "help", meaning: "帮助"),
        Entry(word: "here", meaning: "这里"),
        Entry(word: "how", meaning: "怎样；如何"),
        Entry(word: "have", meaning: "有；拥有"),
        Entry(word: "good", meaning: "好的"),
        Entry(word: "great", meaning: "很棒的"),
        Entry(word: "please", meaning: "请"),
        Entry(word: "people", meaning: "人们"),
        Entry(word: "professor", meaning: "教授"),
        Entry(word: "professional", meaning: "专业的；专业人士"),
        Entry(word: "project", meaning: "项目"),
        Entry(word: "problem", meaning: "问题"),
        Entry(word: "program", meaning: "程序；计划"),
        Entry(word: "product", meaning: "产品"),
        Entry(word: "provide", meaning: "提供"),
        Entry(word: "because", meaning: "因为"),
        Entry(word: "before", meaning: "以前；之前"),
        Entry(word: "between", meaning: "在……之间"),
        Entry(word: "about", meaning: "关于；大约"),
        Entry(word: "after", meaning: "以后；之后"),
        Entry(word: "again", meaning: "再次"),
        Entry(word: "also", meaning: "也；而且"),
        Entry(word: "always", meaning: "总是"),
        Entry(word: "another", meaning: "另一个"),
        Entry(word: "apple", meaning: "苹果"),
        Entry(word: "application", meaning: "应用；申请"),
        Entry(word: "can", meaning: "可以；能够"),
        Entry(word: "could", meaning: "可以；可能"),
        Entry(word: "would", meaning: "将会；愿意"),
        Entry(word: "should", meaning: "应该"),
        Entry(word: "will", meaning: "将会"),
        Entry(word: "want", meaning: "想要"),
        Entry(word: "what", meaning: "什么"),
        Entry(word: "when", meaning: "什么时候"),
        Entry(word: "where", meaning: "哪里"),
        Entry(word: "which", meaning: "哪一个"),
        Entry(word: "work", meaning: "工作"),
        Entry(word: "world", meaning: "世界"),
        Entry(word: "today", meaning: "今天"),
        Entry(word: "tomorrow", meaning: "明天"),
        Entry(word: "time", meaning: "时间"),
        Entry(word: "thing", meaning: "事情；东西"),
        Entry(word: "think", meaning: "思考；认为"),
        Entry(word: "know", meaning: "知道；了解"),
        Entry(word: "look", meaning: "看"),
        Entry(word: "like", meaning: "喜欢；像"),
        Entry(word: "learn", meaning: "学习"),
        Entry(word: "language", meaning: "语言"),
        Entry(word: "meeting", meaning: "会议"),
        Entry(word: "message", meaning: "消息"),
        Entry(word: "memory", meaning: "记忆"),
        Entry(word: "make", meaning: "制作；使得"),
        Entry(word: "maybe", meaning: "也许"),
        Entry(word: "name", meaning: "名字"),
        Entry(word: "need", meaning: "需要"),
        Entry(word: "never", meaning: "从不"),
        Entry(word: "new", meaning: "新的"),
        Entry(word: "next", meaning: "下一个"),
        Entry(word: "nice", meaning: "美好的；友善的"),
        Entry(word: "night", meaning: "夜晚"),
        Entry(word: "number", meaning: "数字；号码"),
        Entry(word: "only", meaning: "仅仅；只有"),
        Entry(word: "other", meaning: "其他的"),
        Entry(word: "right", meaning: "正确的；右边"),
        Entry(word: "really", meaning: "真正地；确实"),
        Entry(word: "schedule", meaning: "日程；安排"),
        Entry(word: "school", meaning: "学校"),
        Entry(word: "see", meaning: "看见"),
        Entry(word: "send", meaning: "发送"),
        Entry(word: "something", meaning: "某事；某物"),
        Entry(word: "sorry", meaning: "抱歉"),
        Entry(word: "study", meaning: "学习；研究"),
        Entry(word: "take", meaning: "拿；带走"),
        Entry(word: "talk", meaning: "交谈"),
        Entry(word: "text", meaning: "文本；短信"),
        Entry(word: "translate", meaning: "翻译"),
        Entry(word: "translation", meaning: "翻译；译文"),
        Entry(word: "use", meaning: "使用"),
        Entry(word: "very", meaning: "非常"),
        Entry(word: "welcome", meaning: "欢迎"),
        Entry(word: "well", meaning: "好；很好地"),
        Entry(word: "with", meaning: "和；带有"),
        Entry(word: "without", meaning: "没有；不带"),
    ]
}
