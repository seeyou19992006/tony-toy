import Foundation

/// 功能注册表。
///
/// 应用启动时注册所有 `Feature`，配置窗口和菜单都从这里读，
/// 避免各处硬编码——这是「新增功能只改 2 处」的那 2 处之一。
final class FeatureRegistry {
    static let shared = FeatureRegistry()

    private var features: [Feature] = []
    private let store: ConfigStore

    /// 启动时加载配置遇到的错误（目前只有 futureVersion）。
    /// 非 nil 时应用应显示告警，且不再写入配置。
    private(set) var loadIssue: ConfigError?

    init(store: ConfigStore = .shared) {
        self.store = store
    }

    // MARK: - 注册

    /// 注册一个功能。按注册顺序显示在侧边栏。
    ///
    /// 重复 id 会被忽略并记录日志——静默追加会导致侧边栏出现两个同名条目。
    func register(_ feature: Feature) {
        guard !features.contains(where: { $0.id == feature.id }) else {
            dbg("功能 \(feature.id) 重复注册，已忽略")
            return
        }
        features.append(feature)
    }

    var allFeatures: [Feature] { features }

    func feature(withID id: String) -> Feature? {
        features.first { $0.id == id }
    }

    // MARK: - 生命周期

    /// 应用启动时调用：加载配置并启动所有启用的功能。
    ///
    /// 配置损坏回退 `.default` 后 `features` 为空，此时**必须**补齐
    /// 每个已注册 Feature 的默认项——否则所有功能都会被当成「未配置」
    /// 而拿到错误的默认状态。
    ///
    /// **版本过高时不启动任何功能**：那意味着磁盘上是本应用读不懂的配置，
    /// 跑默认值等于给用户一个错误的工作状态。同时把 store 置为只读，
    /// 防止后续「整份 save」把新版本数据覆盖掉。
    func startAll() {
        do {
            let config = try store.load()
            applyAll(normalizedConfig(config))
        } catch let error as ConfigError {
            // 版本高于本应用：不能跑默认值（那是错的配置），
            // 也不能写入（会覆盖新版本数据）。记录问题，由界面提示用户。
            loadIssue = error
            store.isReadOnly = true
            dbg("配置加载失败，功能未启动: \(error)")
        } catch {
            // 其它错误不该出现（load 内部已兜底），保底跑默认值
            dbg("配置加载意外失败，使用默认值: \(error)")
            applyAll(normalizedConfig(.default))
        }

        // 配置外部变更时热更新
        store.onChange = { [weak self] newConfig in
            self?.applyAll(newConfig)
        }
    }

    /// 应用退出时调用
    func stopAll() {
        for feature in features {
            feature.stop()
        }
    }

    // MARK: - 内部

    private func applyAll(_ config: TonyToyConfig) {
        for feature in features {
            feature.apply(
                config.features[feature.id] ?? FeatureConfig(isEnabled: feature.defaultEnabled)
            )
        }
    }

    /// 补齐所有已注册 Feature 的默认项。
    ///
    /// 只补**缺失**的节点——已有配置优先，不能被默认值覆盖。
    /// 内部可见（非 private）是为了让测试能直接验证补齐逻辑。
    func normalizedConfig(_ config: TonyToyConfig) -> TonyToyConfig {
        var result = config
        for feature in features where result.features[feature.id] == nil {
            result.features[feature.id] = FeatureConfig(isEnabled: feature.defaultEnabled)
        }
        return result
    }
}
