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

        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let list = value as? [AXUIElement] else {
            return []
        }

        return list.compactMap { element in
            // 只保留标准窗口，排除面板、提示框、工具栏这类
            var subroleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subroleValue)
            guard let subrole = subroleValue as? String,
                  subrole == kAXStandardWindowSubrole else { return nil }

            // 跳过尺寸为零的隐藏窗口
            var sizeValue: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue)
            var size = CGSize.zero
            if let sizeValue {
                AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
            }
            guard size.width > 1, size.height > 1 else { return nil }

            var titleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue)
            let rawTitle = (titleValue as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            var minimizedValue: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXMinimizedAttribute as CFString, &minimizedValue)
            let minimized = (minimizedValue as? Bool) ?? false

            return SwitchWindowInfo(element: element,
                                    title: rawTitle.isEmpty ? "未命名窗口" : rawTitle,
                                    minimized: minimized)
        }
    }
}
