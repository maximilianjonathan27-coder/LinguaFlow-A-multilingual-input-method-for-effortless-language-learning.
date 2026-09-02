import Darwin
import Foundation

public enum SupportedLanguage: String, CaseIterable, Codable, Sendable, Identifiable {
    case chineseSimplified = "zh-Hans"
    case english = "en"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .chineseSimplified: "简体中文"
        case .english: "English"
        }
    }
}

/// The only two language directions currently supported by LinguaFlow.
/// Keeping this as data avoids separate "English mode" control paths.
public enum LanguageDirection: String, CaseIterable, Codable, Sendable, Identifiable {
    case chineseToEnglish = "zh-Hans-en"
    case englishToChinese = "en-zh-Hans"

    public var id: String { rawValue }

    public var source: SupportedLanguage {
        self == .chineseToEnglish ? .chineseSimplified : .english
    }

    public var target: SupportedLanguage {
        self == .chineseToEnglish ? .english : .chineseSimplified
    }

    public var title: String { "\(source.displayName) → \(target.displayName)" }
}

/// File-backed instead of `UserDefaults.standard`: the settings app and input-method
/// extension are different processes/bundles, while both can safely reach this path.
public final class LanguageDirectionStore: @unchecked Sendable {
    public static let shared = LanguageDirectionStore()

    private let fileURL: URL
    private let lock = NSLock()

    public init(fileURL: URL = LanguageDirectionStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    public static var defaultFileURL: URL {
        LinguaFlowStorageDirectory.url.appendingPathComponent("languageDirection.v1.json")
    }

    public func current() -> LanguageDirection {
        lock.lock(); defer { lock.unlock() }
        return (try? readLocked()) ?? .chineseToEnglish
    }

    public func set(_ direction: LanguageDirection) {
        lock.lock(); defer { lock.unlock() }
        try? withFileLock { try JSONEncoder().encode(direction).write(to: fileURL, options: .atomic) }
    }

    private func readLocked() throws -> LanguageDirection {
        try withFileLock {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return .chineseToEnglish }
            return try JSONDecoder().decode(LanguageDirection.self, from: Data(contentsOf: fileURL))
        }
    }

    private func withFileLock<T>(_ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: LinguaFlowStorageDirectory.url, withIntermediateDirectories: true)
        let lockURL = fileURL.deletingPathExtension().appendingPathExtension("lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw CocoaError(.fileLocking) }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw CocoaError(.fileLocking) }
        defer { flock(descriptor, LOCK_UN) }
        return try body()
    }
}

public enum LinguaFlowStorageDirectory {
    public static var url: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return support.appendingPathComponent("LinguaFlow", isDirectory: true)
    }
}
