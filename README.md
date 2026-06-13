# ImagePress

ImagePress is a native macOS batch image compressor. It runs locally, supports large batches, and exports compressed images as folders or zip files.

## Features

- Drag in images or folders.
- Export to JPEG, PNG, WebP, AVIF, HEIC, TIFF, GIF, BMP, or JPEG 2000.
- Keep the original format when possible.
- Adjust quality and compression method.
- Optionally strip metadata.
- Optionally resize by maximum width/height.
- Export results as a folder or a zip file.
- Cancel a running compression job.
- Includes light and dark app icon assets.

## Requirements

- macOS with Xcode command line tools.
- `cwebp` for WebP export.
- `avifenc` for AVIF export.

If you use Homebrew:

```sh
brew install webp libavif
```

## Build

From the repo root:

```sh
zsh work/ImagePress/build.sh
```

The built app is written to:

```text
outputs/ImagePress.app
```

To install locally:

```sh
ditto outputs/ImagePress.app /Applications/ImagePress.app
```

## Test

The app includes a small self-test for JPEG, WebP, AVIF, zip cleanup, and cancellation:

```sh
outputs/ImagePress.app/Contents/MacOS/ImagePress --self-test
```

## Icon Assets

- Default light icon: `work/ImagePress/Assets/ImagePressIconSource.png`
- Alternate dark icon: `work/ImagePress/Assets/ImagePressIconAlternativeDark.png`

## License

ImagePress is licensed under the GNU General Public License v3.0. See `LICENSE`.
