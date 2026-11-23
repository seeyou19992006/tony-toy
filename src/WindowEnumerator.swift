import AppKit
import ApplicationServices

struct SwitchWindowInfo {
    let element: AXUIElement
    let title: String
    let minimized: Bool
}

/// 通过辅助功能 API 枚举应用的窗口（不需要屏幕录制权限）
enum WindowEnumerator {
    static func standardWindows(of pid: pid_t) -> [SwitchWindowInfo] {
        let app = AXUIElementCreateApplication(pid)

        // 某个应用无响应时不要卡住整个切换器
        AXUIElementSetMessagingTimeout(app, 0.25)

        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let list = value as? [AXUIElement] else {
            return []
        }

        // 一次调用取回全部属性：逐个属性取会多出 4 倍 IPC 往返
        let attributes = [kAXSubroleAttribute, kAXTitleAttribute,
                          kAXMinimizedAttribute, kAXSizeAttribute] as [String]

        var result: [SwitchWindowInfo] = []
        result.reserveCapacity(list.count)

        for element in list {
            var values: CFArray?
            guard AXUIElementCopyMultipleAttributeValues(element, attributes as CFArray, [], &values) == .success,
                  let array = values as? [Any],
                  array.count == 4 else { continue }

            // 只保留标准窗口，排除面板、提示框、工具栏这类
            guard let subrole = array[0] as? String,
                  subrole == kAXStandardWindowSubrole else { continue }

            // 跳过尺寸为零的隐藏窗口
            var size = CGSize.zero
            if CFGetTypeID(array[3] as CFTypeRef) == AXValueGetTypeID() {
                AXValueGetValue(array[3] as! AXValue, .cgSize, &size)
            }
            guard size.width > 1, size.height > 1 else { continue }

            let rawTitle = (array[1] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let minimized = (array[2] as? Bool) ?? false

            result.append(SwitchWindowInfo(element: element,
                                           title: rawTitle.isEmpty ? "未命名窗口" : rawTitle,
                                           minimized: minimized))
        }

        return result
    }
}
