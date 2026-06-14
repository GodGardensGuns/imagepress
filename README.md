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

## Download

Download the latest `.dmg` from the GitHub Releases tab, open it, and drag `ImagePress.app` into `Applications`.

The release app is self-contained. You do not need Homebrew, Xcode command line tools, `cwebp`, or `avifenc` to run it.

Current release builds are for Apple Silicon Macs.

## Build From Source

Building from source requires:

- macOS with Xcode command line tools.
- Homebrew-installed encoder packages, because the build script copies them into the app bundle.

```sh
brew install webp libavif
```

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

To create a release DMG:

```sh
zsh work/ImagePress/package_dmg.sh 1.0.0
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

Release builds include bundled encoder components. Their notices are listed in `THIRD_PARTY_NOTICES.md`, and their license files are copied into the app bundle under `Contents/Resources/ThirdPartyLicenses/`.
