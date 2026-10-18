#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
./build.sh
app_directory="$HOME/Applications"
app_destination="$app_directory/Mung Tools.app"
check_destination() {
  if [[ -e "$app_destination" || -L "$app_destination" ]]; then
    app_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_destination/Contents/Info.plist" 2>/dev/null || true)
    if [[ -L "$app_destination" || ! -d "$app_destination" || "$app_id" != "pro.mungb.tool-launcher" ]]; then
      print -u2 "A different app or symbolic link already uses this name; nothing was overwritten: $app_destination"
      return 1
    fi
  fi
}
check_destination
mkdir -p "$app_directory"
# Stage beside the destination so replacement uses renames on one filesystem.
# A running old copy can retain its open executable instead of being overwritten.
install_stage=$(mktemp -d "$app_directory/.MungTools-install.XXXXXX")
staged_app="$install_stage/Mung Tools.app"
previous_app="$install_stage/previous.app"
replacement_complete=false
cleanup_install() {
  local result=$?
  if [[ "$replacement_complete" == false && -e "$previous_app" ]]; then
    print -u2 "The previous app was preserved for recovery: $previous_app"
  else
    /bin/rm -rf "$install_stage"
  fi
  return $result
}
trap cleanup_install EXIT
/usr/bin/ditto "dist/Mung Tools.app" "$staged_app"
staged_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$staged_app/Contents/Info.plist" 2>/dev/null || true)
if [[ "$staged_id" != "pro.mungb.tool-launcher" ]]; then
  print -u2 "The copied app has an unexpected bundle identifier; the installed app was left unchanged."
  exit 1
fi
/usr/bin/codesign --verify --strict "$staged_app"
check_destination
if [[ -d "$app_destination" ]]; then
  /bin/mv "$app_destination" "$previous_app"
fi
if ! /bin/mv "$staged_app" "$app_destination"; then
  if [[ -d "$previous_app" && ! -e "$app_destination" && ! -L "$app_destination" ]]; then
    if /bin/mv "$previous_app" "$app_destination"; then
      print -u2 "Installation failed; the previous app was restored."
    else
      print -u2 "Installation failed, and the previous app could not be restored automatically."
    fi
  else
    print -u2 "Could not move the new app into Applications."
  fi
  exit 1
fi
replacement_complete=true
print "Installed: $app_destination"
if [[ "${1:-}" != "--no-open" ]]; then
  /usr/bin/open "$app_destination"
fi
