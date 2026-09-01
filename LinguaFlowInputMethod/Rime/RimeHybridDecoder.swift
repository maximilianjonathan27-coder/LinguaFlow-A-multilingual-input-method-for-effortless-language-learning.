import Foundation
import LinguaFlowCore
import OSLog

final class RimeHybridDecoder: CandidateDecoding, @unchecked Sendable {
    private static let logger = Logger(
        subsystem: "com.tianxq.inputmethod.LinguaFlow",
        category: "Rime"
    )
    private let fallback: PinyinDecoder
    private let targetLanguage: String

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

        let fallbackCandidates = fallback.candidates(
            for: input,
            limit: max(100, limit * 2)
        )
        // Preserve LinguaFlow's deliberate English fallback behavior. Rime can
        // form obscure Chinese for almost every Latin sequence, including a
        // fully typed English word such as "hello".
        if fallbackCandidates.first?.domain == "english" {
            return Array(fallbackCandidates.prefix(limit))
        }

        var itemPointer: UnsafeMutablePointer<LFRimeCandidateItem>?
        let count = normalized.withCString { inputPointer in
            LFRimeGetCandidates(inputPointer, Int32(limit), &itemPointer)
        }
        guard count > 0, let itemPointer else {
            return Array(fallbackCandidates.prefix(limit))
        }
        defer { LFRimeFreeCandidates(itemPointer, count) }

        let metadataByText = Dictionary(
            fallbackCandidates.map { ($0.sourceText, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let inputSegments = PinyinNormalizer.segments(for: input)
        var results: [Candidate] = []
        var seenText: Set<String> = []

        for index in 0..<Int(count) {
            let item = itemPointer[index]
            guard let textPointer = item.text else { continue }
            let text = String(cString: textPointer)
            guard !text.isEmpty, seenText.insert(text).inserted else { continue }
            let comment = String(cString: item.comment)
            let metadata = metadataByText[text]
            results.append(Candidate(
                id: "rime:\(normalized):\(index):\(text)",
                pinyin: candidatePinyin(
                    comment: comment,
                    sourceText: text,
                    input: input,
                    inputSegments: inputSegments
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
        return Array(results.prefix(limit))
    }

    private func candidatePinyin(
        comment: String,
        sourceText: String,
        input: String,
        inputSegments: [String]
    ) -> String {
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
