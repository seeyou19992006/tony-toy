import AppKit

struct AppEntry: Hashable {
    let name: String
    let bundleID: String
    let url: URL
    var alternateNames: [String] = []
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
    var pinyinMatchEnabled = true
    private var lastScanDate: Date?
    private static let minimumScanInterval: TimeInterval = 6 * 3600

    /// 系统应用的中文名不在自己的 Info.plist 里，系统 API 取不到，只能内置一份常见对照
    private static let chineseAliases: [String: String] = [
        "com.apple.finder": "访达",
        "com.apple.systempreferences": "系统设置",
        "com.apple.ActivityMonitor": "活动监视器",
        "com.apple.Terminal": "终端",
        "com.apple.mail": "邮件",
        "com.apple.iCal": "日历",
        "com.apple.Notes": "备忘录",
        "com.apple.Music": "音乐",
        "com.apple.Photos": "照片",
        "com.apple.calculator": "计算器",
        "com.apple.Dictionary": "词典",
        "com.apple.reminders": "提醒事项",
        "com.apple.Maps": "地图",
        "com.apple.FontBook": "字体册",
        "com.apple.Preview": "预览",
        "com.apple.TextEdit": "文本编辑",
        "com.apple.DiskUtility": "磁盘工具",
        "com.apple.ScreenCaptureUI": "截屏",
        "com.apple.MobileSMS": "信息",
        "com.apple.FaceTime": "FaceTime",
        "com.apple.Safari": "Safari",
        "com.apple.AppStore": "App Store"
    ]

    private let roots = [
        "/Applications",
        "/System/Applications",
        NSString(string: "~/Applications").expandingTildeInPath,
        "/System/Library/CoreServices"
    ]

    func scan(force: Bool = false) {
        if !force, !entries.isEmpty,
           let lastScanDate, Date().timeIntervalSince(lastScanDate) < Self.minimumScanInterval {
            return
        }

        var seen = Set<String>()
        var rawItems: [(name: String, bundleID: String, url: URL, names: [String])] = []

        for root in roots {
            guard let children = try? FileManager.default.contentsOfDirectory(atPath: root) else { continue }
            for child in children.sorted() {
                let fullPath = (root as NSString).appendingPathComponent(child)
                if child.hasSuffix(".app") {
                    autoreleasepool {
                        appendRaw(at: fullPath, seen: &seen, into: &rawItems)
                    }
                } else if !child.hasPrefix(".") {
                    // 一层子目录，例如 /System/Applications/Utilities
                    guard let inner = try? FileManager.default.contentsOfDirectory(atPath: fullPath) else { continue }
                    for item in inner.sorted() where item.hasSuffix(".app") {
                        autoreleasepool {
                            appendRaw(at: (fullPath as NSString).appendingPathComponent(item),
                                      seen: &seen, into: &rawItems)
                        }
                    }
                }
            }
        }

        // 只把所有程序名里出现的非多音字汉字一次性交给短命子进程转成拼音，
        // 转换完即丢弃子进程，主进程不加载也不缓存整个 ICU 拼音表。
        let extraReadings = resolveExtraPinyinReadings(for: rawItems.flatMap(\.names))

        let result: [AppEntry] = rawItems.map { item in
            var fulls: [String] = []
            var initials: [String] = []
            for candidate in item.names {
                let pinyin = Pinyin.convert(candidate, extraReadings: extraReadings)
                fulls += pinyin.fulls
                initials += pinyin.initials
            }
            return AppEntry(name: item.name, bundleID: item.bundleID, url: item.url,
                            alternateNames: Array(item.names.dropFirst()),
                            pinyinFulls: fulls, pinyinInitials: initials)
        }

        entries = result.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        lastScanDate = Date()
    }

    private func appendRaw(
        at path: String,
        seen: inout Set<String>,
        into result: inout [(name: String, bundleID: String, url: URL, names: [String])]
    ) {
        let url = URL(fileURLWithPath: path)
        let bundle = Bundle(url: url)
        let info = bundle?.infoDictionary

        // CoreServices 里混着 Dock 这类后台组件，只收有界面的
        if path.contains("/CoreServices/"), (info?["LSUIElement"] as? Bool) == true {
            return
        }

        guard let bundleID = (info?["CFBundleIdentifier"] as? String) ?? bundle?.bundleIdentifier,
              seen.insert(bundleID).inserted else {
            return
        }
        let name = (info?["CFBundleDisplayName"] as? String)
            ?? (info?["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent

        var names = [name]
        if let alias = Self.chineseAliases[bundleID], alias != name {
            names.append(alias)
        }
        result.append((name: name, bundleID: bundleID, url: url, names: names))
    }

    private func resolveExtraPinyinReadings(for names: [String]) -> [Character: String] {
        var uniqueChars = ""
        var seenChars = Set<Character>()
        for name in names {
            for ch in name where !ch.isASCII && Polyphone.table[ch] == nil && seenChars.insert(ch).inserted {
                uniqueChars.append(ch)
            }
        }
        guard !uniqueChars.isEmpty,
              let executable = Bundle.main.executablePath else { return [:] }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["--convert-pinyin"]
        let inPipe = Pipe()
        let outPipe = Pipe()
        process.standardInput = inPipe
        process.standardOutput = outPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            if let inputData = uniqueChars.data(using: .utf8) {
                inPipe.fileHandleForWriting.write(inputData)
            }
            try? inPipe.fileHandleForWriting.close()
            let outputData = outPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let dict = try JSONSerialization.jsonObject(with: outputData) as? [String: String] else {
                return [:]
            }
            var result: [Character: String] = [:]
            for (k, v) in dict {
                if let ch = k.first {
                    result[ch] = v
                }
            }
            return result
        } catch {
            return [:]
        }
    }

    /// 精确 > 前缀 > 包含 > 首字母缩写 > 字母子序列
    func search(_ query: String, preferred: Set<String> = []) -> [AppEntry] {
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
            // 同分时，已经开着窗口的应用优先
            let leftOpen = preferred.contains($0.entry.bundleID)
            let rightOpen = preferred.contains($1.entry.bundleID)
            if leftOpen != rightOpen { return leftOpen }
            return $0.order < $1.order
        }.map(\.entry)
    }

    private func matchScore(entry: AppEntry, query: String) -> Int? {
        var best: Int?
        for candidate in [entry.name] + entry.alternateNames {
            if let score = score(name: candidate, query: query) {
                best = max(best ?? 0, score)
            }
        }

        // 拼音：丰声 -> fs、fengsheng；多音字会有多个变体
        if pinyinMatchEnabled {
            for variant in entry.pinyinInitials where variant.hasPrefix(query) {
                best = max(best ?? 0, 850)
            }
            for variant in entry.pinyinFulls where variant.hasPrefix(query) {
                best = max(best ?? 0, 840)
            }
            for variant in entry.pinyinFulls where isSubsequence(query, of: variant) {
                best = max(best ?? 0, 600 + min(variant.count - query.count, 190))
            }
        }
        return best
    }

    /// 单个名字的匹配打分
    private func score(name: String, query: String) -> Int? {
        let lower = name.lowercased()

        if lower == query { return 1000 }
        if lower.hasPrefix(query) { return 900 }
        if let range = lower.range(of: query) {
            let offset = lower.distance(from: lower.startIndex, to: range.lowerBound)
            return 800 - min(offset, 100)
        }
        if let result = subsequenceScore(query: query, in: name) {
            // 查询每个字母都落在单词/驼峰边界上，就是首字母缩写
            return result.allBoundary ? 850 : 600 + min(result.score, 190)
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
