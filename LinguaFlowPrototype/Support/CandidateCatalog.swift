import Foundation

enum CandidateCatalog {
    static let supportedInputs = ["huiyi", "anpai", "yanqi", "shenqing", "fangfa"]

    private static let candidatesByInput: [String: [Candidate]] = [
        "huiyi": [
            Candidate(id: "huiyi.meeting", pinyin: "huiyi", sourceText: "会议", translation: "meeting"),
            Candidate(id: "huiyi.memory", pinyin: "huiyi", sourceText: "回忆", translation: "memory"),
            Candidate(id: "huiyi.grasp", pinyin: "huiyi", sourceText: "会意", translation: "grasp the meaning"),
        ],
        "anpai": [
            Candidate(id: "anpai.arrange", pinyin: "anpai", sourceText: "安排", translation: "arrange"),
            Candidate(id: "anpai.meeting", pinyin: "anpai", sourceText: "安排会议", translation: "schedule a meeting"),
            Candidate(id: "anpai.time", pinyin: "anpai", sourceText: "安排时间", translation: "arrange a time"),
        ],
        "yanqi": [
            Candidate(id: "yanqi.postpone", pinyin: "yanqi", sourceText: "延期", translation: "postpone"),
            Candidate(id: "yanqi.meeting", pinyin: "yanqi", sourceText: "延期会议", translation: "postpone the meeting"),
            Candidate(id: "yanqi.submission", pinyin: "yanqi", sourceText: "延期提交", translation: "defer submission"),
        ],
        "shenqing": [
            Candidate(id: "shenqing.apply", pinyin: "shenqing", sourceText: "申请", translation: "apply"),
            Candidate(id: "shenqing.university", pinyin: "shenqing", sourceText: "申请大学", translation: "apply to a university"),
            Candidate(id: "shenqing.submit", pinyin: "shenqing", sourceText: "提交申请", translation: "submit an application"),
        ],
        "fangfa": [
            Candidate(id: "fangfa.method", pinyin: "fangfa", sourceText: "方法", translation: "method"),
            Candidate(id: "fangfa.approach", pinyin: "fangfa", sourceText: "这个方法", translation: "this approach"),
            Candidate(id: "fangfa.learning", pinyin: "fangfa", sourceText: "学习方法", translation: "learning method"),
        ],
    ]

    static func normalizedInput(_ input: String) -> String {
        input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func candidates(for input: String) -> [Candidate] {
        candidatesByInput[normalizedInput(input)] ?? []
    }

    static func primaryCandidate(for input: String) -> Candidate? {
        candidates(for: input).first
    }
}
