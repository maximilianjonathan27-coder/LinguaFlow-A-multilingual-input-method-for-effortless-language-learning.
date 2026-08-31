import Foundation
import LinguaFlowCore
import XCTest

@MainActor
final class ExposureStoreTests: XCTestCase {
    private var temporaryDirectories: [URL] = []
    private var suiteNames: [String] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        for suiteName in suiteNames {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        temporaryDirectories.removeAll()
        suiteNames.removeAll()
        super.tearDown()
    }

    func testIncrementOnlyChangesSelectedCandidate() throws {
        let store = ExposureStore(fileURL: makeFileURL())
        let candidates = CandidateCatalog.candidates(for: "huiyi")
        let meeting = try XCTUnwrap(candidates.first)
        let memory = try XCTUnwrap(candidates.dropFirst().first)

        XCTAssertTrue(store.increment(meeting))

        XCTAssertEqual(store.count(for: meeting), 1)
        XCTAssertEqual(store.count(for: memory), 0)
    }

    func testCountsPersistAcrossStoreInstances() throws {
        let fileURL = makeFileURL()
        let candidate = try XCTUnwrap(CandidateCatalog.candidates(for: "anpai").first)

        let firstStore = ExposureStore(fileURL: fileURL)
        XCTAssertTrue(firstStore.increment(candidate))
        XCTAssertTrue(firstStore.increment(candidate))

        let restoredStore = ExposureStore(fileURL: fileURL)
        XCTAssertEqual(restoredStore.count(for: candidate), 2)
    }

    func testSecondStoreRefreshesChangesWrittenByFirstStore() throws {
        let fileURL = makeFileURL()
        let candidate = try XCTUnwrap(CandidateCatalog.candidates(for: "fangfa").first)
        let firstStore = ExposureStore(fileURL: fileURL)
        let secondStore = ExposureStore(fileURL: fileURL)

        XCTAssertTrue(firstStore.increment(candidate))
        secondStore.refresh()

        XCTAssertEqual(secondStore.count(for: candidate), 1)
    }

    func testResetClearsAllCounts() throws {
        let store = ExposureStore(fileURL: makeFileURL())
        let first = try XCTUnwrap(CandidateCatalog.candidates(for: "yanqi").first)
        let second = try XCTUnwrap(CandidateCatalog.candidates(for: "fangfa").first)

        _ = store.increment(first)
        _ = store.increment(second)
        XCTAssertTrue(store.reset())

        XCTAssertEqual(store.count(for: first), 0)
        XCTAssertEqual(store.count(for: second), 0)
        XCTAssertFalse(store.hasExposures)
    }

    func testCorruptFileRecoversToEmptyAndCanBeRewritten() throws {
        let fileURL = makeFileURL()
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: fileURL)
        let store = ExposureStore(fileURL: fileURL)
        let candidate = try XCTUnwrap(CandidateCatalog.candidates(for: "shenqing").first)

        XCTAssertFalse(store.hasExposures)
        XCTAssertTrue(store.increment(candidate))

        let restored = ExposureStore(fileURL: fileURL)
        XCTAssertEqual(restored.count(for: candidate), 1)
    }

    func testLegacyDefaultsMigrateOnlyOnce() throws {
        let fileURL = makeFileURL()
        let defaults = makeDefaults()
        let candidate = try XCTUnwrap(CandidateCatalog.candidates(for: "huiyi").first)
        let data = try JSONEncoder().encode([candidate.id: 4])
        defaults.set(data, forKey: ExposureStore.legacyStorageKey)

        let migrated = ExposureStore(fileURL: fileURL, legacyDefaults: defaults)
        XCTAssertEqual(migrated.count(for: candidate), 4)
        XCTAssertTrue(defaults.bool(forKey: ExposureStore.migrationMarkerKey))

        defaults.set(try JSONEncoder().encode([candidate.id: 99]), forKey: ExposureStore.legacyStorageKey)
        let restored = ExposureStore(fileURL: fileURL, legacyDefaults: defaults)
        XCTAssertEqual(restored.count(for: candidate), 4)
    }

    private func makeFileURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LinguaFlowTests-\(UUID().uuidString)", isDirectory: true)
        temporaryDirectories.append(directory)
        return directory.appendingPathComponent("exposureCounts.v1.json")
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "LinguaFlowPrototypeTests.\(UUID().uuidString)"
        suiteNames.append(suiteName)
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
