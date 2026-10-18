# 安装熊梦白 AI 工具箱

[English](DOWNLOAD.md) · [返回项目介绍](../README.zh-CN.md) · [关注我-熊梦白](https://x.com/mungbpro)

<img src="images/app-icon.png" alt="熊梦白 AI 工具箱应用图标" width="112">

## 运行一条命令

在使用 **macOS 14 或更新版本的 Apple 芯片 Mac** 上，把下面这行粘贴到**终端**：

```sh
/bin/bash -o pipefail -c 'curl -fsSL https://raw.githubusercontent.com/MungbPro/MungTools/main/install-from-source.sh | /bin/bash'
```

[运行前可先查看安装脚本](../install-from-source.sh)。

脚本会从本项目的 GitHub Release 下载固定校验和的源码包，在你的 Mac 上编译，并安装到 `~/Applications/Mung Tools.app`。随后打开应用；点击菜单栏图标即可看到工具列表。

**第一次安装？** 需要包含 Swift 的 Apple 命令行工具。若尚未安装，脚本会打开 Apple 官方安装程序并停止。安装完成后，再运行同一条命令即可。无需完整 Xcode、Python、Node.js 或 API Key。

已有配置和正在运行的工具会保留。安装脚本不会执行你的工具脚本，也不会退出正在运行的工具箱。若工具箱已经打开，当前会话会继续运行，更新在下次打开时生效。

## 想让 Codex 帮你安装？

把这段话粘贴到 Mac 上的 Codex：

```text
请在这台 Mac 安装 https://github.com/MungbPro/MungTools 的 Mung Tools。先阅读安装说明和 install-from-source.sh，再使用源码安装脚本。保留已有配置及正在运行的工具，不要执行我的工具脚本、退出正在运行的工具箱或关闭 macOS 安全保护。若缺少 Apple 命令行工具，请帮我安装，并在完成后继续。
```

## 也可以下载源码

[下载源码 ZIP](https://github.com/MungbPro/MungTools/archive/refs/heads/main.zip)，解压后，在已安装 Apple 命令行工具的情况下，从该文件夹运行 `./install.sh`。更多内容见[构建说明](USAGE.zh-CN.md#开发)。

## 为什么使用源码安装？

之前的预构建应用下载包**尚未通过 Apple 公证**，可能被 macOS 阻止打开。上面的安装方式会从公开源码在本机构建应用，不会移除隔离属性或关闭 Gatekeeper，也不代表 Apple 恶意软件扫描或公证通过。

正常的直接下载应用需要 Developer ID 签名和 Apple 公证，这种分发方式目前尚未就绪。换图标或把同一个应用改成 DMG，都不能代替这些步骤。详见 [Apple Developer ID 说明](https://developer.apple.com/developer-id/)。

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
