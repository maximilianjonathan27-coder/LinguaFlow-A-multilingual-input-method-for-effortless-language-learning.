import Foundation

public enum CandidateCatalog {
    public static let supportedInputs = ["huiyi", "anpai", "yanqi", "shenqing", "fangfa"]

    public static let seedCandidates: [Candidate] = [
        Candidate(id: "huiyi.meeting", pinyin: "hui yi", sourceText: "会议", translation: "meeting", frequency: 9_820, partOfSpeech: "noun"),
        Candidate(id: "huiyi.memory", pinyin: "hui yi", sourceText: "回忆", translation: "memory", frequency: 7_610, partOfSpeech: "noun"),
        Candidate(id: "huiyi.grasp", pinyin: "hui yi", sourceText: "会意", translation: "grasp the meaning", frequency: 2_800, partOfSpeech: "verb"),
        Candidate(id: "anpai.arrange", pinyin: "an pai", sourceText: "安排", translation: "arrange", frequency: 9_500, partOfSpeech: "verb"),
        Candidate(id: "anpai.meeting", pinyin: "an pai", sourceText: "安排会议", translation: "schedule a meeting", frequency: 7_200, partOfSpeech: "phrase", domain: "work"),
        Candidate(id: "anpai.time", pinyin: "an pai", sourceText: "安排时间", translation: "arrange a time", frequency: 6_800, partOfSpeech: "phrase"),
        Candidate(id: "yanqi.postpone", pinyin: "yan qi", sourceText: "延期", translation: "postpone", frequency: 8_900, partOfSpeech: "verb"),
        Candidate(id: "yanqi.meeting", pinyin: "yan qi", sourceText: "延期会议", translation: "postpone the meeting", frequency: 5_900, partOfSpeech: "phrase", domain: "work"),
        Candidate(id: "yanqi.submission", pinyin: "yan qi", sourceText: "延期提交", translation: "defer submission", frequency: 4_700, partOfSpeech: "phrase", domain: "work"),
        Candidate(id: "shenqing.apply", pinyin: "shen qing", sourceText: "申请", translation: "apply", frequency: 9_600, partOfSpeech: "verb"),
        Candidate(id: "shenqing.university", pinyin: "shen qing", sourceText: "申请大学", translation: "apply to a university", frequency: 6_200, partOfSpeech: "phrase", domain: "education"),
        Candidate(id: "shenqing.submit", pinyin: "shen qing", sourceText: "提交申请", translation: "submit an application", frequency: 5_500, partOfSpeech: "phrase", domain: "work"),
        Candidate(id: "fangfa.method", pinyin: "fang fa", sourceText: "方法", translation: "method", frequency: 9_700, partOfSpeech: "noun"),
        Candidate(id: "fangfa.approach", pinyin: "fang fa", sourceText: "这个方法", translation: "this approach", frequency: 6_100, partOfSpeech: "phrase"),
        Candidate(id: "fangfa.learning", pinyin: "fang fa", sourceText: "学习方法", translation: "learning method", frequency: 5_800, partOfSpeech: "phrase", domain: "education"),
    ]

    public static let repository = InMemoryLexicon(candidates: seedCandidates)

    public static func normalizedInput(_ input: String) -> String {
        PinyinNormalizer.normalize(input)
    }

    public static func candidates(for input: String) -> [Candidate] {
        repository.candidates(for: input, limit: 10)
    }

    public static func primaryCandidate(for input: String) -> Candidate? {
        candidates(for: input).first
    }
}
