import Darwin
import Foundation
import Observation

@MainActor
@Observable
public final class SelectionStore {
    public private(set) var counts: [String: Int] = [:]
    public private(set) var lastErrorDescription: String?

    private let persistence: SelectionPersistence

    public init(fileURL: URL = SelectionStore.defaultFileURL) {
        persistence = SelectionPersistence(fileURL: fileURL)
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
            .appendingPathComponent("selectionCounts.v1.json", isDirectory: false)
    }

    public func refresh() {
        do {
            let storedCounts = try persistence.read()
            let migratedCounts = Self.migrateLegacyRimeIDs(in: storedCounts)
            if migratedCounts == storedCounts {
                counts = storedCounts
            } else {
                counts = try persistence.update { $0 = migratedCounts }
            }
            lastErrorDescription = nil
        } catch {
            counts = [:]
            lastErrorDescription = error.localizedDescription
        }
    }

    @discardableResult
    public func increment(_ candidate: Candidate) -> Bool {
        do {
            counts = try persistence.update { $0[candidate.id, default: 0] += 1 }
            lastErrorDescription = nil
            return true
        } catch {
            lastErrorDescription = error.localizedDescription
            return false
        }
    }

    private static func migrateLegacyRimeIDs(in storedCounts: [String: Int]) -> [String: Int] {
        var migrated: [String: Int] = [:]
        for (candidateID, count) in storedCounts {
            let components = candidateID.split(
                separator: ":",
                maxSplits: 3,
                omittingEmptySubsequences: false
            )
            let stableID: String
            if components.count == 4, components[0] == "rime" {
                stableID = "rime:\(components[1]):\(components[3])"
            } else {
                stableID = candidateID
            }
            migrated[stableID, default: 0] += count
        }
        return migrated
    }
}

private struct SelectionPersistence {
    let fileURL: URL
    private var lockURL: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("selectionCounts.v1.lock")
    }

    func read() throws -> [String: Int] {
        try withLock { try readUnlocked() }
    }

    func update(_ mutation: (inout [String: Int]) -> Void) throws -> [String: Int] {
        try withLock {
            var latest = try readUnlocked()
            mutation(&latest)
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(latest).write(to: fileURL, options: [.atomic])
            return latest
        }
    }

    private func readUnlocked() throws -> [String: Int] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [:] }
        return (try? JSONDecoder().decode([String: Int].self, from: Data(contentsOf: fileURL))) ?? [:]
    }

    private func withLock<T>(_ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(
            at: lockURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw CocoaError(.fileLocking) }
        defer { flock(descriptor, LOCK_UN) }
        return try body()
    }
}
