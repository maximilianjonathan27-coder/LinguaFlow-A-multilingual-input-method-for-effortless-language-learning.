import Darwin
import Foundation
import Observation

@MainActor
@Observable
public final class ExposureStore {
    public static let legacyStorageKey = "linguaflow.exposureCounts.v1"
    public static let migrationMarkerKey = "linguaflow.exposureCounts.fileMigration.v1"

    public private(set) var counts: [String: Int] = [:]
    public private(set) var lastErrorDescription: String?

    private let persistence: ExposurePersistence

    public init(
        fileURL: URL = ExposureStore.defaultFileURL,
        legacyDefaults: UserDefaults? = nil
    ) {
        persistence = ExposurePersistence(fileURL: fileURL)
        migrateLegacyCountsIfNeeded(from: legacyDefaults)
        refresh()
    }

    public static var defaultFileURL: URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)

        return applicationSupport
            .appendingPathComponent("LinguaFlow", isDirectory: true)
            .appendingPathComponent("exposureCounts.v1.json", isDirectory: false)
    }

    public var hasExposures: Bool {
        counts.values.contains { $0 > 0 }
    }

    public func count(for candidate: Candidate) -> Int {
        counts[candidate.id, default: 0]
    }

    public func refresh() {
        do {
            counts = try persistence.read()
            lastErrorDescription = nil
        } catch {
            counts = [:]
            lastErrorDescription = error.localizedDescription
        }
    }

    @discardableResult
    public func increment(_ candidate: Candidate) -> Bool {
        do {
            counts = try persistence.update { latest in
                latest[candidate.id, default: 0] += 1
            }
            lastErrorDescription = nil
            return true
        } catch {
            lastErrorDescription = error.localizedDescription
            return false
        }
    }

    @discardableResult
    public func reset() -> Bool {
        do {
            counts = try persistence.update { $0.removeAll() }
            lastErrorDescription = nil
            return true
        } catch {
            lastErrorDescription = error.localizedDescription
            return false
        }
    }

    private func migrateLegacyCountsIfNeeded(from defaults: UserDefaults?) {
        guard let defaults, !defaults.bool(forKey: Self.migrationMarkerKey) else { return }

        defer { defaults.set(true, forKey: Self.migrationMarkerKey) }

        guard
            let data = defaults.data(forKey: Self.legacyStorageKey),
            let legacyCounts = try? JSONDecoder().decode([String: Int].self, from: data),
            !legacyCounts.isEmpty
        else {
            return
        }

        do {
            _ = try persistence.update { current in
                for (candidateID, count) in legacyCounts where current[candidateID] == nil {
                    current[candidateID] = count
                }
            }
        } catch {
            lastErrorDescription = error.localizedDescription
        }
    }
}

private struct ExposurePersistence {
    let fileURL: URL

    private var lockURL: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("exposureCounts.v1.lock")
    }

    func read() throws -> [String: Int] {
        try withExclusiveLock {
            try readUnlocked()
        }
    }

    func update(_ mutation: (inout [String: Int]) -> Void) throws -> [String: Int] {
        try withExclusiveLock {
            var latest = try readUnlocked()
            mutation(&latest)
            try writeUnlocked(latest)
            return latest
        }
    }

    private func readUnlocked() throws -> [String: Int] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [:] }
        let data = try Data(contentsOf: fileURL)
        return (try? JSONDecoder().decode([String: Int].self, from: data)) ?? [:]
    }

    private func writeUnlocked(_ counts: [String: Int]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(counts)
        try data.write(to: fileURL, options: [.atomic])
    }

    private func withExclusiveLock<T>(_ body: () throws -> T) throws -> T {
        let directory = lockURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
        defer { close(descriptor) }

        guard flock(descriptor, LOCK_EX) == 0 else {
            throw CocoaError(.fileLocking)
        }
        defer { flock(descriptor, LOCK_UN) }

        return try body()
    }
}
