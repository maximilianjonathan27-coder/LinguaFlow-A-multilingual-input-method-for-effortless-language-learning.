import LinguaFlowCore
import XCTest

final class LexiconTests: XCTestCase {
    func testPinyinNormalizerSupportsSpacesCaseAndNewlines() {
        XCTAssertEqual(PinyinNormalizer.normalize("  Hui Yi\n"), "huiyi")
        XCTAssertEqual(PinyinNormalizer.normalize("SHEN qing"), "shenqing")
    }

    func testPinyinCompositionFormattingSupportsCompleteAndPartialSyllables() {
        XCTAssertEqual(PinyinNormalizer.formattedComposition("nihao"), "ni hao")
        XCTAssertEqual(PinyinNormalizer.formattedComposition("woxiangqu"), "wo xiang qu")
        XCTAssertEqual(PinyinNormalizer.formattedComposition("nih"), "ni h")
        XCTAssertEqual(PinyinNormalizer.formattedComposition("xian"), "xian")
        XCTAssertEqual(PinyinNormalizer.formattedComposition("xi'an"), "xi an")
        XCTAssertEqual(PinyinNormalizer.formattedComposition("hhhh"), "h h h h")
        XCTAssertEqual(PinyinNormalizer.formattedComposition("shsh"), "sh sh")
        XCTAssertEqual(PinyinNormalizer.formattedComposition("nh"), "n h")
        XCTAssertEqual(
            PinyinNormalizer.compositionDisplay("nihao", rawCursor: 3).cursor,
            4
        )
    }

    func testPinyinNormalizerExposesAmbiguousCompleteSegmentations() {
        let segmentations = PinyinNormalizer.segmentations(for: "xian")

        XCTAssertEqual(segmentations.first, ["xian"])
        XCTAssertTrue(segmentations.contains(["xi", "an"]))
    }

    func testRankerDoesNotPenalizeAnAlternateExactSegmentation() {
        let candidates = [
            Candidate(id: "xian", pinyin: "xian", sourceText: "先", translation: "first", frequency: 100),
            Candidate(id: "xi-an", pinyin: "xi an", sourceText: "西安", translation: "Xi'an", frequency: 99),
        ]

        let ranked = CandidateRanker.rank(candidates, for: "xian", selectionCounts: [:])
        XCTAssertEqual(ranked.map(\.sourceText), ["先", "西安"])
    }

    func testRankerPreservesLibrimeSentenceOrderForTypoRecovery() {
        let candidates = [
            Candidate(
                id: "rime:这更改",
                pinyin: "zhe geng gai",
                sourceText: "这更改",
                translation: "",
                frequency: 2_000_000_000
            ),
            Candidate(
                id: "rime:这",
                pinyin: "zhe",
                sourceText: "这",
                translation: "this",
                frequency: 1_999_999_999
            ),
        ]

        let ranked = CandidateRanker.rank(candidates, for: "zheggai", selectionCounts: [:])
        XCTAssertEqual(ranked.map(\.sourceText), ["这更改", "这"])
    }

    func testLibrimeInitialOrderStaysAheadOfSupplementalHeuristics() {
        let candidates = [
            Candidate(
                id: "rime:先",
                pinyin: "xian",
                sourceText: "先",
                translation: "first",
                frequency: 1
            ),
            Candidate(
                id: "supplement:西安",
                pinyin: "xi an",
                sourceText: "西安",
                translation: "Xi'an",
                frequency: 2_000_000_000
            ),
            Candidate(
                id: "rime:现",
                pinyin: "xian",
                sourceText: "现",
                translation: "present",
                frequency: 1
            ),
        ]

        let ranked = CandidateRanker.rank(candidates, for: "xian", selectionCounts: [:])

        XCTAssertEqual(ranked.map(\.sourceText), ["先", "现", "西安"])
    }

    func testCommittedUsageCanPromoteAStableLibrimeCandidate() {
        let candidates = [
            Candidate(
                id: "rime:把",
                pinyin: "ba",
                sourceText: "把",
                translation: "to hold",
                frequency: 2_000_000_000
            ),
            Candidate(
                id: "rime:吧",
                pinyin: "ba",
                sourceText: "吧",
                translation: "modal particle",
                frequency: 1_999_999_999
            ),
        ]

        let ranked = CandidateRanker.rank(
            candidates,
            for: "ba",
            selectionCounts: ["rime:吧": 1]
        )

        XCTAssertEqual(ranked.first?.sourceText, "吧")
    }

