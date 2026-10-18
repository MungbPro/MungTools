#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
sign_identity="${MUNGTOOLS_SIGN_IDENTITY:--}"
if [[ "$sign_identity" != "-" && "$sign_identity" != "Developer ID Application: "* ]]; then
  print -u2 "Use a Developer ID Application identity for distribution, or '-' for a local development build."
  exit 1
fi
if [[ ! -f Assets/MungTools.icns || -L Assets/MungTools.icns ]]; then
  print -u2 "The app icon is missing. Run: swift scripts/generate-icon.swift"
  exit 1
fi
output_app_path="$PWD/dist/Mung Tools.app"
mkdir -p dist .build/module-cache
if [[ -e "$output_app_path" || -L "$output_app_path" ]]; then
  previous_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$output_app_path/Contents/Info.plist" 2>/dev/null || true)
  if [[ -L "$output_app_path" || "$previous_id" != "pro.mungb.tool-launcher" ]]; then
    print -u2 "An unexpected build output already exists; nothing was overwritten: $output_app_path"
    exit 1
  fi
fi
# Build a new bundle so stale notarization tickets and resources cannot survive.
build_stage=$(mktemp -d "$PWD/.build/MungTools-build.XXXXXX")
trap '/bin/rm -rf "$build_stage"' EXIT
app_path="$build_stage/Mung Tools.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
/bin/cp Assets/MungTools.icns "$app_path/Contents/Resources/MungTools.icns"
xcrun swiftc -O -whole-module-optimization -swift-version 5 -target arm64-apple-macos14.0 \
  -module-cache-path "$PWD/.build/module-cache" \
  -framework AppKit -framework SwiftUI \
  Sources/*.swift Tests/*.swift -o "$app_path/Contents/MacOS/MungTools"
cat > "$app_path/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MungTools</string>
<key>CFBundleIdentifier</key><string>pro.mungb.tool-launcher</string>
<key>CFBundleName</key><string>Mung Tools</string>
<key>CFBundleDisplayName</key><string>Mung Tools</string>
<key>CFBundleIconFile</key><string>MungTools</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.3.1</string>
<key>CFBundleVersion</key><string>8</string>
<key>UTExportedTypeDeclarations</key><array><dict>
  <key>UTTypeIdentifier</key><string>pro.mungb.tool-launcher.import</string>
  <key>UTTypeDescription</key><string>Mung Tools Import</string>
  <key>UTTypeConformsTo</key><array><string>public.json</string></array>
  <key>UTTypeTagSpecification</key><dict>
    <key>public.filename-extension</key><array><string>mungtools</string></array>
    <key>public.mime-type</key><string>application/json</string>
  </dict>
</dict></array>
<key>CFBundleDocumentTypes</key><array><dict>
  <key>CFBundleTypeName</key><string>Mung Tools Import</string>
  <key>CFBundleTypeRole</key><string>Viewer</string>
  <key>LSHandlerRank</key><string>Owner</string>
  <key>LSItemContentTypes</key><array><string>pro.mungb.tool-launcher.import</string></array>
</dict></array>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
if [[ "$sign_identity" == "-" ]]; then
  /usr/bin/codesign --force --sign - --options runtime "$app_path"
  print "Signing: local development build (not Apple-notarized)"
else
  /usr/bin/codesign --force --sign "$sign_identity" --options runtime --timestamp "$app_path"
  print "Signing: Developer ID; notarization must complete before public distribution."
fi
if [[ -d "$output_app_path" ]]; then
  /bin/mv "$output_app_path" "$build_stage/previous.app"
fi
if ! /bin/mv "$app_path" "$output_app_path"; then
  if [[ -d "$build_stage/previous.app" && ! -e "$output_app_path" ]]; then
    /bin/mv "$build_stage/previous.app" "$output_app_path"
  fi
  print -u2 "Could not install the newly built app into dist."
  exit 1
fi
print "Built: $output_app_path"
