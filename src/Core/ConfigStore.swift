import Foundation

/// 统一配置的读写入口。
///
/// 设计要点：
/// - 文件损坏时**备份**而不是静默丢弃，用户能找回配置。
/// - 写入用原子替换（`.atomic`），避免断电写坏文件。
/// - 变更通过 `onChange` 通知，各 Feature 收到后热更新，无需重启。
///
/// 线程模型：本类不加锁。设计上只在主线程使用（配置窗口/菜单都在主线程），
/// 跨进程并发写时以最后写入者胜出；若将来出现后台写入，需要补加锁。
final class ConfigStore {
    static let shared = ConfigStore()

    /// 默认路径：~/.config/tony-toy/config.json
    static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/tony-toy/config.json")
    }

    private let fileURL: URL

    /// 配置变更回调。在调用 `updateFeature` 的线程上同步触发（当前即主线程）。
    var onChange: ((TonyToyConfig) -> Void)?

    init(fileURL: URL = ConfigStore.defaultURL) {
        self.fileURL = fileURL
    }

    /// 读取配置。文件不存在或损坏时返回默认值，保证启动永远不失败。
    ///
    /// 签名保留 `throws` 是为了将来版本迁移/校验真正需要上报错误时不必改调用方；
    /// 当前实现不会抛错。如第一阶段结束仍无抛错场景，应降级为不抛错的方法。
    func load() throws -> TonyToyConfig {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .default
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            dbg("配置读取失败，使用默认值: \(error)")
            return .default
        }

        do {
            return try JSONDecoder().decode(TonyToyConfig.self, from: data)
        } catch {
            // TODO(Task 6): 这里只回退到默认值，空 features 直接进入运行时会丢掉
            // 各功能的内置默认项。应改由 FeatureRegistry.startAll() 在启动时补齐全
            // 部已注册 Feature 的默认项；Task 3 尚无法依赖它，故不在此引入。
            dbg("配置解析失败，已备份并回退默认值: \(error)")
            backupCorruptedFile()
            return .default
        }
    }

    /// 写入配置。调用方负责保证 config 合法。
    ///
    /// 不触发 `onChange`：这里是纯落盘，批量/迁移场景不应触发全量热更新。
    /// 需要「落盘 + 通知」时用 `updateFeature`。
    func save(_ config: TonyToyConfig) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: fileURL, options: .atomic)

        dbg("配置已保存到 \(fileURL.path)")
    }

    /// 更新单项功能配置并落盘 + 通知。
    ///
    /// 先读后写：未在 `mutate` 中触碰的字段保持磁盘上的最新值，
    /// 不会用调用方手里的旧对象整份覆盖。
    func updateFeature(_ featureID: String, _ mutate: (inout FeatureConfig) -> Void) throws {
        var config = try load()
        var feature = config.features[featureID] ?? FeatureConfig()
        mutate(&feature)
        config.features[featureID] = feature
        try save(config)
        onChange?(config)
    }

    // MARK: - 私有

    /// 把损坏的文件挪到同目录的 `.corrupted.<时间戳>`，保留现场供人工排查。
    /// 备份失败（如目录只读）也不阻塞启动，只是现场会丢失。
    private func backupCorruptedFile() {
        let timestamp = Int(Date().timeIntervalSince1970)
        let backup = fileURL.deletingLastPathComponent()
            .appendingPathComponent("\(fileURL.lastPathComponent).corrupted.\(timestamp)")
        try? FileManager.default.moveItem(at: fileURL, to: backup)
    }
}
