import LinguaFlowCore
import SQLite3
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
        XCTAssertTrue(
            results.filter { $0.id.hasPrefix("sentence:") }.allSatisfy { $0.translation.isEmpty },
            "Generated Chinese combinations must not pretend that word-by-word English is a sentence translation."
        )
    }

    func testTypicalAmbiguousWordsUseCommonMeaningAndKeepAllSenses() throws {
        let lexicon = try SQLiteLexicon(databaseURL: databaseURL)

        let university = try XCTUnwrap(lexicon.candidates(for: "daxue", limit: 20).first { $0.sourceText == "大学" && !$0.isProperNoun })
        XCTAssertEqual(university.translation, "university")
        XCTAssertTrue(university.translationSenses.contains { $0.glosses.contains("college") })

        let xing = try XCTUnwrap(lexicon.candidates(for: "xing", limit: 20).first { $0.sourceText == "行" })
        XCTAssertEqual(xing.translation, "okay")
        XCTAssertTrue(xing.translationSenses.flatMap(\.glosses).contains("all right"))

        let wangCandidates = lexicon.candidates(for: "wang", limit: 30).filter { $0.sourceText == "王" }
        XCTAssertEqual(wangCandidates.first?.translation, "king")
        XCTAssertTrue(wangCandidates.contains { $0.isProperNoun && $0.translation == "surname Wang" })

        let mingCandidates = lexicon.candidates(for: "ming", limit: 30).filter { $0.sourceText == "明" }
        XCTAssertEqual(mingCandidates.first?.translation, "bright")
        XCTAssertTrue(mingCandidates.contains { $0.isProperNoun && $0.translation.contains("Ming Dynasty") })
    }

    func testTwoHundredHighFrequencyWordSensesRoundTripThroughRepository() throws {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        let openedDatabase = try XCTUnwrap(database)
        defer { sqlite3_close(openedDatabase) }

        let sql = """
            SELECT stable_id, normalized_pinyin, chinese
            FROM lexemes
            WHERE is_proper_noun = 0 AND meaning_rank < 9999 AND frequency > 0
            ORDER BY frequency DESC, meaning_rank ASC, stable_id ASC
            LIMIT 200
            """
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(openedDatabase, sql, -1, &statement, nil), SQLITE_OK)
        let prepared = try XCTUnwrap(statement)
        defer { sqlite3_finalize(prepared) }

        var samples: [(id: String, pinyin: String, chinese: String)] = []
        while sqlite3_step(prepared) == SQLITE_ROW {
            samples.append((databaseText(prepared, 0), databaseText(prepared, 1), databaseText(prepared, 2)))
        }
        XCTAssertEqual(samples.count, 200)

        let lexicon = try SQLiteLexicon(databaseURL: databaseURL)
        for (offset, sample) in samples.enumerated() {
            let candidate = try XCTUnwrap(
                lexicon.candidates(for: sample.pinyin, limit: 100).first { $0.id == sample.id },
                "Sense case \(offset + 1): \(sample.chinese) [\(sample.pinyin)]"
            )
            XCTAssertFalse(candidate.translation.isEmpty, "Sense case \(offset + 1) has no primary gloss")
            XCTAssertFalse(candidate.translationSenses.isEmpty, "Sense case \(offset + 1) has no structured senses")
            XCTAssertEqual(candidate.translation, candidate.translationSenses.first?.glosses.first)
            XCTAssertEqual(
                candidate.translationSenses.map(\.commonnessRank),
                candidate.translationSenses.map(\.commonnessRank).sorted(),
                "Sense case \(offset + 1) is not ordered by commonness"
            )
        }
    }

    func testLexiconUsesVersionTwoSenseSchema() throws {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        let openedDatabase = try XCTUnwrap(database)
        defer { sqlite3_close(openedDatabase) }
        XCTAssertEqual(scalarInt(openedDatabase, sql: "PRAGMA user_version"), 2)
        XCTAssertGreaterThan(scalarInt(openedDatabase, sql: "SELECT count(*) FROM translation_senses"), 190_000)
        XCTAssertGreaterThan(scalarInt(openedDatabase, sql: "SELECT count(*) FROM translation_glosses"), 200_000)
    }

    func testExamplesDatabaseContainsOfflineTatoebaDataWithoutHistoryTables() throws {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(examplesDatabaseURL.path, &database, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        let openedDatabase = try XCTUnwrap(database)
        defer { sqlite3_close(openedDatabase) }

        XCTAssertEqual(scalarInt(openedDatabase, sql: "PRAGMA user_version"), 1)
        XCTAssertEqual(scalarInt(openedDatabase, sql: "SELECT count(*) FROM phrases"), 10)
        XCTAssertGreaterThan(scalarInt(openedDatabase, sql: "SELECT count(*) FROM examples"), 50_000)
        XCTAssertGreaterThan(scalarInt(openedDatabase, sql: "SELECT count(*) FROM example_terms"), 240_000)
        XCTAssertEqual(
            scalarInt(openedDatabase, sql: "SELECT count(*) FROM sqlite_master WHERE type='table' AND (name LIKE '%history%' OR name LIKE '%user_input%')"),
            0
        )
    }

    func testReviewedPhrasesUseLongestExactMatchInsteadOfWordSplitting() throws {
        let lexicon = try SQLiteLexicon(databaseURL: databaseURL)
        let examples = try SQLiteExampleRepository(databaseURL: examplesDatabaseURL)
        let decoder = PinyinDecoder(lexicon: lexicon, examples: examples)
        let expectations = [
            ("shenqingdaxue", "申请大学", "apply to a university"),
            ("tijiaoshenqing", "提交申请", "submit an application"),
            ("shenqingdaikuan", "申请贷款", "apply for a loan"),
            ("pizhunshenqing", "批准申请", "approve an application"),
        ]

        for (input, chinese, english) in expectations {
            let candidates = decoder.candidates(for: input, limit: 20)
            XCTAssertEqual(candidates.first?.sourceText, chinese)
            XCTAssertEqual(candidates.first?.translation, english)
            XCTAssertTrue(candidates.first?.id.hasPrefix("phrase.") == true)
            XCTAssertFalse(candidates.prefix(5).contains { $0.id.hasPrefix("sentence:") })
        }
    }

    func testLongestPhraseIsPreservedInsideALongerComposition() throws {
        let decoder = PinyinDecoder(
            lexicon: try SQLiteLexicon(databaseURL: databaseURL),
            examples: try SQLiteExampleRepository(databaseURL: examplesDatabaseURL)
        )
        let results = decoder.candidates(for: "woyaoshenqingdaxue", limit: 30)
        let sentence = try XCTUnwrap(
            results.first {
                $0.sourceText == "我要申请大学"
            },
            results.map { "\($0.sourceText):\($0.id)" }.joined(separator: "\n")
        )

        XCTAssertTrue(sentence.id.contains("phrase.apply-university"))
        XCTAssertTrue(sentence.translation.isEmpty)
    }

    func testVocabularyCardReturnsReviewedAndTatoebaExamples() throws {
        let repository = try SQLiteExampleRepository(databaseURL: examplesDatabaseURL)
        let phrase = try XCTUnwrap(repository.phraseCandidates(for: "shenqingdaxue", limit: 3).first)
        XCTAssertEqual(Array(phrase.examples.map(\.english).prefix(2)), [
            "I'm applying to a university.",
            "She applied to three universities.",
        ])

        let universityExamples = repository.examples(for: "大学", limit: 5)
        XCTAssertFalse(universityExamples.isEmpty)
        XCTAssertTrue(universityExamples.allSatisfy { $0.source == "tatoeba-mdx" })
        XCTAssertTrue(universityExamples.allSatisfy { !$0.chinese.isEmpty && !$0.english.isEmpty })
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
            XCTAssertTrue(results.contains { !$0.translation.isEmpty })
            XCTAssertTrue(
                results.filter { $0.id.hasPrefix("sentence:") }.allSatisfy { $0.translation.isEmpty },
                "\(input) must not show a mechanically concatenated sentence translation"
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

    private var examplesDatabaseURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("LinguaFlowInputMethod/Resources/tatoeba_examples.sqlite")
    }

    private func databaseText(_ statement: OpaquePointer, _ column: Int32) -> String {
        guard let value = sqlite3_column_text(statement, column) else { return "" }
        return String(cString: value)
    }

    private func scalarInt(_ database: OpaquePointer, sql: String) -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { return -1 }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return -1 }
        return Int(sqlite3_column_int64(statement, 0))
    }
}
