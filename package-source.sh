#!/bin/zsh
set -euo pipefail
umask 022
cd "${0:A:h}"

# This explicit allowlist is intentional. Never archive the working directory:
# it can contain personal commands, tool configurations, recordings, and models.
swift_sources=(Sources/*.swift(N))
swift_tests=(Tests/*.swift(N))
if (( ${#swift_sources} == 0 || ${#swift_tests} == 0 )) || [[ -L Sources || -L Tests ]]; then
  print -u2 "Expected local Swift source and test folders; no archive was created."
  exit 1
fi
source_files=(
  "${swift_sources[@]}"
  "${swift_tests[@]}"
  build.sh
  install.sh
  README.md
  README.zh-CN.md
  LICENSE
  .gitignore
  package-source.sh
  package-release.sh
  .github/workflows/build.yml
  docs/CODEX-IMPORT.md
  docs/images/launcher-en.jpg
  docs/images/launcher-zh-CN.jpg
  docs/images/import-en.jpg
  docs/images/running-en.jpg
)
if [[ -e docs/USAGE.md || -L docs/USAGE.md ]]; then
  source_files+=(docs/USAGE.md)
fi
if [[ -e docs/USAGE.zh-CN.md || -L docs/USAGE.zh-CN.md ]]; then
  source_files+=(docs/USAGE.zh-CN.md)
fi
for source_file in "${source_files[@]}"; do
  if [[ ! -f "$source_file" || -L "$source_file" ]]; then
    print -u2 "Expected a regular source file; no archive was created: $source_file"
    exit 1
  fi
  source_parent=${source_file:h}
  while [[ "$source_parent" != "." ]]; do
    if [[ -L "$source_parent" ]]; then
      print -u2 "Source folders must not be symbolic links: $source_parent"
      exit 1
    fi
    source_parent=${source_parent:h}
  done
done

staging_dir=$(mktemp -d "${TMPDIR:-/tmp}/MungTools-source.XXXXXX")
trap '/bin/rm -rf "$staging_dir"' EXIT
mkdir -p "$staging_dir/MungTools/Sources" "$staging_dir/MungTools/Tests"
archive_files=()
for source_file in "${source_files[@]}"; do
  mkdir -p "$staging_dir/MungTools/${source_file:h}"
  file_mode=644
  if [[ "$source_file" == *.sh ]]; then file_mode=755; fi
  /usr/bin/install -m "$file_mode" "$source_file" "$staging_dir/MungTools/$source_file"
  archive_files+=("MungTools/$source_file")
done

archive_path="$staging_dir/MungTools-source.zip"
(
  cd "$staging_dir"
  # -X omits extra attributes. Explicit files also exclude resource forks,
  # hidden files, symlinks, and unexpected contents beneath staged folders.
  /usr/bin/zip -q -X "$archive_path" "${archive_files[@]}"
)
printf '%s\n' "${archive_files[@]}" | LC_ALL=C /usr/bin/sort > "$staging_dir/expected-files.txt"
/usr/bin/zipinfo -1 "$archive_path" | LC_ALL=C /usr/bin/sort > "$staging_dir/actual-files.txt"
if ! /usr/bin/cmp -s "$staging_dir/expected-files.txt" "$staging_dir/actual-files.txt"; then
  print -u2 "Archive validation failed; no release archive was installed."
  exit 1
fi
/usr/bin/unzip -tq "$archive_path" >/dev/null
mkdir -p dist/releases
/bin/mv -f "$archive_path" dist/releases/MungTools-source.zip
print "Created: $PWD/dist/releases/MungTools-source.zip"
print "Validated ${#archive_files} source files. No local configuration or managed scripts were included."
