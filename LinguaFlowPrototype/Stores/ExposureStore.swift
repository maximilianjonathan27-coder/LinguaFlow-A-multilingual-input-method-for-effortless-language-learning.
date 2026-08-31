import Foundation
import Observation

@MainActor
@Observable
final class ExposureStore {
    static let storageKey = "linguaflow.exposureCounts.v1"

    private let defaults: UserDefaults
    private(set) var counts: [String: Int]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.counts = Self.loadCounts(from: defaults)
    }

    var hasExposures: Bool {
        counts.values.contains { $0 > 0 }
    }

    func count(for candidate: Candidate) -> Int {
        counts[candidate.id, default: 0]
    }

    func increment(_ candidate: Candidate) {
        counts[candidate.id, default: 0] += 1
        persist()
    }

    func reset() {
        counts.removeAll()
        defaults.removeObject(forKey: Self.storageKey)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(counts) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private static func loadCounts(from defaults: UserDefaults) -> [String: Int] {
        guard
            let data = defaults.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode([String: Int].self, from: data)
        else {
            return [:]
        }

        return decoded
    }
}
