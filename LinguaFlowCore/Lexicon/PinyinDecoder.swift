import Foundation

public struct PinyinDecoder: Sendable {
    private struct Path {
        let candidates: [Candidate]
        let score: Int64
    }

    private let lexicon: any LexiconRepository
    private let targetLanguage: String

    public init(lexicon: any LexiconRepository, targetLanguage: String = "en") {
        self.lexicon = lexicon
        self.targetLanguage = targetLanguage
    }

    public func candidates(for input: String, limit: Int = 50) -> [Candidate] {
        let normalized = PinyinNormalizer.normalize(input)
        guard !normalized.isEmpty, limit > 0 else { return [] }

        var results = lexicon.candidates(
            for: normalized,
            targetLanguage: targetLanguage,
            limit: limit
        )
        results.append(contentsOf: decodedSentences(for: normalized, limit: limit))

        if results.isEmpty || !hasCompletePinyinEnding(normalized) {
            results.append(contentsOf: lexicon.prefixCandidates(
                for: normalized,
                targetLanguage: targetLanguage,
                limit: limit
            ))
        }

        var seenTexts: Set<String> = []
        return results
            .sorted {
                if $0.frequency != $1.frequency { return $0.frequency > $1.frequency }
                return $0.sourceText.count > $1.sourceText.count
            }
            .filter { seenTexts.insert($0.sourceText).inserted }
            .prefix(limit)
            .map { $0 }
    }

    private func decodedSentences(for input: String, limit: Int) -> [Candidate] {
        let characters = Array(input)
        guard characters.count > 1 else { return [] }
        var paths = Array(repeating: [Path](), count: characters.count + 1)
        paths[0] = [Path(candidates: [], score: 0)]

        for start in characters.indices where !paths[start].isEmpty {
            let maximumEnd = min(characters.count, start + 24)
            for end in (start + 1)...maximumEnd {
                let chunk = String(characters[start..<end])
                let words = lexicon.candidates(
                    for: chunk,
                    targetLanguage: targetLanguage,
                    limit: 6
                )
                guard !words.isEmpty else { continue }
                for path in paths[start].prefix(12) {
                    for word in words {
                        let frequencyScore = Int64(log(Double(max(1, word.frequency))) * 1_000)
                        let phraseBonus = Int64(max(0, word.sourceText.count - 1)) * 25_000
                        let wordScore = frequencyScore + phraseBonus - 20_000
                        paths[end].append(Path(
                            candidates: path.candidates + [word],
                            score: path.score + wordScore
                        ))
                    }
                }
                paths[end] = Array(paths[end].sorted { $0.score > $1.score }.prefix(18))
            }
        }

        return paths[characters.count]
            .filter { $0.candidates.count > 1 }
            .prefix(limit)
            .map { path in
                let translations = path.candidates.map(\.translation).filter { !$0.isEmpty }
                return Candidate(
                    id: "sentence:" + path.candidates.map(\.id).joined(separator: "+"),
                    pinyin: input,
                    sourceText: path.candidates.map(\.sourceText).joined(),
                    translation: translations.count == path.candidates.count
                        ? translations.joined(separator: " ")
                        : "",
                    frequency: Int(min(path.score, Int64(Int.max))),
                    targetLanguage: targetLanguage,
                    partOfSpeech: "sentence"
                )
            }
    }

    private func hasCompletePinyinEnding(_ input: String) -> Bool {
        Self.commonSyllables.contains { input.hasSuffix($0) }
    }

    private static let commonSyllables: Set<String> = Set("""
    a ai an ang ao ba bai ban bang bao bei ben beng bi bian biao bie bin bing bo bu
    ca cai can cang cao ce cen ceng cha chai chan chang chao che chen cheng chi chong chou chu chua chuai chuan chuang chui chun chuo ci cong cou cu cuan cui cun cuo
    da dai dan dang dao de dei den deng di dia dian diao die ding diu dong dou du duan dui dun duo
    e ei en eng er fa fan fang fei fen feng fo fou fu
    ga gai gan gang gao ge gei gen geng gong gou gu gua guai guan guang gui gun guo
    ha hai han hang hao he hei hen heng hong hou hu hua huai huan huang hui hun huo
    ji jia jian jiang jiao jie jin jing jiong jiu ju juan jue jun
    ka kai kan kang kao ke ken keng kong kou ku kua kuai kuan kuang kui kun kuo
    la lai lan lang lao le lei leng li lia lian liang liao lie lin ling liu lo long lou lu luan lun luo lv lve
    ma mai man mang mao me mei men meng mi mian miao mie min ming miu mo mou mu
    na nai nan nang nao ne nei nen neng ni nian niang niao nie nin ning niu nong nou nu nuan nuo nv nve
    o ou pa pai pan pang pao pei pen peng pi pian piao pie pin ping po pou pu
    qi qia qian qiang qiao qie qin qing qiong qiu qu quan que qun
    ran rang rao re ren reng ri rong rou ru rua ruan rui run ruo
    sa sai san sang sao se sen seng sha shai shan shang shao she shei shen sheng shi shou shu shua shuai shuan shuang shui shun shuo si song sou su suan sui sun suo
    ta tai tan tang tao te teng ti tian tiao tie ting tong tou tu tuan tui tun tuo
    wa wai wan wang wei wen weng wo wu
    xi xia xian xiang xiao xie xin xing xiong xiu xu xuan xue xun
    ya yan yang yao ye yi yin ying yo yong you yu yuan yue yun
    za zai zan zang zao ze zei zen zeng zha zhai zhan zhang zhao zhe zhei zhen zheng zhi zhong zhou zhu zhua zhuai zhuan zhuang zhui zhun zhuo zi zong zou zu zuan zui zun zuo
    """.split(whereSeparator: \.isWhitespace).map(String.init))
}
