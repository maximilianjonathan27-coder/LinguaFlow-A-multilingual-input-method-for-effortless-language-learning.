import Foundation

public enum PinyinNormalizer {
    public static func normalize(_ input: String) -> String {
        input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { $0.isASCII && $0.isLetter }
    }

    public static func formattedComposition(_ input: String) -> String {
        compositionDisplay(input, rawCursor: input.count).text
    }

    public static func chinesePunctuation(for text: String) -> String? {
        chinesePunctuation[text]
    }

    public static func compositionDisplay(
        _ input: String,
        rawCursor: Int
    ) -> (text: String, cursor: Int) {
        let rawCharacters = Array(input.lowercased())
        var insertedBoundaries: Set<Int> = []
        var regionStart = 0

        for index in 0...rawCharacters.count {
            let isSeparator = index < rawCharacters.count && rawCharacters[index] == "'"
            guard index == rawCharacters.count || isSeparator else { continue }
            let region = String(rawCharacters[regionStart..<index])
            var length = 0
            for syllable in segments(for: region).dropLast() {
                length += syllable.count
                insertedBoundaries.insert(regionStart + length)
            }
            regionStart = index + 1
        }

        var formatted = ""
        for (index, character) in rawCharacters.enumerated() {
            if insertedBoundaries.contains(index), formatted.last != " " {
                formatted.append(" ")
            }
            formatted.append(character == "'" ? " " : character)
        }

        let boundedCursor = min(max(0, rawCursor), rawCharacters.count)
        let insertedBeforeCursor = insertedBoundaries.count { $0 < boundedCursor }
        return (formatted, boundedCursor + insertedBeforeCursor)
    }

    public static func initials(for input: String) -> String {
        let explicitSyllables = input.lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0 == "'" })
            .map(String.init)
        let syllables = explicitSyllables.count > 1 ? explicitSyllables : segments(for: input)
        return syllables.compactMap(\.first).map(String.init).joined()
    }

    public static func isSingleEditCorrection(input: String, candidate: String) -> Bool {
        let source = Array(normalize(input))
        let target = Array(normalize(candidate))
        guard !source.isEmpty, !target.isEmpty, source != target else { return false }

        if abs(source.count - target.count) == 1 {
            let longer = source.count > target.count ? source : target
            let shorter = source.count > target.count ? target : source
            for removedIndex in longer.indices {
                var edited = longer
                edited.remove(at: removedIndex)
                if edited == shorter { return true }
            }
            return false
        }

        guard source.count == target.count else { return false }
        let differences = source.indices.filter { source[$0] != target[$0] }
        if differences.count == 1,
           let index = differences.first {
            return keyboardNeighbors[source[index], default: ""].contains(target[index])
        }
        if differences.count == 2 {
            let first = differences[0]
            let second = differences[1]
            return second == first + 1
                && source[first] == target[second]
                && source[second] == target[first]
        }
        return false
    }

    static func singleEditCorrectionKeys(for input: String) -> [String] {
        let source = Array(normalize(input))
        guard source.count >= 4, source.count <= 24 else { return [] }
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz")
        var corrections: Set<String> = []

        for index in source.indices {
            var deletion = source
            deletion.remove(at: index)
            corrections.insert(String(deletion))

            for replacement in keyboardNeighbors[source[index], default: ""] {
                var substitution = source
                substitution[index] = replacement
                corrections.insert(String(substitution))
            }

            if index + 1 < source.count, source[index] != source[index + 1] {
                var transposition = source
                transposition.swapAt(index, index + 1)
                corrections.insert(String(transposition))
            }
        }

        for insertionIndex in 0...source.count {
            for character in alphabet {
                var insertion = source
                insertion.insert(character, at: insertionIndex)
                corrections.insert(String(insertion))
            }
        }

        corrections.remove(String(source))
        return corrections.sorted()
    }

    static func segments(for input: String) -> [String] {
        let characters = Array(normalize(input))
        guard !characters.isEmpty else { return [] }
        var paths = Array<[String]?>(repeating: nil, count: characters.count + 1)
        paths[0] = []

        for start in 0..<characters.count {
            guard let path = paths[start] else { continue }
            let maximumEnd = min(characters.count, start + 6)
            for end in (start + 1)...maximumEnd {
                let syllable = String(characters[start..<end])
                guard commonSyllables.contains(syllable) else { continue }
                let candidate = path + [syllable]
                if let existing = paths[end] {
                    if isPreferred(candidate, over: existing) {
                        paths[end] = candidate
                    }
                } else {
                    paths[end] = candidate
                }
            }
        }

        if let complete = paths[characters.count] { return complete }
        guard let coveredLength = (1..<characters.count).reversed().first(where: { paths[$0] != nil }),
              let covered = paths[coveredLength]
        else { return splitIncompleteInitials(String(characters)) }
        return covered + splitIncompleteInitials(String(characters[coveredLength...]))
    }

    static func hasCompleteSyllableEnding(_ input: String) -> Bool {
        commonSyllables.contains { input.hasSuffix($0) }
    }

    private static func isPreferred(_ candidate: [String], over existing: [String]) -> Bool {
        if candidate.count != existing.count { return candidate.count < existing.count }
        for (new, old) in zip(candidate, existing) where new != old {
            return new.count > old.count
        }
        return false
    }

    private static func splitIncompleteInitials(_ input: String) -> [String] {
        let characters = Array(input)
        let consonants = Set("bcdfghjklmnpqrstvwxyz")
        guard !characters.isEmpty, characters.allSatisfy({ consonants.contains($0) }) else {
            return input.isEmpty ? [] : [input]
        }
        var result: [String] = []
        var index = 0
        while index < characters.count {
            if index + 1 < characters.count {
                let pair = String(characters[index...index + 1])
                if pair == "zh" || pair == "ch" || pair == "sh" {
                    result.append(pair)
                    index += 2
                    continue
                }
            }
            result.append(String(characters[index]))
            index += 1
        }
        return result
    }

    private static let keyboardNeighbors: [Character: String] = [
        "q": "wa", "w": "qeas", "e": "wrsd", "r": "etdf", "t": "ryfg",
        "y": "tugh", "u": "yihj", "i": "uojk", "o": "ipkl", "p": "ol",
        "a": "qwsz", "s": "weadzx", "d": "erfsxc", "f": "rtgdvc",
        "g": "tyfhvb", "h": "yugjbn", "j": "uihknm", "k": "iojml", "l": "opk",
        "z": "asx", "x": "zsdc", "c": "xdfv", "v": "cfgb", "b": "vghn",
        "n": "bhjm", "m": "njk",
    ]

    private static let chinesePunctuation: [String: String] = [
        ",": "，", ".": "。", "/": "、", "?": "？",
        ";": "；", ":": "：", "!": "！", "\\": "、",
        "(": "（", ")": "）", "[": "【", "]": "】",
        "{": "｛", "}": "｝", "<": "《", ">": "》",
        "\"": "“", "'": "‘", "`": "·", "~": "～",
        "-": "—", "_": "——", "^": "……", "$": "￥",
        "@": "＠", "#": "＃", "%": "％", "&": "＆",
        "*": "×", "+": "＋", "=": "＝", "|": "｜",
    ]

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
