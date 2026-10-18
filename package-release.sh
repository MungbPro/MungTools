#!/bin/zsh
set -euo pipefail
umask 022
cd "${0:A:h}"

if [[ "$(/usr/bin/uname -s)" != "Darwin" || "$(/usr/bin/uname -m)" != "arm64" ]]; then
  print -u2 "Build and test this Apple Silicon release on an Apple Silicon Mac."
  exit 1
fi

./build.sh
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
  "Mung Tools.app/Contents/_CodeSignature/"
  "Mung Tools.app/Contents/_CodeSignature/CodeResources"
)
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
"$app_path/Contents/MacOS/MungTools" --self-test --data-dir "$release_stage/test-data"
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
/bin/cp dist/releases/MungTools-source.zip "$release_stage/MungTools-source.zip"
(
  cd "$release_stage"
  /usr/bin/shasum -a 256 MungTools-macOS-arm64.zip MungTools-source.zip > SHA256SUMS
)

mkdir -p dist/releases
/bin/mv -f "$app_archive" dist/releases/MungTools-macOS-arm64.zip
/bin/mv -f "$release_stage/SHA256SUMS" dist/releases/SHA256SUMS
print "Release artifacts are ready in: $PWD/dist/releases"
print "MungTools-macOS-arm64.zip · MungTools-source.zip · SHA256SUMS"
