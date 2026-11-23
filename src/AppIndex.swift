import AppKit

struct AppEntry: Hashable {
    let name: String
    let bundleID: String
    let url: URL
    var pinyinFulls: [String] = []
    var pinyinInitials: [String] = []

    static func == (lhs: AppEntry, rhs: AppEntry) -> Bool {
        lhs.bundleID == rhs.bundleID
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(bundleID)
    }
}

/// 扫描并缓存本机应用列表
final class AppIndex {
    private(set) var entries: [AppEntry] = []

    private let roots = [
        "/Applications",
        "/System/Applications",
        NSString(string: "~/Applications").expandingTildeInPath
    ]

    func scan() {
        var seen = Set<String>()
        var result: [AppEntry] = []

        for root in roots {
            guard let children = try? FileManager.default.contentsOfDirectory(atPath: root) else { continue }
            for child in children.sorted() {
                let fullPath = (root as NSString).appendingPathComponent(child)
                if child.hasSuffix(".app") {
                    appendEntry(at: fullPath, seen: &seen, into: &result)
                } else if !child.hasPrefix(".") {
                    // 一层子目录，例如 /System/Applications/Utilities
                    guard let inner = try? FileManager.default.contentsOfDirectory(atPath: fullPath) else { continue }
                    for item in inner.sorted() where item.hasSuffix(".app") {
                        appendEntry(at: (fullPath as NSString).appendingPathComponent(item),
                                    seen: &seen, into: &result)
                    }
                }
            }
        }

        entries = result.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func appendEntry(at path: String, seen: inout Set<String>, into result: inout [AppEntry]) {
        guard let entry = makeEntry(at: path), seen.insert(entry.bundleID).inserted else { return }
        result.append(entry)
    }

    private func makeEntry(at path: String) -> AppEntry? {
        let url = URL(fileURLWithPath: path)
        let bundle = Bundle(url: url)
        let info = bundle?.infoDictionary

        guard let bundleID = (info?["CFBundleIdentifier"] as? String) ?? bundle?.bundleIdentifier else {
            return nil
        }
        let name = (info?["CFBundleDisplayName"] as? String)
            ?? (info?["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent

        let pinyin = Pinyin.convert(name)
        return AppEntry(name: name, bundleID: bundleID, url: url,
                        pinyinFulls: pinyin.fulls, pinyinInitials: pinyin.initials)
    }

    /// 精确 > 前缀 > 包含 > 首字母缩写 > 字母子序列
    func search(_ query: String) -> [AppEntry] {
        let keyword = query.trimmingCharacters(in: .whitespaces)
        guard !keyword.isEmpty else { return entries }

        let lowered = keyword.lowercased()
        var scored: [(entry: AppEntry, score: Int, order: Int)] = []

        for (order, entry) in entries.enumerated() {
            guard let score = matchScore(entry: entry, query: lowered) else { continue }
            scored.append((entry, score, order))
        }

        return scored.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.order < $1.order
        }.map(\.entry)
    }

    private func matchScore(entry: AppEntry, query: String) -> Int? {
        let lower = entry.name.lowercased()

        if lower == query { return 1000 }
        if lower.hasPrefix(query) { return 900 }
        if let range = lower.range(of: query) {
            let offset = lower.distance(from: lower.startIndex, to: range.lowerBound)
            return 800 - min(offset, 100)
        }
        if let result = subsequenceScore(query: query, in: entry.name) {
            // 查询每个字母都落在单词/驼峰边界上，就是首字母缩写
            return result.allBoundary ? 850 : 600 + min(result.score, 190)
        }

        // 拼音：丰声 -> fs、fengsheng；多音字会有多个变体
        for variant in entry.pinyinInitials where variant.hasPrefix(query) {
            return 850
        }
        for variant in entry.pinyinFulls where variant.hasPrefix(query) {
            return 840
        }
        for variant in entry.pinyinFulls where isSubsequence(query, of: variant) {
            return 600 + min(variant.count - query.count, 190)
        }
        return nil
    }

    /// 子序列打分：命中单词/驼峰边界、连续命中的加分，跨度和偏移扣分
    private func subsequenceScore(query: String, in name: String) -> (score: Int, allBoundary: Bool)? {
        let chars = Array(name)
        let needle = Array(query.lowercased())
        guard !chars.isEmpty, !needle.isEmpty else { return nil }

        let boundaries = boundaryIndices(chars)
        var matched = 0
        var score = 0
        var previous = -1
        var first = -1
        var boundaryHits = 0

        for index in 0..<chars.count {
            guard matched < needle.count else { break }
            let character = String(chars[index]).lowercased()
            guard character == String(needle[matched]) else { continue }

            if first < 0 { first = index }
            score += 10
            if boundaries.contains(index) {
                score += 25
                boundaryHits += 1
            }
            if previous == index - 1 { score += 15 }
            previous = index
            matched += 1
        }

        guard matched == needle.count, first >= 0 else { return nil }
        score -= (previous - first) / 2
        score -= first
        score += boundaryHits * 20
        return (score, boundaryHits == needle.count)
    }

    private func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var cursor = haystack.startIndex
        for character in needle {
            guard let found = haystack[cursor...].firstIndex(of: character) else { return false }
            cursor = haystack.index(after: found)
        }
        return true
    }

    /// 单词首字母、驼峰大写处、以及名字开头
    private func boundaryIndices(_ chars: [Character]) -> Set<Int> {
        var result = Set<Int>()
        guard !chars.isEmpty else { return result }
        result.insert(0)

        let separators: Set<Character> = [" ", "-", "_", "."]
        for index in 1..<chars.count {
            let previous = chars[index - 1]
            let current = chars[index]
            if separators.contains(current) { continue }
            if separators.contains(previous) {
                result.insert(index)
            } else if previous.isLowercase && current.isUppercase {
                result.insert(index)
            }
        }
        return result
    }
}
