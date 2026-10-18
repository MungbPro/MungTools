# Signing and notarizing a public release

This guide is for maintainers. A normal downloaded release should use **Developer ID Application signing and Apple notarization**. An ad-hoc signature or an Apple Development certificate cannot provide that distribution path. A local development build is not a notarized release.

The workflow follows Apple's [notarization documentation](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow), [packaging guidance](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution), and [common issue guidance](https://developer.apple.com/documentation/security/resolving-common-notarization-issues).

## Before starting

- Use an Apple Silicon Mac with Xcode command-line tools and internet access.
- Have an active Apple Developer Program membership and a valid **Developer ID Application** certificate with its private key in Keychain. See [Apple's Developer ID overview](https://developer.apple.com/developer-id/).
- Create a `notarytool` Keychain credential profile using Apple's instructions. Keep passwords, API keys, private keys, and credential exports out of this repository and release files.
- Confirm the app version and source are ready for release. Close any running development copy before rebuilding its executable.

To see available signing identity names, run:

```sh
security find-identity -v -p codesigning
```

Use the full `Developer ID Application: … (TEAMID)` name. The scripts reject an ad-hoc identity, an Apple Development identity, and identity hashes for the notarized path.

Set only the identity name and the existing **Keychain profile name**:

```sh
export MUNGTOOLS_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)'
export MUNGTOOLS_NOTARY_PROFILE='mung-tools-notary'
./notarize-release.sh --check-prerequisites
```

This check inspects local tool availability and signing identity metadata. It does not build, submit anything, create certificates, or read account passwords. The Keychain profile is authenticated by Apple's tool during submission.

## Build and notarize

```sh
./notarize-release.sh
```

Running this command uploads the app ZIP and disk image to Apple's notary service. Processing can take time. Logs stay in the ignored `.build/notarization/` folder. The script stops on any failed build, test, signature, submission, staple, or Gatekeeper assessment.

It performs these steps:

1. Build with the requested Developer ID identity, hardened runtime, and a secure timestamp; run isolated self-tests.
2. Submit the app ZIP and wait for Apple's **Accepted** status.
3. Staple and validate the app's ticket, verify its signature, and assess it with Gatekeeper.
4. Recreate the ZIP and a read-only DMG containing the stapled app, an Applications shortcut, and bilingual installation instructions.
5. Sign the DMG, submit it, wait for **Accepted**, then staple, verify, and assess it.
6. Extract the final ZIP and mount the final DMG read-only to verify the delivered apps and installation shortcut.
7. Update checksums and mark the local release status ready only after every check succeeds.

The scripts do not publish to GitHub. Do not change or re-sign the app after this workflow: that changes the code Apple checked. If a submission fails or times out, review the private logs before retrying. A new run rebuilds and submits again; it does not assume an earlier submission succeeded.

## Check before publishing

Outputs are in `dist/releases/`:

- `MungTools-macOS-arm64.dmg` — recommended drag-to-install download.
- `MungTools-macOS-arm64.zip` — compatible app archive.
- `MungTools-source.zip` — source, guides, and fictional demo images.
- `SHA256SUMS` — hashes of those three downloads.
- `RELEASE-STATUS.plist` — local verification state and the matching artifact hashes.

Before creating a public latest release, require a true readiness value and valid checksums:

```sh
test "$(plutil -extract publicReleaseReady raw -o - dist/releases/RELEASE-STATUS.plist)" = true
(cd dist/releases && shasum -a 256 -c SHA256SUMS)
```

Also inspect the version and artifact hashes in `RELEASE-STATUS.plist`. Upload the artifacts from that successful run together. Do not promote a development build or a partial notarization run to the normal download link. A first launch can still show macOS's standard “downloaded from the internet” confirmation; notarization does not promise the absence of every system dialog.

## Local development packages

```sh
./package-release.sh
```

Without a signing identity, this creates an ad-hoc development DMG and ZIP. It always sets `publicReleaseReady=false` and `notarized=false`; its output does not claim Gatekeeper acceptance. Downloaded development builds can be blocked by macOS. See the [download guide](DOWNLOAD.md) instead of disabling Gatekeeper or removing quarantine attributes.

`./package-release.sh --from-built-app` repackages an existing app without rebuilding or rerunning self-tests. The notarization helper uses this to preserve the stapled ticket. It still verifies the bundle and archive, and still marks readiness false until the complete notarization workflow finishes.

## 简体中文

公开下载版需要有效的 **Developer ID Application** 签名和 Apple 公证。临时签名、Apple Development 证书均不能代替此流程。需要有效的 Apple 开发者计划会员、钥匙串中的证书及私钥，以及事先配置好的 `notarytool` 钥匙串凭据。

只在环境变量中指定签名身份名称与钥匙串配置名称，然后运行 `./notarize-release.sh`。脚本会构建并测试，分别提交应用与 DMG，等待 **Accepted**，附加并验证凭据，再检查 Gatekeeper。任何一步失败都不会标记为公开发布就绪；脚本不会自动发布到 GitHub。

发布前，必须确认 `dist/releases/RELEASE-STATUS.plist` 中的 `publicReleaseReady` 为 `true`，并核对 `SHA256SUMS`。默认 `./package-release.sh` 只生成开发下载包，状态始终为 `false`。不要把未公证构建当作正常公开下载版，也不要要求用户关闭 Gatekeeper。
