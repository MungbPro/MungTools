# 下载与安装熊梦白 AI 工具箱

[English](DOWNLOAD.md) · [返回项目介绍](../README.zh-CN.md) · [关注我-熊梦白](https://x.com/mungbpro)

<img src="images/app-icon.png" alt="熊梦白 AI 工具箱应用图标" width="112">

**Apple 公证尚未完成。当前应用下载包可能触发 macOS 安全提示。**

| 检查项 | 当前状态 |
| --- | --- |
| Mac 兼容性 | Apple 芯片，macOS 14 或更新版本 |
| 公开应用的签名 | 临时签名，非 Developer ID 分发签名 |
| Apple 公证 | 尚未完成 |
| 目前推荐的安装方式 | 按下方说明从公开源码构建 |

校验和、代码签名、构建测试通过，都不能证明应用没有恶意软件。Apple 公证服务会扫描提交的软件，并为 Gatekeeper 签发公证票据，详见 [Apple Developer ID 说明](https://developer.apple.com/developer-id/)。

## 从源码构建

公证完成前，推荐使用此方式。需要包含 Swift 的 Apple 命令行工具。运行前请检查源码；本地构建也不等于 Apple 恶意软件扫描。

**在 Mac 上用 Codex？复制这段话：**

```text
请在这台 Mac 安装 https://github.com/MungbPro/MungTools 的 Mung Tools。先阅读源码和安装说明，在本机构建并打开。保留已有配置及正在运行的工具，不要执行我的工具脚本，也不要关闭 macOS 安全保护。
```

**也可以自己运行：**

```sh
git clone https://github.com/MungbPro/MungTools.git
cd MungTools
./install.sh
```

安装脚本会构建应用，将它放入 `~/Applications` 并打开。你会在菜单栏看到工具箱图标，点击即可打开工具列表。

也可以[下载源码 ZIP](https://github.com/MungbPro/MungTools/archive/refs/heads/main.zip)，解压后在文件夹内运行 `./install.sh`。更多内容见[构建说明](USAGE.zh-CN.md#开发)。

## 关于应用下载包

[开发预览版 v1.3.1 — 未通过 Apple 公证](https://github.com/MungbPro/MungTools/releases/tag/v1.3.1)。

这是开发预览版，并非经过验证的稳定下载版本。它包含新应用图标和 DMG 安装包；Apple 公证仍未完成。

目前的应用下载包仍有上表列出的限制。仅改为 DMG 或 ZIP 格式不会改变公证状态。完成公证后，本页会直接链接到已公证的下载包。

ZIP 版本：解压后，将 **Mung Tools.app** 放入**应用程序**。DMG 版本：打开磁盘映像，将 **Mung Tools.app** 拖入**应用程序**，推出磁盘映像，再打开已安装的应用。运行预构建版本无需 Python、Node.js 或 Xcode。

## macOS 提示是什么意思

| 提示内容 | 建议操作 |
| --- | --- |
| Apple 无法验证开发者，或无法检查是否包含恶意软件 | 当前版本缺少相应的分发验证。请从源码构建，或等待已公证版本。此提示并不能证明应用安全。 |
| 应用会损坏电脑，或包含恶意软件 | 不要打开。移除这份文件，并在 Issue 中报告准确提示。 |
| 应用已损坏，或被修改 | 不要绕过提示。移除这份文件并报告；损坏或被改动的下载文件需要检查。 |

详见 [Apple 对这些提示的解释](https://support.apple.com/en-us/102445)。本项目不建议通过关闭 Gatekeeper 或移除隔离属性来安装。

## 添加第一个工具

点击**导入 → 复制 Codex 提示词**，粘贴到能够访问你选定文件夹的 Codex，并核对脚本配对。也可以点击**新建**手动添加。导入不会启动工具，需要时再点击**启动**。

需要帮助？欢迎[提交 Issue](https://github.com/MungbPro/MungTools/issues)，说明 macOS 版本和提示文字。请勿附上私人项目文件或凭据。

[关注我-熊梦白 · X：@mungbpro](https://x.com/mungbpro)
