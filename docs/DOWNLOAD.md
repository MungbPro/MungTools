# Download & install Mung Tools

[简体中文](DOWNLOAD.zh-CN.md) · [Back to Mung Tools](../README.md) · [Mung on X](https://x.com/mungbpro)

<img src="images/app-icon.png" alt="Mung Tools app icon" width="112">

**Apple notarization is not complete. Current binary downloads can trigger a macOS security warning.**

| Check | Current status |
| --- | --- |
| Mac compatibility | Apple Silicon, macOS 14 or later |
| Public app signature | Ad-hoc; not a Developer ID distribution signature |
| Apple notarization | Not completed |
| Recommended installation for now | Build from the published source below |

A checksum, code signature, or passing build test does not establish that an app is malware-free. Apple’s notarization service scans submitted software and issues a ticket for Gatekeeper; see [Apple’s Developer ID guide](https://developer.apple.com/developer-id/).

## Build from source

This is the recommended route while notarization is unfinished. You need Apple’s Command Line Tools with Swift. Review the source before running it; a local build is not an Apple malware scan.

**Using Codex on your Mac? Paste this:**

```text
Install Mung Tools from https://github.com/MungbPro/MungTools on this Mac. Read its source and installation instructions, build it locally, and open it. Preserve my existing configuration and running tools. Do not run my tool scripts or disable macOS security.
```

**Or run these commands yourself:**

```sh
git clone https://github.com/MungbPro/MungTools.git
cd MungTools
./install.sh
```

The installer builds the app, places it in `~/Applications`, and opens it. You will see Mung Tools’ icon in the menu bar. Click it to open the tool list.

You can also [download the source ZIP](https://github.com/MungbPro/MungTools/archive/refs/heads/main.zip), unzip it, and run `./install.sh` from that folder. See [build details](USAGE.md#development).

## About the downloadable app

[Development preview v1.3.1 — NOT Apple-notarized](https://github.com/MungbPro/MungTools/releases/tag/v1.3.1).

This is a development pre-release, not a verified stable download. It includes the new app icon and DMG installer; Apple notarization is still pending.

Prebuilt downloads currently have the limitations listed above. A DMG or ZIP file alone does not change the notarization status. When a notarized download is available, this page will link to it directly.

For a ZIP release, unzip it and move **Mung Tools.app** into **Applications**. For a DMG release, open the disk image and drag **Mung Tools.app** to **Applications**. Eject the disk image, then open the installed app. No Python, Node.js, or Xcode is needed to run a prebuilt app.

## If macOS shows a warning

| The alert says… | What to do |
| --- | --- |
| Apple cannot verify the developer or check for malware | The current release lacks the required distribution verification. Use the source build above or wait for a notarized release. This warning does not establish that the app is safe. |
| The app will damage your computer or contains malware | Do not open it. Remove that copy and report the exact message in an issue. |
| The app is damaged or has been modified | Do not override the warning. Remove that copy and report it; a corrupt or altered download needs investigation. |

See [Apple’s explanation of these alerts](https://support.apple.com/en-us/102445). This project does not recommend disabling Gatekeeper or removing quarantine metadata to install the app.

## Add your first tools

Click **Import → Copy Codex Prompt**, paste into Codex with access to the folders you choose, and review its script pairs. Or click **New** to add a tool manually. Importing never starts a tool; click **Start** when ready.

Need help? [Open an issue](https://github.com/MungbPro/MungTools/issues) with your macOS version and the alert text. Do not include private project files or credentials.

[More About Mung · @mungbpro on X](https://x.com/mungbpro)
