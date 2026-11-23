# TonyToy 项目长期约定

## 构建与安装流程（老孙 2026-11-23 明确要求）
**每次打包完成后，必须安装到 `/Applications` 并重启程序，不要只交付 dmg/app 就结束。**

标准动作（二选一，优先第一条）：
- `just release` 之后执行 `just install`
- 或一次跑完：`just release install`

`just install`（`scripts/install.sh`）做的事：结束旧进程 → `ditto` 到暂存目录再替换 `/Applications/TonyToy.app`（保留签名）→ `codesign --verify` 校验 → `open -a` 启动 → 确认新 PID。

## 项目结构要点
- 纯 Swift + `just`，**没有 Xcode 工程**，`scripts/build.sh` 用 `swiftc -O -whole-module-optimization -target arm64-apple-macosx11.0` 直接汇编 38 个源文件。
- 配置集中在 `scripts/developer-settings.sh`，本地覆盖放 `developer-settings.local.sh`。
- 签名身份固定为 `TonyToy Local Sign`（自签名），密钥链 id `1126749BD4D15A37C1301EA622E650CE296CBF52`。
  **签名必须稳定**，否则每次重编译都会丢辅助功能权限。
- 产物：`dist/build/TonyToy.app`、`dist/package/TonyToy-<version>.dmg`、`dist/TonyToy`（软链）。

## 应用图标（2026-11-23 换成魔方）
- 源文件 `resources/AppIcon.svg`，生成脚本 `scripts/make-icon.py`，命令 `just icon`（`--theme charcoal|coral` 切配色，`--png` 只出预览）。
- 投影：观察者右前上方（PHI=32° 绕 Y、THETA=31° 俯角）的**正交投影**，两斜轴不对称，比严格等轴测更像实拍。
- 几何：三面各 3×3 共 27 块，缝隙约 8% 块宽（GAP=5.8px @1024），圆角 12%，底座 n=5 超椭圆。
- 配色：`plum`（当前，紫底+白/橙/绿）、`charcoal`（白/红/蓝经典）、`coral`（橙底，橙面会糊）。
- 渲染链路：SVG → Chrome headless（`--default-background-color=00000000`）→ PIL LANCZOS 出 10 档 → `iconutil -c icns`。

## 菜单栏图标（托盘）
- `scripts/make-status-icon.py` 生成 `resources/StatusIcon.png`(18) 与 `@2x`(36)，纯黑+alpha 的**模板图**。
- 18pt 装不下 27 格，只表现**三个面**（每面一块），三面之间留透明缝。按 3×3 做过，18px 会糊成噪点。
- 代码：`main.swift` `setupStatusItem()` 用 `NSImage(named: "StatusIcon")` + `isTemplate = true`。
- **取舍**：原来的喇叭图标会随音量变化，现在固定魔方，音量改成按钮 tooltip 显示（`onVolumeChanged`）。

## 踩过的坑
- **图标缝隙算错**：`da = GAP/(CUBE*scale)` 里 `CUBE` 重复除了一次，实际缩进只有 0.02px，
  所谓「缝隙」全是圆角退缩出来的。`scale` 本身已是「归一化→像素」比例，正确写法是 `da = GAP/scale`。
- **正交投影退化**：用 `RY=38°, RX=26°` 的旋转矩阵时，立方体一条棱几乎正对视线，投影成一个点，
  顶面和侧面挤在一起，表现为「块翘起」。改两斜轴不对称的正交投影才解决。
- **`show_widget` 里的 `<img>` 读不了 `/tmp`**：只重写工作区内的路径，候选图要放项目目录。
- `set -euo pipefail` 下不要用 `cmd | grep -q` 判断存在性：grep 提前退出 → SIGPIPE → 管道返回 141 → 判断恒假。
  （2026-11-23 修过一次，见 `build.sh` 签名检测。）
- `hdiutil create -volname` 已废弃（仅警告，未改）。
- `src/main.swift:25` `Activator()` 临时对象立即释放导致 weak 引用必为 nil（未修）。
