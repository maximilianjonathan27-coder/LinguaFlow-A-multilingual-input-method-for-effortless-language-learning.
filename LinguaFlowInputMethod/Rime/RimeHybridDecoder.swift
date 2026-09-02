import Foundation
import LinguaFlowCore
import OSLog

final class RimeHybridDecoder: CandidateDecoding, @unchecked Sendable {
    private struct RawCandidate {
        let text: String
        let comment: String
        let pinyinHint: String?
    }

    private static let logger = Logger(
        subsystem: "com.tianxq.inputmethod.LinguaFlow",
        category: "Rime"
    )
    private let fallback: PinyinDecoder
    private let lexicon: any LexiconRepository
    private let targetLanguage: String
    private let cacheLock = NSLock()
    private var cachedInput = ""
    private var cachedLimit = 0
    private var cachedCandidates: [Candidate] = []

    init?(
        sharedDataURL: URL,
        userDataURL: URL,
        lexicon: any LexiconRepository,
        targetLanguage: String = "en"
    ) {
        fallback = PinyinDecoder(lexicon: lexicon, targetLanguage: targetLanguage)
        self.lexicon = lexicon
        self.targetLanguage = targetLanguage
        do {
            try FileManager.default.createDirectory(
                at: userDataURL,
                withIntermediateDirectories: true
            )
        } catch {
            return nil
        }

        let initialized = sharedDataURL.path.withCString { sharedDataPath in
            userDataURL.path.withCString { userDataPath in
                "linguaflow_pinyin".withCString { schemaID in
                    LFRimeInitialize(sharedDataPath, userDataPath, schemaID)
                }
            }
        }
        guard initialized else {
            Self.logger.error(
                "librime initialization failed: \(String(cString: LFRimeLastError()), privacy: .public)"
            )
            return nil
        }
        Self.logger.notice("librime initialized with schema linguaflow_pinyin")
    }

