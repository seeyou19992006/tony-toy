import Foundation
import GameController

/// 手柄按键追踪，供按键追踪面板使用。
///
/// 和 `HomeKeyBridge` 的分工：
/// - **Home** 走原始 HID（`HomeKeyBridge`）。GameController 在 app 转入后台后
///   收不到 Home——系统把这个键当作手势，只转给当前活跃的 app。实测：
///   大屏显示时能收到，收起后按几十次一条记录都没有。
/// - **其余按键**走 GameController，`shouldMonitorBackgroundEvents = true`
///   之后后台也能收到，不需要辅助功能，也不需要输入监控授权。
///
/// 生命周期：只在追踪面板打开时创建，关掉即销毁。GameController 进来会多占
/// 几 MB，给它常驻没意义。
final class GamepadTrace {
    /// (按键名, 设备名, 是否按下)
    var onButton: ((String, String, Bool) -> Void)?

    private var attached = Set<ObjectIdentifier>()

    func start() {
        // 11.3 才有这个开关。项目最低支持 11.0，低版本上拿不到后台按键，
        // 但也不至于崩——只是手柄追踪在后台无数据。
        if #available(macOS 11.3, *) {
            GCController.shouldMonitorBackgroundEvents = true
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(controllerConnected(_:)),
            name: .GCControllerDidConnect, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(controllerDisconnected(_:)),
            name: .GCControllerDidDisconnect, object: nil)

        for controller in GCController.controllers() {
            attach(controller)
        }
        GCController.startWirelessControllerDiscovery {}
    }

    func stop() {
        NotificationCenter.default.removeObserver(self)
        GCController.stopWirelessControllerDiscovery()

        for controller in GCController.controllers() {
            detach(controller)
        }
        attached.removeAll()
        onButton = nil
    }

    // MARK: - 接入 / 断开

    @objc private func controllerConnected(_ note: Notification) {
        guard let controller = note.object as? GCController else { return }
        attach(controller)
        onButton?("（接入）", controller.vendorName ?? "手柄", true)
    }

    @objc private func controllerDisconnected(_ note: Notification) {
        guard let controller = note.object as? GCController else { return }
        detach(controller)
        onButton?("（断开）", controller.vendorName ?? "手柄", false)
    }

    private func attach(_ controller: GCController) {
        let id = ObjectIdentifier(controller)
        guard !attached.contains(id) else { return }
        attached.insert(id)

        let device = controller.vendorName ?? "手柄"
        let profile = controller.physicalInputProfile

        // `buttons` 是 [名字: 按钮]，能查到元素的标识（GCInputButtonA 之类），
        // 用它才能给出稳定可读的名字。
        // `allButtons` 是 Set，没有 key，只用来兜底补几个 buttons 里没有的。
        var bound = Set<ObjectIdentifier>()

        for (key, button) in profile.buttons {
            bound.insert(ObjectIdentifier(button))
            if key == GCInputButtonHome { continue }
            bind(button, name: Self.displayName(key), device: device)
        }

        for button in profile.allButtons {
            guard !bound.contains(ObjectIdentifier(button)) else { continue }
            let name = button.localizedName ?? "未知键"
            if name == "Home" { continue }
            bind(button, name: name, device: device)
        }

        if let dpad = profile.dpads[GCInputDirectionPad] {
            bind(dpad.up, name: "↑", device: device)
            bind(dpad.down, name: "↓", device: device)
            bind(dpad.left, name: "←", device: device)
            bind(dpad.right, name: "→", device: device)
        }
    }

    private func detach(_ controller: GCController) {
        let id = ObjectIdentifier(controller)
        guard attached.contains(id) else { return }
        attached.remove(id)

        let profile = controller.physicalInputProfile
        for button in profile.allButtons {
            button.pressedChangedHandler = nil
        }
        if let dpad = profile.dpads[GCInputDirectionPad] {
            dpad.up.pressedChangedHandler = nil
            dpad.down.pressedChangedHandler = nil
            dpad.left.pressedChangedHandler = nil
            dpad.right.pressedChangedHandler = nil
        }
    }

    private func bind(
        _ button: GCControllerButtonInput, name: String, device: String
    ) {
        button.pressedChangedHandler = {
            [weak self] (_: GCControllerButtonInput, _: Float, isPressed: Bool) in
            self?.onButton?(name, device, isPressed)
        }
    }

    // MARK: - 按键名

    /// GameController 的元素标识是 `GCInputButtonA` 这种字符串，直接显示不好读
    private static func displayName(_ key: String) -> String {
        switch key {
        case GCInputButtonA: return "A"
        case GCInputButtonB: return "B"
        case GCInputButtonX: return "X"
        case GCInputButtonY: return "Y"
        case GCInputLeftShoulder: return "L1 / LB"
        case GCInputRightShoulder: return "R1 / RB"
        case GCInputLeftTrigger: return "L2 / LT"
        case GCInputRightTrigger: return "R2 / RT"
        case GCInputLeftThumbstick: return "L3（左摇杆按下）"
        case GCInputRightThumbstick: return "R3（右摇杆按下）"
        case GCInputButtonMenu: return "Menu"
        case GCInputButtonOptions: return "Options"
        // GCInputButtonShare 常量要 macOS 12，这里用它的原始值，避免抬高门槛
        case "Button Share": return "Share"
        case GCInputDirectionPad: return "方向键"
        default: return key
        }
    }
}
