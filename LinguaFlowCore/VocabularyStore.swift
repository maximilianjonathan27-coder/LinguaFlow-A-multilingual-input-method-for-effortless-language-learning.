import Darwin
import Foundation

public struct VocabularyEntry: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public var sourceText: String
    public var translatedText: String
    public var sourceLanguage: SupportedLanguage
    public var targetLanguage: SupportedLanguage
    public var firstViewedAt: Date
    public var lastViewedAt: Date
    public var viewCount: Int
    public var definition: String?

    public init(candidate: Candidate, definition: String? = nil, now: Date = .now) {
        sourceText = candidate.sourceText
        translatedText = candidate.translation
        sourceLanguage = candidate.sourceLanguage
        targetLanguage = candidate.targetSupportedLanguage
        self.definition = definition
        firstViewedAt = now
        lastViewedAt = now
        viewCount = 1
        id = Self.identity(candidate: candidate)
    }

    public static func identity(candidate: Candidate) -> String {
        let normalizedTarget: String
        if candidate.targetSupportedLanguage == .english {
            normalizedTarget = candidate.translation.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            normalizedTarget = candidate.translation.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "\(candidate.targetSupportedLanguage.rawValue)|\(candidate.sourceLanguage.rawValue)|\(candidate.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())|\(normalizedTarget)"
    }
}

public enum VocabularySort: String, CaseIterable, Codable, Sendable {
    case recentlyViewed
    case mostViewed
    case alphabetical
}

public final class VocabularyStore: @unchecked Sendable {
    public static let shared = VocabularyStore()
    public static var defaultFileURL: URL { LinguaFlowStorageDirectory.url.appendingPathComponent("vocabulary.v1.json") }

    private let fileURL: URL
    private let lock = NSLock()

    public init(fileURL: URL = VocabularyStore.defaultFileURL) { self.fileURL = fileURL }

    public func entries() -> [VocabularyEntry] {
        lock.lock(); defer { lock.unlock() }
        return (try? withFileLock { try readUnlocked() }) ?? []
    }

    @discardableResult
    public func recordView(candidate: Candidate, definition: String? = nil, now: Date = .now) -> VocabularyEntry? {
        lock.lock(); defer { lock.unlock() }
        return try? withFileLock {
            var current = try readUnlocked()
            let identity = VocabularyEntry.identity(candidate: candidate)
            if let index = current.firstIndex(where: { $0.id == identity }) {
                current[index].lastViewedAt = now
                current[index].viewCount += 1
                if current[index].definition == nil { current[index].definition = definition }
                try writeUnlocked(current)
                return current[index]
            }
            let entry = VocabularyEntry(candidate: candidate, definition: definition, now: now)
            current.append(entry)
            try writeUnlocked(current)
            return entry
        }
    }

    public func remove(id: String) {
        lock.lock(); defer { lock.unlock() }
        try? withFileLock {
            var current = try readUnlocked()
            current.removeAll { $0.id == id }
            try writeUnlocked(current)
        }
    }

    public func clear() {
        lock.lock(); defer { lock.unlock() }
        try? withFileLock { try writeUnlocked([]) }
    }

    private func readUnlocked() throws -> [VocabularyEntry] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return (try? JSONDecoder().decode([VocabularyEntry].self, from: Data(contentsOf: fileURL))) ?? []
    }

    private func writeUnlocked(_ entries: [VocabularyEntry]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(entries).write(to: fileURL, options: .atomic)
    }

    private func withFileLock<T>(_ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let lockURL = fileURL.deletingPathExtension().appendingPathExtension("lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw CocoaError(.fileLocking) }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw CocoaError(.fileLocking) }
        defer { flock(descriptor, LOCK_UN) }
        return try body()
    }
}

public enum VocabularyHistoryService {
    /// Deliberately asynchronous: card presentation and key handling never wait for disk I/O.
    public static func recordOpenedCard(for candidate: Candidate, definition: String? = nil) {
        DispatchQueue.global(qos: .utility).async {
            _ = VocabularyStore.shared.recordView(candidate: candidate, definition: definition)
        }
    }
}
