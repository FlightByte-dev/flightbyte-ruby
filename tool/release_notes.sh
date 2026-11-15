#!/usr/bin/env bash
# Prints the CHANGELOG.md section of one version, without its heading.
#
#   tool/release_notes.sh 1.0.0
set -euo pipefail

version="${1:?usage: tool/release_notes.sh <version>}"
notes="$(awk -v heading="## ${version}" '
  $0 == heading { found = 1; next }
  found && /^## / { exit }
  found { print }
' CHANGELOG.md | sed -e '/./,$!d')"

if [[ -z "${notes//[[:space:]]/}" ]]; then
  echo "CHANGELOG.md has no \"## ${version}\" section." >&2
  exit 1
fi
printf '%s\n' "$notes"
