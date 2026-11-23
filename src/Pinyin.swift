import Foundation

/// 常见多音字（只收读音不同、会影响拼音字母的字）
enum Polyphone {
    static let table: [Character: [String]] = [
        "重": ["zhong", "chong"],
        "行": ["xing", "hang"],
        "长": ["chang", "zhang"],
        "乐": ["le", "yue"],
        "了": ["le", "liao"],
        "和": ["he", "huo", "hu"],
        "还": ["hai", "huan"],
        "会": ["hui", "kuai"],
        "单": ["dan", "shan", "chan"],
        "查": ["cha", "zha"],
        "区": ["qu", "ou"],
        "仇": ["chou", "qiu"],
        "解": ["jie", "xie"],
        "沈": ["shen", "chen"],
        "折": ["zhe", "she"],
        "参": ["can", "shen", "cen"],
        "差": ["cha", "chai", "ci"],
        "调": ["diao", "tiao"],
        "弹": ["dan", "tan"],
        "都": ["dou", "du"],
        "度": ["du", "duo"],
        "恶": ["e", "wu"],
        "给": ["gei", "ji"],
        "更": ["geng", "jing"],
        "角": ["jiao", "jue"],
        "省": ["sheng", "xing"],
        "石": ["shi", "dan"],
        "宿": ["su", "xiu"],
        "汤": ["tang", "shang"],
        "提": ["ti", "di"],
        "曾": ["ceng", "zeng"],
        "血": ["xue", "xie"],
        "似": ["si", "shi"],
        "什": ["shen", "shi"],
        "佛": ["fo", "fu"],
        "薄": ["bao", "bo"],
        "便": ["bian", "pian"],
        "屏": ["ping", "bing"],
        "剥": ["bao", "bo"],
        "泊": ["bo", "po"],
        "藏": ["cang", "zang"],
        "刹": ["cha", "sha"],
        "禅": ["chan", "shan"],
        "颤": ["chan", "zhan"],
        "称": ["cheng", "chen"],
        "乘": ["cheng", "sheng"],
        "盛": ["sheng", "cheng"],
        "畜": ["chu", "xu"],
        "传": ["chuan", "zhuan"],
        "大": ["da", "dai"],
        "塞": ["sai", "se"],
        "色": ["se", "shai"],
        "厦": ["sha", "xia"],
        "杉": ["shan", "sha"],
        "术": ["shu", "zhu"],
        "数": ["shu", "shuo"],
        "说": ["shuo", "shui"],
        "缩": ["suo", "su"],
        "拓": ["tuo", "ta"],
        "吓": ["xia", "he"],
        "削": ["xiao", "xue"],
        "校": ["xiao", "jiao"],
        "钥": ["yao", "yue"],
        "遗": ["yi", "wei"],
        "轧": ["zha", "ya"],
        "着": ["zhe", "zhao", "zhuo"],
        "仔": ["zi", "zai"]
    ]
}

/// 把应用名转成拼音全拼与首字母，多音字会产出多个变体
enum Pinyin {
    struct Result {
        let fulls: [String]
        let initials: [String]
    }

    private static let maxVariants = 24

    static func convert(_ text: String) -> Result {
        var fullCombos = [""]
        var initialCombos = [""]

        let words = text.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "_" || $0 == "." })
        for word in words {
            let piece = String(word)
            if piece.allSatisfy({ $0.isASCII }) {
                // 英文/数字单词：整体保留，首字母取第一个字母
                let latin = piece.lowercased().filter { $0.isLetter || $0.isNumber }
                fullCombos = expand(fullCombos, with: latin.isEmpty ? [] : [latin])
                if let first = latin.first(where: { $0.isLetter }) {
                    initialCombos = expand(initialCombos, with: [String(first)])
                }
            } else {
                // 含汉字：逐字转，多音字产生分支
                for character in piece {
                    let readings = readingsOf(character)
                    guard !readings.isEmpty else { continue }
                    fullCombos = expand(fullCombos, with: readings)
                    initialCombos = expand(initialCombos, with: readings.compactMap { $0.first.map(String.init) })
                }
                trim(&fullCombos)
                trim(&initialCombos)
            }
        }

        return Result(fulls: fullCombos.filter { !$0.isEmpty },
                      initials: initialCombos.filter { !$0.isEmpty })
    }

    private static func expand(_ prefixes: [String], with options: [String]) -> [String] {
        guard !options.isEmpty else { return prefixes }
        var result: [String] = []
        for prefix in prefixes {
            for option in options {
                result.append(prefix + option)
                if result.count >= maxVariants { return result }
            }
        }
        return result
    }

    private static func trim(_ list: inout [String]) {
        if list.count > maxVariants {
            list = Array(list.prefix(maxVariants))
        }
    }

    private static func readingsOf(_ character: Character) -> [String] {
        if let readings = Polyphone.table[character] {
            return readings
        }
        if character.isASCII {
            if character.isLetter || character.isNumber {
                return [String(character).lowercased()]
            }
            return []
        }
        let latin = toLatin(String(character)).filter { $0.isLetter }
        return latin.isEmpty ? [] : [latin]
    }

    private static func toLatin(_ text: String) -> String {
        let mutable = NSMutableString(string: text)
        CFStringTransform(mutable, nil, kCFStringTransformMandarinLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripDiacritics, false)
        return (mutable as String).lowercased()
    }
}
