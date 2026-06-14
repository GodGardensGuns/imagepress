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
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/bin" "$APP/Contents/Resources/lib" "$APP/Contents/Resources/ThirdPartyLicenses" "$MODULE_CACHE" "$BUILD_DIR"

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

copy_runtime_file() {
  local source="$1"
  local destination="$2"

  if [[ ! -f "$source" ]]; then
    echo "Missing runtime dependency: $source" >&2
    exit 1
  fi

  cp -f "$source" "$destination"
}

patch_runtime_dependencies() {
  local target="$1"
  local replacement_prefix="$2"
  local dependency_name

  while IFS= read -r dependency; do
    case "$dependency" in
      /usr/lib/*|/System/*)
        ;;
      *)
        dependency_name="$(basename "$dependency")"
        install_name_tool -change "$dependency" "$replacement_prefix/$dependency_name" "$target" 2>/dev/null || true
        ;;
    esac
  done < <(otool -L "$target" | awk 'NR > 1 { print $1 }')
}

copy_encoder_runtimes() {
  copy_runtime_file "/opt/homebrew/bin/cwebp" "$APP/Contents/Resources/bin/cwebp"
  copy_runtime_file "/opt/homebrew/bin/avifenc" "$APP/Contents/Resources/bin/avifenc"
  copy_runtime_file "/opt/homebrew/bin/pngquant" "$APP/Contents/Resources/bin/pngquant"
  copy_runtime_file "/opt/homebrew/bin/oxipng" "$APP/Contents/Resources/bin/oxipng"
  chmod 755 "$APP/Contents/Resources/bin/cwebp" "$APP/Contents/Resources/bin/avifenc" "$APP/Contents/Resources/bin/pngquant" "$APP/Contents/Resources/bin/oxipng"

  local libraries=(
    "/opt/homebrew/lib/libwebpdemux.2.dylib"
    "/opt/homebrew/lib/libwebp.7.dylib"
    "/opt/homebrew/lib/libsharpyuv.0.dylib"
    "/opt/homebrew/opt/libpng/lib/libpng16.16.dylib"
    "/opt/homebrew/opt/jpeg-turbo/lib/libjpeg.8.dylib"
    "/opt/homebrew/opt/libtiff/lib/libtiff.6.dylib"
    "/opt/homebrew/lib/libavif.16.dylib"
    "/opt/homebrew/opt/dav1d/lib/libdav1d.7.dylib"
    "/opt/homebrew/opt/aom/lib/libaom.3.dylib"
    "/opt/homebrew/opt/libvmaf/lib/libvmaf.3.dylib"
    "/opt/homebrew/opt/zstd/lib/libzstd.1.dylib"
    "/opt/homebrew/opt/xz/lib/liblzma.5.dylib"
    "/opt/homebrew/opt/little-cms2/lib/liblcms2.2.dylib"
  )

  for library in "${libraries[@]}"; do
    copy_runtime_file "$library" "$APP/Contents/Resources/lib/$(basename "$library")"
  done

  for library in "$APP/Contents/Resources/lib/"*.dylib; do
    install_name_tool -id "@rpath/$(basename "$library")" "$library" 2>/dev/null || true
    patch_runtime_dependencies "$library" "@loader_path"
  done

  patch_runtime_dependencies "$APP/Contents/Resources/bin/cwebp" "@loader_path/../lib"
  patch_runtime_dependencies "$APP/Contents/Resources/bin/avifenc" "@loader_path/../lib"
  patch_runtime_dependencies "$APP/Contents/Resources/bin/pngquant" "@loader_path/../lib"
  patch_runtime_dependencies "$APP/Contents/Resources/bin/oxipng" "@loader_path/../lib"

  local license_sources=(
    "/opt/homebrew/Cellar/webp/1.6.0/COPYING:webp-COPYING.txt"
    "/opt/homebrew/Cellar/libavif/1.4.2/LICENSE:libavif-LICENSE.txt"
    "/opt/homebrew/Cellar/aom/3.14.1/LICENSE:aom-LICENSE.txt"
    "/opt/homebrew/Cellar/dav1d/1.5.3/COPYING:dav1d-COPYING.txt"
    "/opt/homebrew/Cellar/libpng/1.6.58/LICENSE:libpng-LICENSE.txt"
    "/opt/homebrew/Cellar/jpeg-turbo/3.1.4.1/LICENSE.md:jpeg-turbo-LICENSE.md"
    "/opt/homebrew/Cellar/libtiff/4.7.1_1/LICENSE.md:libtiff-LICENSE.md"
    "/opt/homebrew/Cellar/zstd/1.5.7_1/LICENSE:zstd-LICENSE.txt"
    "/opt/homebrew/Cellar/xz/5.8.3/COPYING:xz-COPYING.txt"
    "/opt/homebrew/Cellar/libvmaf/3.1.0/LICENSE:libvmaf-LICENSE.txt"
    "/opt/homebrew/Cellar/pngquant/3.0.3/COPYRIGHT:pngquant-COPYRIGHT.txt"
    "/opt/homebrew/Cellar/oxipng/10.1.1/LICENSE:oxipng-LICENSE.txt"
    "/opt/homebrew/Cellar/little-cms2/2.19/LICENSE:little-cms2-LICENSE.txt"
  )

  for entry in "${license_sources[@]}"; do
    local source="${entry%%:*}"
    local destination_name="${entry##*:}"
    if [[ -f "$source" ]]; then
      cp -f "$source" "$APP/Contents/Resources/ThirdPartyLicenses/$destination_name"
    fi
  done
}

copy_encoder_runtimes
cp "$WORK_ROOT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"

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
