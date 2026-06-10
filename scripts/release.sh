#!/usr/bin/env bash
set -euo pipefail
COMMIT_MSG="${1:-Update app}"
VERSION_ARG="${2:-patch}"
BRANCH="${BRANCH:-main}"
current_tag=$(git tag --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -n 1 || true)
if [[ -z "$current_tag" ]]; then current_tag="v0.0.0"; fi
bump_version(){ local raw="${1#v}"; IFS='.' read -r major minor patch <<< "$raw"; case "$2" in major) major=$((major+1)); minor=0; patch=0;; minor) minor=$((minor+1)); patch=0;; patch) patch=$((patch+1));; v*) echo "$2"; return;; *) echo "Use patch/minor/major or vX.Y.Z"; exit 1;; esac; echo "v${major}.${minor}.${patch}"; }
new_tag=$(bump_version "$current_tag" "$VERSION_ARG")
git add .
if ! git diff --cached --quiet; then git commit -m "$COMMIT_MSG"; fi
if ! git rev-parse "$new_tag" >/dev/null 2>&1; then git tag -a "$new_tag" -m "Release $new_tag"; fi
git push origin "$BRANCH"
git push origin "$new_tag"
echo "Pushed $new_tag"