    func testChinesePunctuationMappingsCoverCommonKeyboardSymbols() {
        XCTAssertEqual(PinyinNormalizer.chinesePunctuation(for: ","), "，")
        XCTAssertEqual(PinyinNormalizer.chinesePunctuation(for: "."), "。")
        XCTAssertEqual(PinyinNormalizer.chinesePunctuation(for: "/"), "、")
        XCTAssertEqual(PinyinNormalizer.chinesePunctuation(for: "?"), "？")
        XCTAssertEqual(PinyinNormalizer.chinesePunctuation(for: "\""), "“")
        XCTAssertEqual(PinyinNormalizer.chinesePunctuation(for: "("), "（")
        XCTAssertEqual(PinyinNormalizer.chinesePunctuation(for: "_"), "——")
        XCTAssertEqual(PinyinNormalizer.chinesePunctuation(for: "^"), "……")
    }

    func testSingleEditCorrectionRecognizesConservativeTypos() {
        XCTAssertTrue(PinyinNormalizer.isSingleEditCorrection(input: "nihaoo", candidate: "nihao"))
        XCTAssertTrue(PinyinNormalizer.isSingleEditCorrection(input: "niha", candidate: "nihao"))
        XCTAssertTrue(PinyinNormalizer.isSingleEditCorrection(input: "niaho", candidate: "nihao"))
        XCTAssertTrue(PinyinNormalizer.isSingleEditCorrection(input: "nihqo", candidate: "nihao"))
        XCTAssertFalse(PinyinNormalizer.isSingleEditCorrection(input: "nixao", candidate: "nihao"))
        XCTAssertFalse(PinyinNormalizer.isSingleEditCorrection(input: "nihxx", candidate: "nihao"))
    }

    func testSQLiteLexiconReturnsTranslatedCandidates() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let databaseURL = repositoryRoot
            .appendingPathComponent("LinguaFlowInputMethod/Resources/linguaflow.sqlite")
        let lexicon = try SQLiteLexicon(databaseURL: databaseURL)

        let candidates = lexicon.candidates(for: "HUI YI", limit: 10)

