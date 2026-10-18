#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
./build.sh
app_destination="$HOME/Applications/Mung Tools.app"
if [[ -d "$app_destination" ]]; then
  app_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_destination/Contents/Info.plist" 2>/dev/null || true)
  if [[ "$app_id" != "pro.mungb.tool-launcher" ]]; then
    print -u2 "A different app already uses this name; nothing was overwritten: $app_destination"
    exit 1
  fi
fi
mkdir -p "$HOME/Applications"
/usr/bin/ditto "dist/Mung Tools.app" "$app_destination"
/usr/bin/codesign --verify "$app_destination"
print "Installed: $app_destination"
if [[ "${1:-}" != "--no-open" ]]; then
  /usr/bin/open "$app_destination"
fi
