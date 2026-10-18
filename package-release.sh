#!/bin/zsh
set -euo pipefail
umask 022
cd "${0:A:h}"

from_built_app=false
case "${1:-}" in
  "") ;;
  --from-built-app) from_built_app=true ;;
  --help)
    print "Usage: ./package-release.sh [--from-built-app]"
    print "Create local development DMG/ZIP files. This does not notarize or publish."
    print -- "--from-built-app preserves a previously built/stapled app and skips the build and self-tests."
    exit 0 ;;
  *) print -u2 "Unknown option. Use --help."; exit 1 ;;
esac
if (( $# > 1 )); then print -u2 "Unexpected arguments. Use --help."; exit 1; fi

if [[ "$(/usr/bin/uname -s)" != "Darwin" || "$(/usr/bin/uname -m)" != "arm64" ]]; then
  print -u2 "Build and test this Apple Silicon release on an Apple Silicon Mac."
  exit 1
fi

mkdir -p dist/releases
# Invalidate any previous approval before changing release artifacts.
/bin/rm -f dist/releases/RELEASE-STATUS.plist
/usr/bin/plutil -create xml1 dist/releases/RELEASE-STATUS.plist
/usr/bin/plutil -insert publicReleaseReady -bool NO dist/releases/RELEASE-STATUS.plist
/usr/bin/plutil -insert notarized -bool NO dist/releases/RELEASE-STATUS.plist
/usr/bin/plutil -insert message -string "Packaging in progress; not approved for public release." dist/releases/RELEASE-STATUS.plist
if [[ "$from_built_app" == false ]]; then ./build.sh; fi
app_path="$PWD/dist/Mung Tools.app"
/usr/bin/codesign --verify --strict "$app_path"
if [[ "$(/usr/bin/lipo -archs "$app_path/Contents/MacOS/MungTools")" != "arm64" ]]; then
  print -u2 "The release executable must contain only the arm64 architecture."
  exit 1
fi

release_stage=$(mktemp -d "${TMPDIR:-/tmp}/MungTools-release.XXXXXX")
trap '/bin/rm -rf "$release_stage"' EXIT

# Only the executable, bundle metadata, and signature belong in this release.
# Refuse unexpected files instead of accidentally shipping local runtime data.
expected_bundle_entries=(
  "Mung Tools.app/"
  "Mung Tools.app/Contents/"
  "Mung Tools.app/Contents/Info.plist"
  "Mung Tools.app/Contents/MacOS/"
  "Mung Tools.app/Contents/MacOS/MungTools"
  "Mung Tools.app/Contents/Resources/"
  "Mung Tools.app/Contents/Resources/MungTools.icns"
  "Mung Tools.app/Contents/_CodeSignature/"
  "Mung Tools.app/Contents/_CodeSignature/CodeResources"
)
# stapler stores an app's ticket here. Only accept it after local validation.
app_ticket_valid=false
if [[ -e "$app_path/Contents/CodeResources" ]]; then
  xcrun stapler validate "$app_path"
  app_ticket_valid=true
  expected_bundle_entries+=("Mung Tools.app/Contents/CodeResources")
fi
printf '%s\n' "${expected_bundle_entries[@]}" | LC_ALL=C /usr/bin/sort > "$release_stage/expected-bundle.txt"
bundle_entries=("Mung Tools.app/")
for bundle_entry in "$app_path"/**/*(ND); do
  relative_entry="Mung Tools.app/${bundle_entry#$app_path/}"
  if [[ -d "$bundle_entry" && ! -L "$bundle_entry" ]]; then
    relative_entry+="/"
  elif [[ ! -f "$bundle_entry" || -L "$bundle_entry" ]]; then
    print -u2 "The app bundle contains an unexpected file type; no app archive was created."
    exit 1
  fi
  bundle_entries+=("$relative_entry")
done
printf '%s\n' "${bundle_entries[@]}" | LC_ALL=C /usr/bin/sort > "$release_stage/actual-bundle.txt"
if [[ -L "$app_path" ]] || ! /usr/bin/cmp -s "$release_stage/expected-bundle.txt" "$release_stage/actual-bundle.txt"; then
  print -u2 "The app bundle contains unexpected files or symbolic links; no app archive was created."
  exit 1
fi

# Self-tests create their own temporary fixtures. This separate data directory
# also isolates language preferences from the developer's real app settings.
if [[ "$from_built_app" == false ]]; then
  "$app_path/Contents/MacOS/MungTools" --self-test --data-dir "$release_stage/test-data"
fi
./package-source.sh

app_archive="$release_stage/MungTools-macOS-arm64.zip"
/usr/bin/ditto -c -k --norsrc --keepParent "$app_path" "$app_archive"
/usr/bin/unzip -tq "$app_archive" >/dev/null
/usr/bin/zipinfo -1 "$app_archive" | LC_ALL=C /usr/bin/sort > "$release_stage/archived-bundle.txt"
if ! /usr/bin/cmp -s "$release_stage/expected-bundle.txt" "$release_stage/archived-bundle.txt"; then
  print -u2 "The app archive contains unexpected files; no release artifacts were installed."
  exit 1
fi
/usr/bin/ditto -x -k "$app_archive" "$release_stage/extracted"
/usr/bin/codesign --verify --strict "$release_stage/extracted/Mung Tools.app"
if [[ -e "$app_path/Contents/CodeResources" ]]; then
  xcrun stapler validate "$release_stage/extracted/Mung Tools.app"
fi

# A read-only drag-to-install image: exactly the app and Applications shortcut.
mkdir -p "$release_stage/dmg-root"
/usr/bin/ditto "$app_path" "$release_stage/dmg-root/Mung Tools.app"
/bin/ln -s /Applications "$release_stage/dmg-root/Applications"
if [[ "$app_ticket_valid" == true ]]; then
  app_status="APP STATUS: An Apple notarization ticket is attached to this app and has been verified."
  app_status_zh="应用状态：此应用已附有经验证的 Apple 公证凭据。"
else
  app_status="APP STATUS: Development build. This app is NOT notarized by Apple. macOS may block opening it. Use an official notarized release when available, or build from source."
  app_status_zh="应用状态：开发构建，尚未经 Apple 公证。macOS 可能阻止打开。请使用官方已公证版本（如有），或自行从源码构建。"
fi
cat > "$release_stage/dmg-root/Read Me First.txt" <<INSTALL_TEXT
Mung Tools — Install

$app_status

1. Drag Mung Tools.app onto the Applications shortcut in this window.
2. Eject the Mung Tools disk image.
3. Open Mung Tools from Applications. Its icon lives in the menu bar.

Download status and installation help:
https://github.com/MungbPro/MungTools/blob/main/docs/DOWNLOAD.md
More About Mung: https://x.com/mungbpro

熊梦白 AI 工具箱 — 安装

$app_status_zh

1. 将 Mung Tools.app 拖到此窗口中的 Applications（应用程序）快捷方式。
2. 推出 Mung Tools 磁盘映像。
3. 从“应用程序”打开 Mung Tools；工具箱图标会出现在菜单栏。

下载状态与安装说明：
https://github.com/MungbPro/MungTools/blob/main/docs/DOWNLOAD.zh-CN.md
关注我-熊梦白：https://x.com/mungbpro
INSTALL_TEXT
dmg_archive="$release_stage/MungTools-macOS-arm64.dmg"
/usr/bin/hdiutil create -quiet -srcfolder "$release_stage/dmg-root" \
  -volname "Mung Tools" -fs HFS+ -format UDZO "$dmg_archive"
/usr/bin/hdiutil verify -quiet "$dmg_archive"
/bin/cp dist/releases/MungTools-source.zip "$release_stage/MungTools-source.zip"
(
  cd "$release_stage"
  /usr/bin/shasum -a 256 MungTools-macOS-arm64.dmg MungTools-macOS-arm64.zip MungTools-source.zip > SHA256SUMS
)

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")
build_number=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app_path/Contents/Info.plist")
signature_info=$(/usr/bin/codesign -dv --verbose=4 "$app_path" 2>&1)
signature_type="other"
if [[ "$signature_info" == *"Signature=adhoc"* ]]; then
  signature_type="ad-hoc"
elif [[ "$signature_info" == *"Authority=Developer ID Application:"* ]]; then
  signature_type="Developer ID Application"
fi
release_status="$release_stage/RELEASE-STATUS.plist"
/usr/bin/plutil -create xml1 "$release_status"
/usr/bin/plutil -insert schemaVersion -integer 1 "$release_status"
/usr/bin/plutil -insert version -string "$version" "$release_status"
/usr/bin/plutil -insert build -string "$build_number" "$release_status"
/usr/bin/plutil -insert architecture -string arm64 "$release_status"
/usr/bin/plutil -insert signatureType -string "$signature_type" "$release_status"
/usr/bin/plutil -insert notarized -bool NO "$release_status"
/usr/bin/plutil -insert publicReleaseReady -bool NO "$release_status"
/usr/bin/plutil -insert message -string "Development package: notarization and public release checks have not passed." "$release_status"
for artifact_name hash_key in MungTools-macOS-arm64.dmg dmgSHA256 MungTools-macOS-arm64.zip appZIPsha256 MungTools-source.zip sourceSHA256; do
  artifact_hash=$(/usr/bin/shasum -a 256 "$release_stage/$artifact_name")
  /usr/bin/plutil -insert "$hash_key" -string "${artifact_hash%% *}" "$release_status"
done

/bin/mv -f "$app_archive" dist/releases/MungTools-macOS-arm64.zip
/bin/mv -f "$dmg_archive" dist/releases/MungTools-macOS-arm64.dmg
/bin/mv -f "$release_stage/SHA256SUMS" dist/releases/SHA256SUMS
/bin/mv -f "$release_status" dist/releases/RELEASE-STATUS.plist
print "Development packages created in: $PWD/dist/releases"
print "MungTools-macOS-arm64.dmg · MungTools-macOS-arm64.zip · MungTools-source.zip · SHA256SUMS"
print "NOT NOTARIZED: publicReleaseReady=false. Use ./notarize-release.sh for a verified public release."
