#!/bin/bash
# Download a checksum-pinned source release and compile it on this Mac.
# No downloaded app, administrator access, or macOS security overrides.
set -euo pipefail

source_version="v1.3.1"
source_sha256="649d37de4c9e2e59d7a4d26e097c379d4acdcf36fe39925e351ac066af060f56"
source_url="https://github.com/MungbPro/MungTools/releases/download/$source_version/MungTools-source.zip"
check_only=false
case "${1:-}" in
  "") ;;
  --check) check_only=true ;;
  *) printf 'Usage: bash install-from-source.sh [--check]\n' >&2; exit 2 ;;
esac
if (( $# > 1 )); then
  printf 'Usage: bash install-from-source.sh [--check]\n' >&2
  exit 2
fi

fail() { printf '\nMung Tools: %s\n' "$1" >&2; exit 1; }
[[ "$(/usr/bin/uname -s)" == Darwin ]] || fail 'This installer requires macOS.'
[[ "$(/usr/bin/id -u)" != 0 ]] || fail 'Run this as your normal user, without sudo.'
[[ "$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null || true)" == 1 ]] || fail 'This version requires an Apple Silicon Mac.'
macos_version=$(/usr/bin/sw_vers -productVersion)
macos_major=${macos_version%%.*}
[[ "$macos_major" =~ ^[0-9]+$ ]] && (( macos_major >= 14 )) || fail 'macOS 14 or later is required.'
[[ -n "${HOME:-}" && "$HOME" == /* && "$HOME" != / && -d "$HOME" && -O "$HOME" && -w "$HOME" ]] || fail 'Your home folder must be writable and owned by your user.'

app_directory="$HOME/Applications"
app_destination="$app_directory/Mung Tools.app"
if [[ -L "$app_directory" || ( -e "$app_directory" && ! -d "$app_directory" ) ]]; then
  fail '~/Applications must be a regular folder, not a symbolic link or file.'
fi
if [[ -d "$app_directory" && ! -w "$app_directory" ]]; then
  fail '~/Applications is not writable. Nothing was installed.'
fi
if [[ -e "$app_destination" || -L "$app_destination" ]]; then
  [[ ! -L "$app_destination" && -d "$app_destination" ]] || fail 'A different file or symbolic link already uses the app name. Nothing was overwritten.'
  installed_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_destination/Contents/Info.plist" 2>/dev/null || true)
  [[ "$installed_id" == pro.mungb.tool-launcher ]] || fail 'A different app already uses this name. Nothing was overwritten.'
fi

if ! /usr/bin/xcrun --find swiftc >/dev/null 2>&1; then
  printf '\nApple Command Line Tools are required to build Mung Tools.\n'
  if [[ "$check_only" == false ]]; then
    printf 'Opening Apple\047s installer. Complete it, then run this command again.\n'
    /usr/bin/xcode-select --install || true
  else
    printf 'Install them with: xcode-select --install\n'
  fi
  exit 1
fi
if ! /usr/bin/xcrun swiftc --version >/dev/null 2>&1; then
  fail 'The Apple Swift compiler is not ready. Run xcrun swiftc --version in Terminal to see the setup issue, then try again.'
fi

printf '\nMung Tools source installer\n'
printf 'Downloading source %s; the app will be compiled locally.\n' "$source_version"
printf 'Your saved tools and running services will be preserved.\n\n'
work_directory=$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/MungTools-source-install.XXXXXX")
cleanup() { /bin/rm -rf "$work_directory"; }
trap cleanup EXIT
archive_path="$work_directory/MungTools-source.zip"
if ! /usr/bin/curl --fail --show-error --location --retry 2 --connect-timeout 15 --max-time 180 \
  --proto '=https' --proto-redir '=https' --tlsv1.2 "$source_url" -o "$archive_path"; then
  fail 'The source download failed. Check your connection and run the installer again.'
fi
actual_sha256=$(/usr/bin/shasum -a 256 "$archive_path")
actual_sha256=${actual_sha256%% *}
[[ "$actual_sha256" == "$source_sha256" ]] || fail 'The source checksum did not match. Nothing was built or installed.'

# The digest fixes the exact source archive. Validate its paths before extraction.
/usr/bin/unzip -Z1 "$archive_path" > "$work_directory/archive-files.txt"
while IFS= read -r archive_entry; do
  case "$archive_entry" in
    MungTools/*) ;;
    *) fail 'The source archive has an unexpected path. Nothing was installed.' ;;
  esac
  case "/$archive_entry/" in
    */../*|*/./*|*\\*) fail 'The source archive has an unsafe path. Nothing was installed.' ;;
  esac
done < "$work_directory/archive-files.txt"
mkdir "$work_directory/source"
/usr/bin/unzip -q "$archive_path" -d "$work_directory/source"
source_directory="$work_directory/source/MungTools"
[[ -f "$source_directory/install.sh" && ! -L "$source_directory/install.sh" ]] || fail 'The expected source installer is missing.'
if [[ "$check_only" == true ]]; then
  printf '\nCheck passed: this Mac has the compiler, and the pinned source download is valid.\n'
  printf 'No app was built, installed, opened, or stopped.\n'
  exit 0
fi

printf '\nBuilding locally. This may take a few minutes…\n'
if ! (cd "$source_directory" && /bin/zsh ./install.sh --no-open); then
  fail 'The local build or installation failed. Review the message above before trying again.'
fi
/usr/bin/codesign --verify --strict "$app_destination"

# Opening an installed update must not quit a launcher that owns running tools.
launcher_running=false
app_binary="$app_destination/Contents/MacOS/MungTools"
while IFS= read -r process_command; do
  if [[ "$process_command" == "$app_binary" || "$process_command" == "$app_binary "* ]]; then
    launcher_running=true
  fi
done < <(/bin/ps -axo command=)
printf '\nInstalled: %s\n' "$app_destination"
if [[ "$launcher_running" == true ]]; then
  printf 'Your current launcher and tools are still running. The new build takes effect on the next launch.\n'
else
  /usr/bin/open "$app_destination"
  printf 'Mung Tools is open. Click its menu-bar icon to get started.\n'
fi
printf 'This is a local source build; no macOS security settings were changed.\n'
