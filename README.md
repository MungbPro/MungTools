[Install Mung Tools](docs/DOWNLOAD.md)

```sh
/bin/bash -o pipefail -c 'curl -fsSL https://raw.githubusercontent.com/MungbPro/MungTools/main/install-from-source.sh | /bin/bash'
```

Paste into **Terminal** to download the source, build it on your Mac, and install it in `~/Applications`. [Review the installer](install-from-source.sh) · [Download source instead](https://github.com/MungbPro/MungTools/archive/refs/heads/main.zip).

Requires **Apple Silicon and macOS 14+**. If Apple’s Command Line Tools are missing, the script opens Apple’s installer; finish it, then run the command again. Direct app downloads await Apple notarization; this command builds locally and keeps macOS security settings enabled.

# Mung Tools

**Your local tools. One small menu-bar app.**

[简体中文](README.zh-CN.md) · [Follow Mung on X · @mungbpro](https://x.com/mungbpro)

<img src="docs/images/launcher-en.jpg" alt="Mung Tools with fictional demo tools, pinned favorites, and Start and End buttons" width="1100">

**macOS 14+ · Apple Silicon · English / 简体中文 · Free & open source**

Have a folder full of `Start.command` and `Stop.command` files? Give each tool a name, connect its scripts, and manage them here. Use Codex to help find and pair your scripts, or add them yourself.

## Start. End. Find it again.

- **Green Start, red End.** End stays gray until you start a tool. Start stays gray while it is active.
- **Pin your favorites.** Keep the tools you use most at the top. Search the rest.
- **Stay in the menu bar.** Click **×** to hide the window. Your tools keep running; click the menu-bar icon to return.
- **Bring your scripts.** Import configurations, choose executable files, or enter shell commands. Add a website and view logs when needed.
- **Choose your language.** Switch between English and Simplified Chinese with the globe button.

<table>
  <tr>
    <td width="50%"><img src="docs/images/running-en.jpg" alt="A fictional demo tool running, with Start disabled and End available"></td>
    <td width="50%"><img src="docs/images/launcher-zh-CN.jpg" alt="The Simplified Chinese interface with fictional demo tools"></td>
  </tr>
  <tr>
    <td align="center">Clear Start and End states</td>
    <td align="center">English and 简体中文 built in</td>
  </tr>
</table>

[Install Mung Tools](docs/DOWNLOAD.md)

## Get your tools in with Codex

1. Follow the [download and installation guide](docs/DOWNLOAD.md), then open Mung Tools.
2. Click **Import → Copy Codex Prompt**. Paste into Codex on your Mac and tell it which folders it may inspect.
3. Review the tools Codex pairs. It creates and opens an import file; your tools appear in Mung Tools. Click **Start** when ready.

<img src="docs/images/import-en.jpg" alt="Mung Tools import screen with a Copy Codex Prompt option and a file import option" width="1100">

Codex needs access to the folders you choose. This uses your existing Codex setup; Mung Tools needs no API key or connected account. Importing configurations does not run their commands. The [Codex import guide](docs/CODEX-IMPORT.md) explains the file format and discovery rules.

**Manual setup:** click **New** to choose scripts yourself, or use **Import → Choose File** for an existing configuration. See the [usage guide](docs/USAGE.md).

The installer needs Apple’s Command Line Tools with Swift; full Xcode, Python, and Node.js are not required. Your tools may have their own requirements. Existing configuration and running tools are preserved. If Mung Tools is already open, the update takes effect at its next launch. See the [installation guide](docs/DOWNLOAD.md).

**A few useful keys:** `⌘F` search · `⌘P` pin · `⌘K` actions · `⌘N` new tool · `⌘H` hide window.

All pictures use fictional demo tools. No personal projects, scripts, or configuration are included.

## A few things to know

Mung Tools runs the commands you choose. It does not scan your folders itself or check whether an external service is healthy. For commands that launch a separate app or background service, configure an End command. After relaunching Mung Tools, start the tool here before End becomes available again.

Configuration and logs stay on your Mac. Read the [usage guide](docs/USAGE.md) for command setup, stopping behavior, shortcuts, and data storage.

## Build it yourself

Requires Apple’s Command Line Tools with Swift, an Apple Silicon Mac, and macOS 14 or later.

```sh
git clone https://github.com/MungbPro/MungTools.git
cd MungTools
./install.sh
```

Or get the [source ZIP](https://github.com/MungbPro/MungTools/archive/refs/heads/main.zip), unzip it, and run `./install.sh` inside its folder. See [development notes](docs/USAGE.md#development) for tests and packaging.

## Made by Mung

Have an idea or found a bug? [Open an issue](https://github.com/MungbPro/MungTools/issues).

[More About Mung · @mungbpro on X](https://x.com/mungbpro) · [MIT license](LICENSE)

[Install Mung Tools](docs/DOWNLOAD.md)
