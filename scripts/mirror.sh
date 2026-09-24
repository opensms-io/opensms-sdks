#!/usr/bin/env bash
# Copy one git-resolved client (go, swift or php) from packages/<lang> to its mirror repo
# opensms-io/opensms-<lang>, as the repo root, and push main. Tags are pushed separately
# when releasing (see RELEASING.md).
#
#   scripts/mirror.sh go
set -euo pipefail

lang="${1:?usage: scripts/mirror.sh go|swift|php}"
case "$lang" in go|swift|php) ;; *) echo "unknown client: $lang" >&2; exit 1 ;; esac

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -z "$(git -C "$root" status --porcelain "packages/$lang")" ] || { echo "packages/$lang has uncommitted changes" >&2; exit 1; }
source_rev="$(git -C "$root" rev-parse --short HEAD)"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
git clone --quiet "git@github.com:opensms-io/opensms-$lang.git" "$work/mirror"
cd "$work/mirror"

# The exact files the mirror should hold: the committed package tree plus .gitignore.
git -C "$root" ls-tree -r --name-only HEAD "packages/$lang/" | sed "s#^packages/$lang/##" > "$work/wanted"
echo .gitignore >> "$work/wanted"

# Drop tracked files that no longer exist in the package, one path at a time.
git ls-files | grep -vxF -f "$work/wanted" | while IFS= read -r gone; do git rm --quiet -- "$gone"; done || true

git -C "$root" archive HEAD "packages/$lang" | tar -x --strip-components=2 -C "$work/mirror"
cp "$root/scripts/mirror.gitignore" .gitignore
while IFS= read -r path; do git add -- "$path"; done < "$work/wanted"

if git diff --cached --quiet; then
  echo "opensms-$lang is already in sync with $source_rev"
  exit 0
fi
git commit --quiet -m "sync from opensms-sdks@$source_rev"
git push --quiet origin HEAD:main
echo "opensms-$lang synced to opensms-sdks@$source_rev"
