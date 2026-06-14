#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
WORK_ROOT="$(cd "$ROOT/../.." && pwd)"
VERSION="${1:-1.0.0}"
DMG="$WORK_ROOT/outputs/ImagePress-${VERSION}-arm64.dmg"
STAGING="$WORK_ROOT/work/dmg-staging"

zsh "$ROOT/build.sh"

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
ditto "$WORK_ROOT/outputs/ImagePress.app" "$STAGING/ImagePress.app"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
  -volname "ImagePress" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  "$DMG" >/dev/null

echo "$DMG"
