#!/bin/zsh
set -euo pipefail
umask 077
cd "${0:A:h}"

case "${1:-}" in
  ""|--check-prerequisites) ;;
  --help)
    print "Usage: ./notarize-release.sh [--check-prerequisites]"
    print "Requires MUNGTOOLS_SIGN_IDENTITY='Developer ID Application: Name (TEAMID)'"
    print "and MUNGTOOLS_NOTARY_PROFILE naming an existing notarytool Keychain profile."
    print "The default action builds and uploads app ZIP and DMG to Apple's notary service."
    print -- "--check-prerequisites checks local tools/identity only; no build or upload."
    exit 0 ;;
  *) print -u2 "Unknown option. Use --help."; exit 1 ;;
esac
if (( $# > 1 )); then print -u2 "Unexpected arguments. Use --help."; exit 1; fi

signing_identity="${MUNGTOOLS_SIGN_IDENTITY:-}"
notary_profile="${MUNGTOOLS_NOTARY_PROFILE:-}"
if [[ "$signing_identity" != "Developer ID Application: "* ]]; then
  print -u2 "A real Developer ID Application signing identity is required."
  print -u2 "Ad-hoc and Apple Development certificates cannot produce this notarized public release."
  print -u2 "Set MUNGTOOLS_SIGN_IDENTITY to its full name from Keychain. See docs/NOTARIZATION.md."
  exit 1
fi
if [[ -z "$notary_profile" ]]; then
  print -u2 "Set MUNGTOOLS_NOTARY_PROFILE to an existing notarytool Keychain profile name."
  print -u2 "Do not put Apple account passwords or API keys in scripts or this repository."
  exit 1
fi
if [[ "$(/usr/bin/uname -s)" != "Darwin" || "$(/usr/bin/uname -m)" != "arm64" ]]; then
  print -u2 "Build and test this release on an Apple Silicon Mac."
  exit 1
fi
xcrun --find notarytool >/dev/null
xcrun --find stapler >/dev/null
available_identities=$(/usr/bin/security find-identity -v -p codesigning)
if [[ "$available_identities" != *"\"${signing_identity}\""* ]]; then
  print -u2 "The requested Developer ID Application identity and private key are not available for code signing."
  print -u2 "Check Keychain and docs/NOTARIZATION.md; no files were submitted."
  exit 1
fi
if [[ "${1:-}" == --check-prerequisites ]]; then
  print "Developer ID Application identity and local notary tools are available."
  print "The Keychain profile is named but will only be authenticated when submitting. No build or upload occurred."
  exit 0
fi

./package-release.sh
app_path="$PWD/dist/Mung Tools.app"
release_path="$PWD/dist/releases"
signature_info=$(/usr/bin/codesign -dv --verbose=4 "$app_path" 2>&1)
if [[ "$signature_info" != *"Authority=${signing_identity}"* ||
      "$signature_info" != *"(runtime)"* || "$signature_info" != *"Timestamp="* ]]; then
  print -u2 "The app must have the requested Developer ID signature, hardened runtime, and a secure timestamp."
  exit 1
fi

log_path="$PWD/.build/notarization/$(/bin/date -u +%Y%m%dT%H%M%SZ)-$$"
mkdir -p "$log_path"
notary_stage=$(mktemp -d "${TMPDIR:-/tmp}/MungTools-notarize.XXXXXX")
mounted=false
cleanup_notary() {
  local result=$?
  if [[ "$mounted" == true ]]; then
    if /usr/bin/hdiutil detach -quiet "$notary_stage/mounted"; then
      mounted=false
    else
      print -u2 "Could not eject the verification disk image; its temporary mount was preserved: $notary_stage/mounted"
    fi
  fi
  if [[ "$mounted" == false ]]; then /bin/rm -rf "$notary_stage"; fi
  if (( result != 0 )); then
    /usr/bin/plutil -replace publicReleaseReady -bool NO "$release_path/RELEASE-STATUS.plist" 2>/dev/null || true
    /usr/bin/plutil -replace notarized -bool NO "$release_path/RELEASE-STATUS.plist" 2>/dev/null || true
    print -u2 "Notarized release checks did not finish. Nothing was published. Logs: $log_path"
  fi
  return $result
}
trap cleanup_notary EXIT

submit_for_notarization() {
  local archive="$1"
  local label="$2"
  local response="$log_path/$label-submission.plist"
  local submission_result=0
  print "Submitting $label to Apple's notary service; waiting for Accepted status."
  xcrun notarytool submit "$archive" --keychain-profile "$notary_profile" \
    --wait --timeout 1h --output-format plist > "$response" || submission_result=$?
  local submission_id=$(/usr/bin/plutil -extract id raw -o - "$response" 2>/dev/null || true)
  local submission_status=$(/usr/bin/plutil -extract status raw -o - "$response" 2>/dev/null || true)
  if [[ -n "$submission_id" ]]; then
    xcrun notarytool log "$submission_id" --keychain-profile "$notary_profile" \
      "$log_path/$label-log.json" >/dev/null 2>&1 || true
  fi
  if (( submission_result != 0 )) || [[ "$submission_status" != Accepted || -z "$submission_id" ]]; then
    print -u2 "$label notarization did not reach Accepted. Review $response and its notary log."
    return 1
  fi
  /usr/bin/printf '%s' "$submission_id" > "$notary_stage/$label-id"
  print "$label: Accepted."
}

submit_for_notarization "$release_path/MungTools-macOS-arm64.zip" app
xcrun stapler staple "$app_path"
xcrun stapler validate "$app_path"
/usr/bin/codesign --verify --strict "$app_path"
/usr/sbin/spctl --assess --type execute --verbose=4 "$app_path"

# Keep the signed, stapled app intact; rebuilding would discard the ticket.
./package-release.sh --from-built-app
disk_image="$release_path/MungTools-macOS-arm64.dmg"
/usr/bin/codesign --force --sign "$signing_identity" --timestamp "$disk_image"
/usr/bin/codesign --verify --strict "$disk_image"
submit_for_notarization "$disk_image" dmg
xcrun stapler staple "$disk_image"
xcrun stapler validate "$disk_image"
/usr/bin/codesign --verify --strict "$disk_image"
/usr/sbin/spctl --assess --type open --context context:primary-signature --verbose=4 "$disk_image"
/usr/bin/hdiutil verify -quiet "$disk_image"

# Verify both delivery formats after their final bytes are in place.
/usr/bin/ditto -x -k "$release_path/MungTools-macOS-arm64.zip" "$notary_stage/unzipped"
xcrun stapler validate "$notary_stage/unzipped/Mung Tools.app"
/usr/bin/codesign --verify --strict "$notary_stage/unzipped/Mung Tools.app"
/usr/sbin/spctl --assess --type execute --verbose=4 "$notary_stage/unzipped/Mung Tools.app"
mkdir -p "$notary_stage/mounted"
/usr/bin/hdiutil attach -readonly -nobrowse -mountpoint "$notary_stage/mounted" "$disk_image" > "$log_path/dmg-mount.txt"
mounted=true
[[ -L "$notary_stage/mounted/Applications" && "$(/usr/bin/readlink "$notary_stage/mounted/Applications")" == /Applications ]]
[[ -f "$notary_stage/mounted/Read Me First.txt" ]]
xcrun stapler validate "$notary_stage/mounted/Mung Tools.app"
/usr/bin/codesign --verify --strict "$notary_stage/mounted/Mung Tools.app"
/usr/sbin/spctl --assess --type execute --verbose=4 "$notary_stage/mounted/Mung Tools.app"
/usr/bin/cmp -s "$app_path/Contents/MacOS/MungTools" "$notary_stage/mounted/Mung Tools.app/Contents/MacOS/MungTools"
/usr/bin/hdiutil detach -quiet "$notary_stage/mounted"
mounted=false

(
  cd "$release_path"
  /usr/bin/shasum -a 256 MungTools-macOS-arm64.dmg MungTools-macOS-arm64.zip MungTools-source.zip > "$notary_stage/SHA256SUMS"
)
release_status="$notary_stage/RELEASE-STATUS.plist"
/bin/cp "$release_path/RELEASE-STATUS.plist" "$release_status"
/usr/bin/plutil -replace notarized -bool YES "$release_status"
/usr/bin/plutil -replace publicReleaseReady -bool YES "$release_status"
/usr/bin/plutil -replace message -string "App and disk image Accepted by Apple; staples, signatures, and Gatekeeper checks passed." "$release_status"
/usr/bin/plutil -insert gatekeeperVerified -bool YES "$release_status"
/usr/bin/plutil -insert appNotarySubmissionID -string "$(<"$notary_stage/app-id")" "$release_status"
/usr/bin/plutil -insert dmgNotarySubmissionID -string "$(<"$notary_stage/dmg-id")" "$release_status"
/usr/bin/plutil -insert verifiedAtUTC -string "$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)" "$release_status"
for artifact_name hash_key in MungTools-macOS-arm64.dmg dmgSHA256 MungTools-macOS-arm64.zip appZIPsha256 MungTools-source.zip sourceSHA256; do
  artifact_hash=$(/usr/bin/shasum -a 256 "$release_path/$artifact_name")
  /usr/bin/plutil -replace "$hash_key" -string "${artifact_hash%% *}" "$release_status"
done
/bin/mv -f "$notary_stage/SHA256SUMS" "$release_path/SHA256SUMS"
/bin/mv -f "$release_status" "$release_path/RELEASE-STATUS.plist"
print "Notarized release checks passed: publicReleaseReady=true."
print "Artifacts: $release_path"
print "Nothing was uploaded to GitHub or published. Preserve the matching SHA256SUMS and RELEASE-STATUS.plist."
