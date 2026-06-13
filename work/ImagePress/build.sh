#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
WORK_ROOT="$(cd "$ROOT/../.." && pwd)"
APP="$WORK_ROOT/outputs/ImagePress.app"
ICON_SOURCE="$ROOT/Assets/ImagePressIconSource.png"
MODULE_CACHE="$WORK_ROOT/work/module-cache"
BUILD_DIR="$WORK_ROOT/work/build"
ICONSET="$BUILD_DIR/ImagePressIcon.iconset"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$MODULE_CACHE" "$BUILD_DIR"

cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
printf "APPL????" > "$APP/Contents/PkgInfo"

if [[ -f "$ICON_SOURCE" ]]; then
  rm -rf "$ICONSET"
  mkdir -p "$ICONSET"
  sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET/icon_16x16.png" >/dev/null
  sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET/icon_32x32.png" >/dev/null
  sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET/icon_128x128.png" >/dev/null
  sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET/icon_256x256.png" >/dev/null
  sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
  python3 "$ROOT/make_icns.py" "$ICONSET" "$APP/Contents/Resources/ImagePressIcon.icns"
fi

xcrun swiftc \
  -swift-version 5 \
  -parse-as-library \
  -module-cache-path "$MODULE_CACHE" \
  -target arm64-apple-macosx14.0 \
  -O \
  -framework AppKit \
  -framework CoreGraphics \
  -framework ImageIO \
  -framework SwiftUI \
  -framework UniformTypeIdentifiers \
  "$ROOT/Sources/ImagePress.swift" \
  -o "$APP/Contents/MacOS/ImagePress"

codesign --force --deep --sign - "$APP" >/dev/null
echo "$APP"
