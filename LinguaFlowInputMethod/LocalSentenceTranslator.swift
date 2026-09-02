import Foundation
import LinguaFlowCore

#if canImport(Translation)
@preconcurrency import Translation
#endif

struct CandidateTranslationRequest: Sendable {
    let candidateID: String
    let sourceText: String
}

@MainActor
final class LocalSentenceTranslator {
    private static let maximumCacheEntries = 1_000
    private static let debounceNanoseconds: UInt64 = 150_000_000

    private var cachedTranslations: [String: String]
    private var insertionOrder: [String]
    private var pendingCacheSave: Task<Void, Never>?
    private let cacheURL: URL?

    init() {
        cacheURL = Self.makeCacheURL()
        let stored = cacheURL.flatMap(Self.loadCache(from:)) ?? TranslationCacheFile()
        cachedTranslations = stored.translations
        insertionOrder = stored.insertionOrder.filter { stored.translations[$0] != nil }
    }

    deinit {
        pendingCacheSave?.cancel()
    }

    func requests(from candidates: [Candidate], limit: Int = 3) -> [CandidateTranslationRequest] {
        var seenSourceTexts = Set<String>()
        return candidates.compactMap { candidate -> CandidateTranslationRequest? in
            guard Self.shouldTranslate(candidate),
                  seenSourceTexts.insert(candidate.sourceText).inserted
            else { return nil }
            return CandidateTranslationRequest(
                candidateID: candidate.id,
                sourceText: candidate.sourceText
            )
        }
        .prefix(limit)
        .map { $0 }
    }

    func cachedResults(
        for requests: [CandidateTranslationRequest]
    ) -> [String: String] {
        Dictionary(uniqueKeysWithValues: requests.compactMap { request in
            cachedTranslations[request.sourceText].map { (request.candidateID, $0) }
        })
    }

    func translate(
        _ requests: [CandidateTranslationRequest]
    ) async -> [String: String] {
        guard !requests.isEmpty else { return [:] }

        var results = cachedResults(for: requests)
        let uncached = requests.filter { cachedTranslations[$0.sourceText] == nil }
        guard !uncached.isEmpty else { return results }

        do {
            try await Task.sleep(nanoseconds: Self.debounceNanoseconds)
            try Task.checkCancellation()

#if canImport(Translation)
            guard #available(macOS 26.0, *) else { return results }
            let responses = try await translateInstalled(uncached)
            try Task.checkCancellation()

            for response in responses {
                guard let candidateID = response.clientIdentifier else { continue }
                let translation = response.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !translation.isEmpty else { continue }
                results[candidateID] = translation
                store(translation, for: response.sourceText)
            }
#endif
        } catch is CancellationError {
            return results
        } catch {
            // Missing language packs or a transient framework failure must never
            // interfere with Chinese candidate generation.
            return results
        }
        return results
    }

#if canImport(Translation)
    @available(macOS 26.0, *)
    private func translateInstalled(
        _ requests: [CandidateTranslationRequest]
    ) async throws -> [TranslationSession.Response] {
        let session = TranslationSession(
            installedSource: Locale.Language(identifier: "zh-Hans"),
            target: Locale.Language(identifier: "en")
        )
        var responses: [TranslationSession.Response] = []
        for request in requests {
            try Task.checkCancellation()
            let response = try await session.translate(request.sourceText)
            responses.append(
                TranslationSession.Response(
                    sourceLanguage: response.sourceLanguage,
                    targetLanguage: response.targetLanguage,
                    sourceText: response.sourceText,
                    targetText: response.targetText,
                    clientIdentifier: request.candidateID
                )
            )
        }
        return responses
    }
#endif

    private static func shouldTranslate(_ candidate: Candidate) -> Bool {
        let hanCount = candidate.sourceText.unicodeScalars.reduce(into: 0) { count, scalar in
            if (0x3400...0x9FFF).contains(scalar.value) { count += 1 }
        }
        guard hanCount >= 3 else { return false }

        let existingLooksGenerated = candidate.translation.isEmpty
            || candidate.translation.hasPrefix("≈ ")
            || candidate.style == "approximate"
            || candidate.partOfSpeech == "generated-gloss"

        // Keep short, reviewed dictionary translations. Longer strings are
        // sentence-like enough for contextual translation to be more useful.
        return existingLooksGenerated || hanCount >= 6
    }

    private func store(_ translation: String, for sourceText: String) {
        if cachedTranslations[sourceText] == nil {
            insertionOrder.append(sourceText)
        }
        cachedTranslations[sourceText] = translation

        while insertionOrder.count > Self.maximumCacheEntries {
            let removed = insertionOrder.removeFirst()
            cachedTranslations.removeValue(forKey: removed)
        }
        scheduleCacheSave()
    }

    private func scheduleCacheSave() {
        pendingCacheSave?.cancel()
        let cache = TranslationCacheFile(
            translations: cachedTranslations,
            insertionOrder: insertionOrder
        )
        let url = cacheURL
        pendingCacheSave = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let url else { return }
            guard let data = try? JSONEncoder().encode(cache) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func makeCacheURL() -> URL? {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return nil }
        let directory = applicationSupport.appendingPathComponent(
            "LinguaFlow",
            isDirectory: true
        )
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory.appendingPathComponent("translation-cache.json")
    }

    nonisolated private static func loadCache(from url: URL) -> TranslationCacheFile? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(TranslationCacheFile.self, from: data)
    }
}

private struct TranslationCacheFile: Codable, Sendable {
    var translations: [String: String] = [:]
    var insertionOrder: [String] = []
}
