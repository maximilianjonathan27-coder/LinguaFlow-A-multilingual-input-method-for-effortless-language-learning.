import XCTest
@testable import LinguaFlowPrototype

@MainActor
final class ExposureStoreTests: XCTestCase {
    private var suiteNames: [String] = []

    override func tearDown() {
        for suiteName in suiteNames {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        suiteNames.removeAll()
        super.tearDown()
    }

    func testIncrementOnlyChangesSelectedCandidate() throws {
        let defaults = makeDefaults()
        let store = ExposureStore(defaults: defaults)
        let candidates = CandidateCatalog.candidates(for: "huiyi")
        let meeting = try XCTUnwrap(candidates.first)
        let memory = try XCTUnwrap(candidates.dropFirst().first)

        store.increment(meeting)

        XCTAssertEqual(store.count(for: meeting), 1)
        XCTAssertEqual(store.count(for: memory), 0)
    }

    func testCountsPersistAcrossStoreInstances() throws {
        let defaults = makeDefaults()
        let candidate = try XCTUnwrap(CandidateCatalog.candidates(for: "anpai").first)

        let firstStore = ExposureStore(defaults: defaults)
        firstStore.increment(candidate)
        firstStore.increment(candidate)

        let restoredStore = ExposureStore(defaults: defaults)
        XCTAssertEqual(restoredStore.count(for: candidate), 2)
    }

    func testResetClearsAllCounts() throws {
        let defaults = makeDefaults()
        let store = ExposureStore(defaults: defaults)
        let first = try XCTUnwrap(CandidateCatalog.candidates(for: "yanqi").first)
        let second = try XCTUnwrap(CandidateCatalog.candidates(for: "fangfa").first)

        store.increment(first)
        store.increment(second)
        store.reset()

        XCTAssertEqual(store.count(for: first), 0)
        XCTAssertEqual(store.count(for: second), 0)
        XCTAssertFalse(store.hasExposures)
        XCTAssertNil(defaults.object(forKey: ExposureStore.storageKey))
    }

    func testDifferentCandidatesKeepIndependentCounts() throws {
        let defaults = makeDefaults()
        let store = ExposureStore(defaults: defaults)
        let first = try XCTUnwrap(CandidateCatalog.candidates(for: "shenqing").first)
        let second = try XCTUnwrap(CandidateCatalog.candidates(for: "shenqing").last)

        store.increment(first)
        store.increment(first)
        store.increment(second)

        XCTAssertEqual(store.count(for: first), 2)
        XCTAssertEqual(store.count(for: second), 1)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "LinguaFlowPrototypeTests.\(UUID().uuidString)"
        suiteNames.append(suiteName)
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
