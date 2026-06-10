#!/usr/bin/env bash
set -euo pipefail
COMMIT_MSG="${1:-Update app}"
VERSION_ARG="${2:-patch}"
BRANCH="${BRANCH:-main}"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Error: not inside a git repository."
  exit 1
fi

current_tag=$(git tag --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -n 1 || true)
if [[ -z "$current_tag" ]]; then current_tag="v0.0.0"; fi

bump_version() {
  local tag="$1"; local part="$2"; local raw="${tag#v}"
  IFS='.' read -r major minor patch <<< "$raw"
  case "$part" in
    major) major=$((major+1)); minor=0; patch=0 ;;
    minor) minor=$((minor+1)); patch=0 ;;
    patch) patch=$((patch+1)) ;;
    v*) echo "$part"; return ;;
    *) echo "Invalid version arg: $part. Use patch/minor/major or vX.Y.Z" >&2; exit 1 ;;
  esac
  echo "v${major}.${minor}.${patch}"
}

new_tag=$(bump_version "$current_tag" "$VERSION_ARG")
echo "Current tag: $current_tag"
echo "New tag:     $new_tag"
echo "Branch:      $BRANCH"

git status --short
git add .
if git diff --cached --quiet; then
  echo "No staged changes to commit."
else
  git commit -m "$COMMIT_MSG"
fi

if git rev-parse "$new_tag" >/dev/null 2>&1; then
  echo "Tag $new_tag already exists. Skipping tag creation."
else
  git tag -a "$new_tag" -m "Release $new_tag"
fi

git push origin "$BRANCH"
git push origin "$new_tag"
echo "Done. Pushed commit and tag $new_tag."
