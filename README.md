# TonyToy 🚀

TonyToy 是一款轻量级的 macOS 效率工具，通过底层事件拦截提供强大的按键映射和鼠标功能扩展。

## 主要功能

- **鼠标侧键层**: 通过侧键实现音量调节等扩展功能。
- **Caps Lock 键层**: 重新映射 Caps Lock 键，提高编码和快捷键使用效率。
- **全局快捷键层**: 提供高度可定制的全局快捷键。
- **本地化存储**: 状态自动保存，重启无忧。
- **轻量稳定**: 使用原生 Swift 编写，不依赖 Xcode 工程，支持 Apple Silicon。

## 快速安装 (对于用户)

由于应用采用自签名分发，首次安装请遵循以下步骤：

1. **下载**: 从 Release 页面下载最新的 `TonyToy.dmg`。
2. **安装**: 将 `TonyToy.app` 拖入 **应用程序 (Applications)** 文件夹。
3. **解除隔离**: 打开“终端” (Terminal.app)，运行以下命令：
   ```bash
   sudo xattr -cr /Applications/TonyToy.app
   ```
4. **权限授权**: 启动应用，并在弹出的系统提示中授予“辅助功能”权限。

---

## 开发与构建 (对于开发者)

本项目使用 `just` 作为任务管理器。请确保已安装 `brew install just`。

### 基础命令

| 命令 | 描述 |
| :--- | :--- |
| `just` | 列出所有可用命令 |
| `just build` | 编译 Apple Silicon (.app) |
| `just package` | 签名并打包为 .dmg |
| `just release` | **一键发布** (编译 + 打包) |
| `just test` | 运行单元测试 |
| `just clean` | 清理构建产物 |

### 签名配置 (SSH/远程环境)

本项目支持完全脱离 UI 交互的签名流程：

1. **初始化证书**: `just setup-sign` (生成并导入自签名证书)
2. **解锁环境**: `just unlock` (SSH 会话必备，授权 codesign 访问钥匙串)
3. **打包**: `just release`

### 目录结构

- `src/`: Swift 源代码
- `scripts/`: 构建、打包、清理等核心脚本
- `resources/`: 应用图标及配置资源
- `dist/`: 构建产物输出目录
- `tests/`: 测试脚本及资源

---

## 许可证

[MIT License](LICENSE)
