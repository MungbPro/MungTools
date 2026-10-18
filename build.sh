#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
app_path="$PWD/dist/Mung Tools.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources" .build/module-cache
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
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.3.0</string>
<key>CFBundleVersion</key><string>7</string>
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
/usr/bin/codesign --force --sign - "$app_path"
print "Built: $app_path"
