# Mung Tools usage guide

[README](../README.md) · [简体中文](USAGE.zh-CN.md) · [Mung on X](https://x.com/mungbpro)

## Install and macOS security

Read the [download and installation guide](DOWNLOAD.md) first. Current public binaries are ad-hoc signed and **not Apple-notarized**; they may be blocked by macOS. Source build instructions are available there. Build tests and checksums are not malware scans. Building locally does not notarize the app.

## Import tools with Codex

Choose **Import → Copy Codex Prompt**, paste into Codex on your Mac, and specify the folders it may inspect. Review its Start/End pairs before importing. Codex creates a UTF-8 `.mungtools` configuration and opens it with Mung Tools. You can also choose **Import → Choose File** manually.

The import adds tool configurations without running them or changing their scripts. It validates the entire file before saving. Re-importing the same `.mungtools` configuration skips exact duplicates; conflicting entries with the same ID are rejected. Existing tools are preserved. See the [Codex import guide](CODEX-IMPORT.md) for the schema and discovery rules.

This uses your existing Codex setup with local folder access. Mung Tools has no embedded AI service, Codex account connection, or API-key setting.

## Add a tool manually

1. Choose **New Tool** and enter a name.
2. Choose a Start script or enter a shell command.
3. Set the working directory. Choosing the first script fills an empty working directory with its containing folder.
4. Optionally choose an End script or command. Without one, Mung Tools can stop the process group it started and still owns in this session.
5. Optionally add an HTTP or HTTPS address, then save.

Scripts stay in their original locations. Saving or deleting a tool does not modify scripts or their permissions. Script files need executable permission and a valid interpreter line, such as `#!/bin/zsh`. Alternatively, choose **Shell command** and explicitly invoke an interpreter, for example:

```sh
/bin/zsh '/path/to/Start.command'
```

Shell commands run through `/bin/zsh -lc`. Use absolute paths or paths relative to the configured working directory. Commands run with your user’s permissions, so only add commands you trust.

Start never runs automatically when Mung Tools opens. Stop a managed process before editing its configuration. Unsaved drafts remain available during the current app session.

## Everyday controls

- Click the green **Start** button to start a tool. End is disabled until the tool has been started in this session.
- While active, Start is disabled and **End** is red. Both buttons are disabled while stopping.
- Click a row’s pin icon, or press **⌘P**, to keep a tool at the top. Pins persist across launches and configuration exports.
- Click the menu-bar icon to open or hide the window. Right-click it for quick actions.
- The top-right **×** only hides the window. It does not save a draft, stop tools, or quit Mung Tools.
- Use the globe button to choose English or Simplified Chinese. Names, paths, commands, and existing log output remain as entered.

## Keyboard shortcuts

Shortcuts apply while Mung Tools is focused.

| Shortcut | Action |
| --- | --- |
| ⌘F | Focus search |
| ↑ / ↓ | Select a tool |
| Return | Run the primary action shown in the footer |
| ⌘K | Show available actions |
| ⌘N | Add a tool |
| ⌘E | Edit the selected tool |
| ⌘P | Pin or unpin the selected tool |
| ⌘L | View logs |
| ⌘⇧X | Run End |
| ⌘Return | Save the editor |
| Escape | Go back, dismiss actions, or hide the window |
| ⌘H | Hide the window |
| ⌘Q | Quit |

## Status and stopping

| Status | Meaning |
| --- | --- |
| Ready | This session is not managing the tool. A service started elsewhere may still be running. |
| Running | The process started by Mung Tools has not exited. |
| Start command finished | Start exited successfully. A separately launched app or service may still be running. A configured End remains available in this session. |
| Needs attention | A command failed or needs checking. Open its logs for details. |

End first runs your configured command. On success, it terminates any remaining Start process group owned by this session. Without an End command, it sends TERM and waits. **Force Stop** is a separate action that requires confirmation; the app does not escalate automatically. If End fails, inspect the logs and retry it.

Commands that detach, open Terminal, or launch an external service need their own End command. Mung Tools does not infer which external process to stop. If several tools share one service, ending that service can affect them all.

Quitting offers to stop tools started in the current session. It does not automatically run End for tools never started here. Relaunching Mung Tools does not adopt old process IDs: Start is available again, and End becomes available after a new Start. Make your Start script handle an already-running service if needed. The displayed status describes command execution, not an external service health check.

## Local data and sharing

```text
~/Library/Application Support/MungTools/
  tools.json
  logs/<tool-id>.log
```

Configuration and logs stay on your Mac. Mung Tools does not sync them. Your configured commands may use the network, and their output is saved in local logs. Exported configurations contain command text and local paths; review an export before sharing it.

The log viewer shows the last 64 KiB. Logs larger than 10 MiB rotate to `.log.1` at the next Start; an active command keeps its output. Configuration writes are atomic. A damaged configuration is reported and backed up as `tools.corrupt-*.json` before the next save. Interface language is stored in macOS preferences.

## Development

Requires **Apple Silicon, macOS 14 or later**, and Apple’s Command Line Tools with a Swift compiler. Full Xcode is optional. The app has no third-party runtime dependencies.

```sh
./build.sh
"dist/Mung Tools.app/Contents/MacOS/MungTools" --self-test
./install.sh
```

The build uses `xcrun swiftc` and creates an ad-hoc-signed app in `dist/`. The installer copies it to `~/Applications/Mung Tools.app` and opens it. Use `./install.sh --no-open` to install without opening. Existing configuration is preserved. An unrelated app with the same name is not overwritten.

Self-tests use temporary fake tools; they do not start or stop your configured tools. For isolated interface testing, launch with a separate data folder:

```sh
"dist/Mung Tools.app/Contents/MacOS/MungTools" --data-dir /tmp/mung-tools-demo
```

To build local release candidates:

```sh
./package-release.sh
```

This builds the app and creates `MungTools-macOS-arm64.dmg`, `MungTools-macOS-arm64.zip`, `MungTools-source.zip`, `SHA256SUMS`, and `RELEASE-STATUS.plist` in `dist/releases/`. The app packages contain **Mung Tools.app**, without your configuration or scripts.

These are unnotarized development packages; `publicReleaseReady` is `false`. This project’s verified public release workflow requires Developer ID signing, accepted notarization, and Gatekeeper verification. See the [notarization workflow](NOTARIZATION.md). Checksums and passing tests do not replace those checks.

To prepare only a source archive:

```sh
./package-source.sh
```

The resulting `dist/releases/MungTools-source.zip` contains a top-level `MungTools/` folder. Packaging uses an explicit public-file allowlist and validates the archive. Local configuration, logs, generated apps, caches, machine-specific `ManagedScripts`, recordings, and models are excluded.

## Design and license

The compact, keyboard-friendly interface takes inspiration from [Raycast’s search bar](https://manual.raycast.com/search-bar) and [action panel](https://manual.raycast.com/action-panel). Mung Tools is an independent project.

[MIT license](../LICENSE). Made by [Mung (@mungbpro)](https://x.com/mungbpro).
