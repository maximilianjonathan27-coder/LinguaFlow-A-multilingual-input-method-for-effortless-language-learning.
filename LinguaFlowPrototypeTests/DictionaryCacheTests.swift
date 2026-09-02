import LinguaFlowCore
import XCTest

final class DictionaryCacheTests: XCTestCase {
    func testLookupPlannerExtractsUsefulHeadwordsFromCEDICTGloss() {
        let terms = DictionaryLookupPlanner.lookupTerms(for: "to postpone (with unfortunate consequences); to miss (a deadline)")
        XCTAssertTrue(terms.contains("postpone"))
        XCTAssertTrue(terms.contains("miss"))
    }

    func testLookupPlannerHandlesArticlesAndUsageLabels() {
        let terms = DictionaryLookupPlanner.lookupTerms(for: "(computing) a data structure")
        XCTAssertTrue(terms.contains("data structure"))
        XCTAssertTrue(terms.contains("data"))
    }

    func testCardParserSeparatesDefinitionExamplesAndPhrases() {
        let raw = "conference con·fer·ence | ˈkänf(ə)rən(t)s | noun 1 a formal meeting for discussion: he gathered everyone for a conference. • a multi-day formal meeting: an international conference. PHRASES in conference in a meeting: the Prime Minister is in conference. ORIGIN early 16th century."
        let content = DictionaryCardContentParser.parse(raw, fallbackTerm: "conference")

        XCTAssertEqual(content.headword, "conference")
        XCTAssertEqual(content.partOfSpeech, "noun")
        XCTAssertEqual(content.pronunciation, "ˈkänf(ə)rən(t)s")
        XCTAssertTrue(content.englishDefinition.contains("formal meeting"))
        XCTAssertTrue(content.examples.contains { $0.contains("gathered everyone") })
        XCTAssertTrue(content.phrasesAndIdioms.contains { $0.expression.contains("in conference") })
        XCTAssertFalse(content.phrasesAndIdioms.contains { $0.explanation?.contains("ORIGIN") == true })
    }

    func testCardParserSplitsDensePhraseSectionIntoRows() {
        let raw = "memory | ˈmem(ə)rē | noun the faculty by which the mind stores information. PHRASES from memory without reading or referring to notes: each child recited a verse from memory. in memory of intended to remind people of a dead person: a prayer in memory of the deceased. take a trip down memory lane indulge in pleasant or sentimental memories."
        let content = DictionaryCardContentParser.parse(raw, fallbackTerm: "memory")

        XCTAssertEqual(content.phrasesAndIdioms.map(\.expression), [
            "from memory",
            "in memory of",
            "take a trip down memory lane",
        ])
        XCTAssertTrue(content.phrasesAndIdioms[0].explanation?.contains("without reading") == true)
        XCTAssertTrue(content.phrasesAndIdioms[1].explanation?.contains("a prayer") == true)
        XCTAssertTrue(content.phrasesAndIdioms[2].explanation?.contains("sentimental memories") == true)
    }

    func testCacheLoadsEntryOnlyOnce() {
        let cache = DictionaryCache()
        var loads = 0
        for _ in 0..<2 {
            let entry = cache.value(for: "conference") {
                loads += 1
                return DictionaryEntry(term: "conference", definition: "a meeting")
            }
            XCTAssertEqual(entry?.definition, "a meeting")
        }
        XCTAssertEqual(loads, 1)
    }

    func testCacheRemembersMissingEntry() {
        let cache = DictionaryCache()
        var loads = 0
        for _ in 0..<2 { _ = cache.value(for: "missing phrase") { loads += 1; return nil } }
        XCTAssertEqual(loads, 1)
    }
}