        XCTAssertEqual(candidates.first?.sourceText, "会议")
        XCTAssertTrue(candidates.contains { $0.sourceText == "回忆" })
        XCTAssertTrue(candidates.contains { $0.sourceText == "会意" })
        XCTAssertEqual(candidates.first?.translation, "meeting")
        XCTAssertEqual(candidates.first?.targetLanguage, "en")
    }

    func testSelectionFrequencyCanPromoteARegularCandidate() {
        let candidates = CandidateCatalog.candidates(for: "huiyi")
        let ranked = CandidateRanker.rank(
            candidates,
            for: "huiyi",
            selectionCounts: ["huiyi.memory": 1]
        )

        XCTAssertEqual(ranked.first?.id, "huiyi.memory")
    }

    func testRankerKeepsNoisyLongProperNounsBehindCommonWordsForPrefixes() {
        let candidates = [
            Candidate(
                id: "title",
                pinyin: "san guo qun ying zhuan",
                sourceText: "三国群英传",
                translation: "",
                frequency: 12_345_678
            ),
            Candidate(
                id: "say",
                pinyin: "shuo",
                sourceText: "说",
                translation: "to say",
                frequency: 12_000_460
            ),
        ]

        XCTAssertEqual(
            CandidateRanker.rank(candidates, for: "s", selectionCounts: [:]).first?.sourceText,
            "说"
        )
        XCTAssertEqual(
            CandidateRanker.rank(
                candidates,
                for: "sanguoqunyingzhuan",
                selectionCounts: [:]
            ).first?.sourceText,
            "三国群英传"
        )
    }

    func testRealPrefixCandidatesPrioritizeEverydayCharacters() throws {
        var machine = CompositionStateMachine(
            lexicon: try SQLiteLexicon(databaseURL: databaseURL)
        )
        _ = machine.handle(.insertLetter("s"))

        let topFive = machine.allCandidates.prefix(5).map(\.sourceText)
        XCTAssertEqual(topFive.first, "是")
        XCTAssertTrue(topFive.contains("说"))
        XCTAssertTrue(topFive.contains("上"))
        XCTAssertFalse(topFive.contains("三国群英传"))
    }

    func testSQLiteLexiconSupportsCommonCharactersAndPrefixLookup() throws {
        let lexicon = try SQLiteLexicon(databaseURL: databaseURL)

        XCTAssertEqual(lexicon.candidates(for: "wo", limit: 5).first?.sourceText, "我")
        XCTAssertTrue(lexicon.prefixCandidates(for: "niha", limit: 10).contains {
            $0.sourceText == "你好"
        })
    }

    func testSQLiteLexiconSupportsAbbreviationsAndSingleEditCorrections() throws {
        let lexicon = try SQLiteLexicon(databaseURL: databaseURL)

        XCTAssertTrue(lexicon.abbreviationCandidates(for: "nh", limit: 20).contains {
            $0.sourceText == "你好"
        })
        XCTAssertTrue(lexicon.abbreviationCandidates(for: "bj", limit: 20).contains {
            $0.sourceText == "北京"
        })
        XCTAssertTrue(lexicon.correctionCandidates(for: "niaho", limit: 20).contains {
            $0.sourceText == "你好"
        })
        XCTAssertTrue(lexicon.correctionCandidates(for: "nihaoo", limit: 20).contains {
            $0.sourceText == "你好"
        })
    }

    func testDecoderPrioritizesExactThenSupportsAbbreviationAndTypos() throws {
        let decoder = PinyinDecoder(lexicon: try SQLiteLexicon(databaseURL: databaseURL))

        XCTAssertEqual(decoder.candidates(for: "nihao", limit: 20).first?.sourceText, "你好")
        XCTAssertTrue(decoder.candidates(for: "nh", limit: 20).contains { $0.sourceText == "你好" })
        XCTAssertTrue(decoder.candidates(for: "niaho", limit: 20).contains { $0.sourceText == "你好" })
        XCTAssertTrue(decoder.candidates(for: "nihaoo", limit: 20).contains { $0.sourceText == "你好" })
        XCTAssertTrue(decoder.candidates(for: "nihqo", limit: 20).contains { $0.sourceText == "你好" })
    }

    func testDecoderBuildsContinuousPinyinSentence() throws {
        let decoder = PinyinDecoder(lexicon: try SQLiteLexicon(databaseURL: databaseURL))
        let results = decoder.candidates(for: "woxiangqubeijing", limit: 20)

        XCTAssertTrue(results.contains { $0.sourceText == "我想去北京" })
    }

    func testDecoderPrefersEverydaySegmentationForYouFirstHelp() throws {
        let decoder = PinyinDecoder(lexicon: try SQLiteLexicon(databaseURL: databaseURL))
        let results = decoder.candidates(for: "ni xian bang", limit: 20)

        XCTAssertEqual(results.first?.sourceText, "你先帮")
        XCTAssertFalse(results.prefix(5).contains { $0.sourceText == "逆袭安邦" })
    }

    func testCommonWordsOutsideGlobalTopLimitRemainAvailable() throws {
        let lexicon = try SQLiteLexicon(databaseURL: databaseURL)
        let results = lexicon.candidates(for: "ni ba", limit: 20)

        XCTAssertTrue(results.contains { candidate in
            candidate.sourceText == "泥巴" && candidate.translation == "(coll.) mud"
        })
    }

    func testDecoderHandlesAmbiguousAndExplicitPinyinBoundaries() throws {
        let lexicon = try SQLiteLexicon(databaseURL: databaseURL)
        let decoder = PinyinDecoder(lexicon: lexicon)

        XCTAssertEqual(decoder.candidates(for: "xuanfu", limit: 30).first?.sourceText, "悬浮")
        XCTAssertTrue(decoder.candidates(for: "xian", limit: 50).contains {
            $0.sourceText == "西安" && $0.pinyin == "xi an"
        })

        var explicitMachine = CompositionStateMachine(lexicon: lexicon)
        for character in "xi'an" {
            _ = explicitMachine.handle(.insertLetter(character))
        }
        XCTAssertEqual(explicitMachine.allCandidates.first?.sourceText, "西安")
    }

    func testDecoderCompletesUnfinishedFinalSyllableInSentence() throws {
        let decoder = PinyinDecoder(lexicon: try SQLiteLexicon(databaseURL: databaseURL))
        let results = decoder.candidates(for: "nibangw", limit: 20)

        XCTAssertEqual(results.first?.sourceText, "你帮我")
        XCTAssertEqual(results.first?.pinyin, "nibangw")
    }

    func testDecoderSupportsMixedFullPinyinAndInitials() throws {
        let decoder = PinyinDecoder(lexicon: try SQLiteLexicon(databaseURL: databaseURL))

        XCTAssertEqual(
            decoder.candidates(for: "niky", limit: 20).first?.sourceText,
            "你可以"
        )
        XCTAssertEqual(
            decoder.candidates(for: "ni k y", limit: 20).first?.sourceText,
            "你可以"
        )
    }

    func testInitialCandidatesIncludeFullPhraseThenTwoAndOneCharacterPrefixes() throws {
        let decoder = PinyinDecoder(lexicon: try SQLiteLexicon(databaseURL: databaseURL))
        let results = decoder.candidates(for: "nky", limit: 50)

        let fullIndex = try XCTUnwrap(results.firstIndex { $0.sourceText == "你可以" })
        let twoIndex = try XCTUnwrap(results.firstIndex { $0.sourceText == "你看" })
        let oneIndex = try XCTUnwrap(results.firstIndex { $0.sourceText == "你" })
        XCTAssertLessThan(fullIndex, twoIndex)
        XCTAssertLessThan(twoIndex, oneIndex)
    }

    func testEnglishPrefixCandidatesAppearInCandidateList() throws {
        let decoder = PinyinDecoder(lexicon: try SQLiteLexicon(databaseURL: databaseURL))
        let nearResults = decoder.candidates(for: "hel", limit: 50)
        let longerPrefixResults = decoder.candidates(for: "profe", limit: 50)
        let exactResults = decoder.candidates(for: "hello", limit: 50)

        XCTAssertTrue(nearResults.contains { $0.sourceText == "hello" })
        XCTAssertTrue(nearResults.contains { $0.sourceText == "help" && $0.domain == "english" })
        XCTAssertTrue(longerPrefixResults.contains {
            $0.sourceText == "professor" && $0.domain == "english"
        })
        XCTAssertTrue(exactResults.contains { $0.sourceText == "hello" && $0.domain == "english" })
        XCTAssertFalse(decoder.candidates(for: "he", limit: 50).contains {
            $0.domain == "english"
        })
    }

    func testEnglishCompletionLeadsWhenThereIsNoExactChineseMatch() throws {
        let lexicon = try SQLiteLexicon(databaseURL: databaseURL)
        var machine = CompositionStateMachine(lexicon: lexicon)
        for character in "profe" { _ = machine.handle(.insertLetter(character)) }

        XCTAssertEqual(machine.allCandidates.first?.sourceText, "professor")
        XCTAssertEqual(machine.allCandidates.first?.domain, "english")
    }

    func testExactEnglishLeadsOnlyWithoutExactChineseMatch() throws {
        let lexicon = try SQLiteLexicon(databaseURL: databaseURL)
        var englishMachine = CompositionStateMachine(lexicon: lexicon)
        for character in "hello" { _ = englishMachine.handle(.insertLetter(character)) }
        XCTAssertEqual(englishMachine.allCandidates.first?.sourceText, "hello")

        var chineseMachine = CompositionStateMachine(lexicon: lexicon)
        for character in "can" { _ = chineseMachine.handle(.insertLetter(character)) }
        XCTAssertNotEqual(chineseMachine.allCandidates.first?.domain, "english")
        XCTAssertTrue(chineseMachine.allCandidates.contains {
            $0.sourceText == "can" && $0.domain == "english"
        })
    }

    func testDecoderKeepsCommonWordsBeforeSingleCharacterFallbacks() throws {
        let decoder = PinyinDecoder(lexicon: try SQLiteLexicon(databaseURL: databaseURL))

        for input in ["nihao", "huiyi", "anpai", "shenqing", "nide", "wode"] {
            let results = decoder.candidates(for: input, limit: 40)
            let firstCharacterIndex = try XCTUnwrap(
                results.firstIndex { $0.sourceText.count == 1 },
                "\(input) should include single-character fallbacks"
            )

            XCTAssertTrue(
                results[firstCharacterIndex...].allSatisfy {
                    $0.sourceText.count == 1 || $0.domain == "english"
                },
                "\(input) should not contain generated low-frequency words after character fallbacks"
            )
            XCTAssertFalse(
                results.contains { $0.id.hasPrefix("sentence:") },
                "\(input) already has complete words and should not include mechanical sentence combinations"
            )
            XCTAssertTrue(
                results.prefix(12).allSatisfy { !$0.translation.isEmpty },
                "\(input) should prioritize candidates with English definitions"
            )
        }
    }

    @MainActor
    func testSelectionCountsPersistSeparately() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directory.appendingPathComponent("selection.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let candidate = try XCTUnwrap(CandidateCatalog.primaryCandidate(for: "huiyi"))
        XCTAssertTrue(SelectionStore(fileURL: fileURL).increment(candidate))
        XCTAssertEqual(SelectionStore(fileURL: fileURL).counts[candidate.id], 1)
    }

    private var databaseURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("LinguaFlowInputMethod/Resources/linguaflow.sqlite")
    }
}