    func candidates(for input: String, limit: Int) -> [Candidate] {
        let normalized = PinyinNormalizer.normalize(input)
        guard !normalized.isEmpty, limit > 0 else { return [] }
        let cacheKey = input.lowercased()
        cacheLock.lock()
        if cachedInput == cacheKey, cachedLimit == limit {
            let cached = cachedCandidates
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let fallbackCandidates = fallback.candidates(
            for: input,
            limit: max(100, limit * 2)
        )
        let query = rimeQuery(for: input)
        let primary = rawCandidates(for: query, limit: limit)

        // Preserve LinguaFlow's deliberate English fallback behavior for real
        // English words such as `hello`. Exact/ordinary Chinese Pinyin remains
        // first in the fallback decoder, so `he` and `xian` stay Chinese.
        if fallbackCandidates.first?.domain == "english" {
            return cache(
                Array(fallbackCandidates.prefix(limit)),
                input: cacheKey,
                limit: limit
            )
        }

        guard !primary.isEmpty else {
            return cache(
                Array(fallbackCandidates.prefix(limit)),
                input: cacheKey,
                limit: limit
            )
        }

        // librime itself performs syllable segmentation and already includes
        // alternatives such as 西安 in the normal `xian` result. Running our own
        // alternate queries here duplicates work on every keystroke and can also
        // disturb librime's ranking contract.
        let rawResults = primary

        let fallbackMetadataByText = Dictionary(
            fallbackCandidates.map { ($0.sourceText, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let metadataByText = lexicon.metadata(
            for: translationLookupTexts(in: rawResults.map(\.text)),
            targetLanguage: targetLanguage
        )
        let inputSegments = PinyinNormalizer.segments(for: input)
        var results: [Candidate] = []
        var seenText: Set<String> = []

        for (index, item) in rawResults.enumerated() {
            let text = item.text
            guard !text.isEmpty, seenText.insert(text).inserted else { continue }
            let fallbackMetadata = fallbackMetadataByText[text]
            let metadata = if let dictionaryMetadata = metadataByText[text],
                              !dictionaryMetadata.translation.isEmpty {
                dictionaryMetadata
            } else {
                fallbackMetadata
            }
            let translation = metadata?.translation.isEmpty == false
                ? metadata?.translation ?? ""
                : compositionalTranslation(for: text, metadataByText: metadataByText) ?? ""
            let isApproximate = translation.hasPrefix("≈ ")
            results.append(Candidate(
                // Learning is tied to the composition as well as the text. This
                // keeps choosing 吧 for `ba` from incorrectly promoting it for
                // `bei`, while remaining stable when Rime changes list position.
                id: "rime:\(normalized):\(text)",
                pinyin: candidatePinyin(
                    comment: item.comment,
                    sourceText: text,
                    input: input,
                    inputSegments: inputSegments,
                    pinyinHint: item.pinyinHint
                ),
                sourceText: text,
                translation: translation,
                frequency: 2_000_000_000 - index,
                targetLanguage: metadata?.targetLanguage ?? targetLanguage,
                partOfSpeech: isApproximate ? "generated-gloss" : metadata?.partOfSpeech,
                domain: metadata?.domain ?? "general",
                style: isApproximate ? "approximate" : metadata?.style ?? "neutral"
            ))
        }

        for candidate in fallbackCandidates where seenText.insert(candidate.sourceText).inserted {
            results.append(candidate)
        }
        return cache(Array(results.prefix(limit)), input: cacheKey, limit: limit)
    }

    private func translationLookupTexts(in sourceTexts: [String]) -> [String] {
        var lookups: Set<String> = []
        for sourceText in sourceTexts {
            let characters = Array(sourceText)
            guard !characters.isEmpty, characters.count <= 12 else { continue }
            for start in characters.indices {
                let maximumEnd = min(characters.count, start + 6)
                for end in (start + 1)...maximumEnd {
                    lookups.insert(String(characters[start..<end]))
                }
            }
        }
        return Array(lookups)
    }

    private func compositionalTranslation(
        for sourceText: String,
        metadataByText: [String: Candidate]
    ) -> String? {
        struct GlossPath {
            let glosses: [String]
            let score: Int64
        }

        let characters = Array(sourceText)
        guard characters.count > 1, characters.count <= 12 else { return nil }
        var paths = Array<GlossPath?>(repeating: nil, count: characters.count + 1)
        paths[0] = GlossPath(glosses: [], score: 0)

        for start in characters.indices {
            guard let path = paths[start] else { continue }
            let maximumEnd = min(characters.count, start + 6)
            for end in (start + 1)...maximumEnd {
                let text = String(characters[start..<end])
                guard let metadata = metadataByText[text], !metadata.translation.isEmpty else {
                    continue
                }
                let length = end - start
                // Strongly prefer known multi-character words and grammar
                // units such as “一下” over character glosses like “one · down”.
                let lengthScore = Int64(length * length * 100_000)
                let frequencyScore = Int64(log(Double(max(1, metadata.frequency))) * 1_000)
                let candidate = GlossPath(
                    glosses: path.glosses + [compactGloss(metadata.translation)],
                    score: path.score + lengthScore + frequencyScore
                )
                if paths[end].map({ $0.score < candidate.score }) ?? true {
                    paths[end] = candidate
                }
            }
        }

        guard let result = paths[characters.count], result.glosses.count > 1 else { return nil }
        return "≈ " + result.glosses.joined(separator: " · ")
    }

    private func compactGloss(_ translation: String) -> String {
        var gloss = translation
        if gloss.hasPrefix("≈ ") { gloss.removeFirst(2) }
        gloss = gloss.split(separator: ";", maxSplits: 1).first
            .map(String.init) ?? gloss
        while gloss.hasPrefix("("), let closing = gloss.firstIndex(of: ")") {
            gloss = String(gloss[gloss.index(after: closing)...])
                .trimmingCharacters(in: .whitespaces)
        }
        return gloss.isEmpty ? translation : gloss
    }

    private func cache(_ candidates: [Candidate], input: String, limit: Int) -> [Candidate] {
        cacheLock.lock()
        cachedInput = input
        cachedLimit = limit
        cachedCandidates = candidates
        cacheLock.unlock()
        return candidates
    }

    private func rimeQuery(for input: String) -> String {
        let explicit = input.lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0 == "'" })
            .map(String.init)
        if explicit.count > 1 {
            return explicit.joined(separator: "'")
        }
        return PinyinNormalizer.normalize(input)
    }

    private func rawCandidates(for query: String, limit: Int) -> [RawCandidate] {
        var itemPointer: UnsafeMutablePointer<LFRimeCandidateItem>?
        let count = query.withCString { inputPointer in
            LFRimeGetCandidates(inputPointer, Int32(limit), &itemPointer)
        }
        guard count > 0, let itemPointer else { return [] }
        defer { LFRimeFreeCandidates(itemPointer, count) }

        let hint = query.contains("'")
            ? query.replacingOccurrences(of: "'", with: " ")
            : nil
        return (0..<Int(count)).compactMap { index in
            let item = itemPointer[index]
            guard let textPointer = item.text else { return nil }
            return RawCandidate(
                text: String(cString: textPointer),
                comment: String(cString: item.comment),
                pinyinHint: hint
            )
        }
    }

    private func candidatePinyin(
        comment: String,
        sourceText: String,
        input: String,
        inputSegments: [String],
        pinyinHint: String?
    ) -> String {
        if let pinyinHint { return pinyinHint }
        let commentIsPinyin = !comment.isEmpty && comment.allSatisfy {
            $0.isASCII && ($0.isLetter || $0.isWhitespace || $0 == "'")
        }
        if commentIsPinyin {
            return comment
        }
        if sourceText.count < inputSegments.count {
            return inputSegments.prefix(sourceText.count).joined(separator: " ")
        }
        return PinyinNormalizer.formattedComposition(input)
    }
}
