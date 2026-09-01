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
        let queries = rimeQueries(for: input)
        let primary = rawCandidates(for: queries[0], limit: max(20, limit * 2))
        let alternatives = queries.dropFirst().flatMap {
            rawCandidates(for: $0, limit: max(8, limit))
        }

        // Preserve LinguaFlow's deliberate English fallback behavior for real
        // English words such as `hello`. Do not apply it to ambiguous Pinyin:
        // `xian` is also `xi an`, and that query yields the ordinary word 西安.
        if fallbackCandidates.first?.domain == "english",
           !alternatives.contains(where: { $0.text.count > 1 }) {
            return cache(
                Array(fallbackCandidates.prefix(limit)),
                input: cacheKey,
                limit: limit
            )
        }

        guard !primary.isEmpty || !alternatives.isEmpty else {
            return cache(
                Array(fallbackCandidates.prefix(limit)),
                input: cacheKey,
                limit: limit
            )
        }

        // The untouched primary sequence is librime's default ranking. Alternate
        // segmentations may fill missing results, but must never be injected into
        // or placed ahead of librime's own sequence. For example, librime already
        // includes 西安 in the normal `xian` list at its dictionary-ranked position.
        var rawResults = primary
        rawResults.append(contentsOf: alternatives)

        let metadataByText = Dictionary(
            fallbackCandidates.map { ($0.sourceText, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let inputSegments = PinyinNormalizer.segments(for: input)
        var results: [Candidate] = []
        var seenText: Set<String> = []

        for (index, item) in rawResults.enumerated() {
            let text = item.text
            guard !text.isEmpty, seenText.insert(text).inserted else { continue }
            let metadata = metadataByText[text]
            results.append(Candidate(
                // Candidate identity must not depend on the current spelling or
                // list position. A stable ID lets SelectionStore learn that the
                // user chose the same word across queries and Rime rerankings.
                id: "rime:\(text)",
                pinyin: candidatePinyin(
                    comment: item.comment,
                    sourceText: text,
                    input: input,
                    inputSegments: inputSegments,
                    pinyinHint: item.pinyinHint
                ),
                sourceText: text,
                translation: metadata?.translation ?? "",
                frequency: 2_000_000_000 - index,
                targetLanguage: metadata?.targetLanguage ?? targetLanguage,
                partOfSpeech: metadata?.partOfSpeech,
                domain: metadata?.domain ?? "general",
                style: metadata?.style ?? "neutral"
            ))
        }

        for candidate in fallbackCandidates where seenText.insert(candidate.sourceText).inserted {
            results.append(candidate)
        }
        return cache(Array(results.prefix(limit)), input: cacheKey, limit: limit)
    }

    private func cache(_ candidates: [Candidate], input: String, limit: Int) -> [Candidate] {
        cacheLock.lock()
        cachedInput = input
        cachedLimit = limit
        cachedCandidates = candidates
        cacheLock.unlock()
        return candidates
    }

    private func rimeQueries(for input: String) -> [String] {
        let explicit = input.lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0 == "'" })
            .map(String.init)
        if explicit.count > 1 {
            return [explicit.joined(separator: "'")]
        }

        let normalized = PinyinNormalizer.normalize(input)
        var queries = [normalized]
        for segmentation in PinyinNormalizer.segmentations(for: input, limit: 3)
            where segmentation.count > 1 {
            let query = segmentation.joined(separator: "'")
            if !queries.contains(query) { queries.append(query) }
        }
        return queries
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
